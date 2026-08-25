import CoreML
import Foundation
import WhisperKit

/// Wraps WhisperKit: downloads and loads a Core ML Whisper model, then turns
/// 16 kHz mono samples into text.
actor TranscriptionEngine {
    struct Model: Identifiable, Hashable {
        let id: String
        let labelKey: String
    }

    enum PrepareState {
        case downloading(Double)
        case loading
        case ready
        case failed(String)
    }

    enum EngineError: LocalizedError {
        case notReady
        case languageDetectionFailed

        var errorDescription: String? {
            switch self {
            case .notReady:
                return "The model is not loaded yet."
            case .languageDetectionFailed:
                return "Language detection produced no result."
            }
        }
    }

    /// Whisper's own turbo release is the `large-v3-v20240930` family; the bare
    /// `large-v3` folders are the full 32-layer model.
    ///
    /// Measured on this machine against Polish speech, turbo transcribed 3.7×
    /// faster (speed factor 6.6 vs 1.8) with no loss on Polish diacritics or
    /// inflection, so it is the default. Full large-v3 stays available in case a
    /// harder recording disagrees with that benchmark.
    static let availableModels: [Model] = [
        .init(id: "openai_whisper-large-v3-v20240930_turbo", labelKey: "model.turbo"),
        .init(id: "openai_whisper-large-v3-v20240930_626MB", labelKey: "model.turbo_light"),
        .init(id: "openai_whisper-large-v3_947MB", labelKey: "model.large_compact"),
        .init(id: "openai_whisper-large-v3", labelKey: "model.large_full"),
        .init(id: "openai_whisper-small", labelKey: "model.small"),
    ]

    static let defaultModel = "openai_whisper-large-v3-v20240930_turbo"

    /// Turbo was fine-tuned on transcription data only, so it ignores the
    /// translate task and just transcribes. The local translation fallback
    /// therefore needs a real large-v3; the compact one keeps the download
    /// under 1 GB.
    static let translationModel = "openai_whisper-large-v3_947MB"

    static func supportsTranslation(_ model: String) -> Bool {
        !model.contains("v20240930")
    }

    private var pipeline: WhisperKit?
    private var loadedModel: String?
    /// Loaded lazily on the first fallback translation while a turbo model is selected.
    private var translationPipeline: WhisperKit?

    /// Multi-gigabyte Core ML models do not belong in ~/Documents, which is
    /// where the HuggingFace client puts them by default.
    private static var storageDirectory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "OpenFlow/models")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static let modelRepo = "argmaxinc/whisperkit-coreml"

    /// Where `WhisperKit.download` puts a variant once it has been fetched.
    private static func localFolder(for model: String) -> URL {
        storageDirectory
            .appending(path: "models")
            .appending(path: modelRepo)
            .appending(path: model)
    }

    /// The three Core ML models `loadModels()` insists on. Checking all of them
    /// means a half-finished download is treated as missing rather than loaded.
    private static func isFullyDownloaded(_ folder: URL) -> Bool {
        ["MelSpectrogram.mlmodelc", "AudioEncoder.mlmodelc", "TextDecoder.mlmodelc"].allSatisfy {
            FileManager.default.fileExists(atPath: folder.appending(path: $0).path)
        }
    }

    /// Downloads (if needed) and loads `model`, reporting progress as it goes.
    nonisolated func prepare(model: String) -> AsyncStream<PrepareState> {
        AsyncStream { continuation in
            let task = Task {
                await self.load(model: model) { continuation.yield($0) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func load(model: String, report: @escaping (PrepareState) -> Void) async {
        guard loadedModel != model || pipeline == nil else {
            report(.ready)
            return
        }

        pipeline = nil
        loadedModel = nil

        do {
            pipeline = try await Self.loadPipeline(model: model, report: report)
            loadedModel = model
            if Self.supportsTranslation(model) {
                translationPipeline = nil
            }
            report(.ready)
        } catch is CancellationError {
            // A newer prepare() superseded this one; it will report its own state.
        } catch {
            report(.failed(error.localizedDescription))
        }
    }

    private static func loadPipeline(
        model: String,
        report: @escaping (PrepareState) -> Void
    ) async throws -> WhisperKit {
        // Only touch the network when the model is genuinely missing;
        // otherwise the app would refuse to start while offline.
        let cached = localFolder(for: model)
        let folder: URL
        if isFullyDownloaded(cached) {
            folder = cached
        } else {
            report(.downloading(0))
            folder = try await WhisperKit.download(
                variant: model,
                downloadBase: storageDirectory,
                from: modelRepo,
                progressCallback: { progress in
                    report(.downloading(progress.fractionCompleted))
                }
            )
        }

        try Task.checkCancellation()
        report(.loading)

        let config = WhisperKitConfig(
            model: model,
            downloadBase: storageDirectory,
            modelFolder: folder.path,
            verbose: false,
            logLevel: .error,
            prewarm: false,
            load: true,
            download: false
        )

        return try await WhisperKit(config)
    }

    /// `language` nil runs the primary/English detector. A value forces a language.
    func transcribe(
        _ samples: [Float],
        language: String? = nil,
        primaryLanguage: String = "pl"
    ) async throws -> String {
        guard let pipeline else { throw EngineError.notReady }

        let resolved: String
        if let language {
            resolved = language
        } else {
            resolved = await detectLanguage(
                samples,
                primaryLanguage: primaryLanguage,
                using: pipeline
            )
        }

        let options = DecodingOptions(
            task: .transcribe,
            language: resolved,
            detectLanguage: false,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            chunkingStrategy: .vad
        )

        let results = try await pipeline.transcribe(audioArray: samples, decodeOptions: options)
        let text = results.map(\.text).joined(separator: " ")
        return Self.stripHallucinations(text)
    }

    /// Whisper's built-in speech translation to English. Quality is below the
    /// LLM pass but it runs fully offline, so it is the fallback when the
    /// translate hotkey has no API key or the network fails.
    func translateNatively(_ samples: [Float], language: String) async throws -> String {
        let pipeline = try await translationPipeline()

        let options = DecodingOptions(
            task: .translate,
            language: language,
            detectLanguage: false,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            chunkingStrategy: .vad
        )

        let results = try await pipeline.transcribe(audioArray: samples, decodeOptions: options)
        let text = results.map(\.text).joined(separator: " ")
        return Self.stripHallucinations(text)
    }

    /// The main pipeline when its model can translate, otherwise a dedicated
    /// large-v3 that is downloaded and loaded on first use and then kept.
    private func translationPipeline() async throws -> WhisperKit {
        guard let pipeline, let loadedModel else { throw EngineError.notReady }
        if Self.supportsTranslation(loadedModel) { return pipeline }
        if let translationPipeline { return translationPipeline }

        NSLog("OpenFlow: %@ cannot translate, loading %@", loadedModel, Self.translationModel)
        let loaded = try await Self.loadPipeline(model: Self.translationModel) { state in
            if case .downloading(let progress) = state {
                NSLog("OpenFlow: translation model download %.0f%%", progress * 100)
            }
        }
        translationPipeline = loaded
        return loaded
    }

    /// Picks the configured primary language or English.
    ///
    /// English wins only when it is clearly ahead. Dev-speak Polish is full of
    /// English terms ("code review", "PR", "deploy"), which drags the detector
    /// towards `en`; a mistaken `en` makes Whisper *translate* Polish speech
    /// instead of transcribing it, which is the worst possible failure. A
    /// mistaken `pl` on English speech merely garbles a dictation that the
    /// user can redo with TAB→EN.
    private static let englishMargin: Float = 0.2

    static func resolvedLanguage(
        probabilities: [String: Float],
        primaryLanguage: String
    ) -> String {
        let primary = probabilities[primaryLanguage] ?? 0
        let english = probabilities["en"] ?? 0
        return english > primary + englishMargin ? "en" : primaryLanguage
    }

    /// Softmax over the language tokens only, matching how Whisper itself
    /// picks a language.
    static func languageProbabilities(logits: [String: Float]) -> [String: Float] {
        guard let maxLogit = logits.values.max() else { return [:] }
        let scaled = logits.mapValues { exp($0 - maxLogit) }
        let total = scaled.values.reduce(0, +)
        return scaled.mapValues { $0 / total }
    }

    /// WhisperKit's `detectLangauge` reports only the winning language, and as
    /// a log-probability, so a primary-versus-English comparison is impossible
    /// with it. This runs the same single decoder step over the first 30 s and
    /// keeps the whole distribution.
    private func languageProbabilities(
        _ samples: [Float],
        using pipeline: WhisperKit
    ) async throws -> [String: Float] {
        guard let tokenizer = pipeline.tokenizer else { throw EngineError.notReady }
        let decoder = pipeline.textDecoder
        let window = pipeline.featureExtractor.windowSamples ?? 480_000
        let startToken = tokenizer.specialTokens.startOfTranscriptToken

        guard
            let audio = pipeline.audioProcessor.padOrTrim(fromArray: samples, startAt: 0, toLength: window),
            let mel = try await pipeline.featureExtractor.logMelSpectrogram(fromAudio: audio),
            let encoded = try await pipeline.audioEncoder.encodeFeatures(mel) as? MLMultiArray,
            let inputs = try decoder.prepareDecoderInputs(withPrompt: [startToken]) as? DecodingInputs
        else { throw EngineError.languageDetectionFailed }

        inputs.inputIds[0] = NSNumber(value: startToken)
        inputs.cacheLength[0] = 0

        let output = try await decoder.predictLogits(TextDecoderMLMultiArrayInputType(
            inputIds: inputs.inputIds,
            cacheLength: inputs.cacheLength,
            keyCache: inputs.keyCache,
            valueCache: inputs.valueCache,
            kvCacheUpdateMask: inputs.kvCacheUpdateMask,
            encoderOutputEmbeds: encoded,
            decoderKeyPaddingMask: inputs.decoderKeyPaddingMask
        )) as? TextDecoderMLMultiArrayOutputType
        guard let logits = output?.logits else { throw EngineError.languageDetectionFailed }

        var languageLogits: [String: Float] = [:]
        for token in tokenizer.allLanguageTokens {
            // Language tokens look like "<|en|>".
            guard let name = tokenizer.convertIdToToken(token) else { continue }
            let code = name.trimmingCharacters(in: CharacterSet(charactersIn: "<|>"))
            languageLogits[code] = logits[[0, 0, token] as [NSNumber]].floatValue
        }
        return Self.languageProbabilities(logits: languageLogits)
    }

    private func detectLanguage(
        _ samples: [Float],
        primaryLanguage: String,
        using pipeline: WhisperKit
    ) async -> String {
        do {
            let probabilities = try await languageProbabilities(samples, using: pipeline)
            let primary = probabilities[primaryLanguage] ?? 0
            let english = probabilities["en"] ?? 0
            let language = Self.resolvedLanguage(
                probabilities: probabilities,
                primaryLanguage: primaryLanguage
            )
            NSLog(
                "OpenFlow: language detection: %@ (%@=%.3f en=%.3f)",
                language,
                primaryLanguage,
                primary,
                english
            )
            return language
        } catch {
            NSLog(
                "OpenFlow: language detection failed (%@), using %@",
                error.localizedDescription,
                primaryLanguage
            )
            return primaryLanguage
        }
    }

    /// Whisper was trained on subtitle dumps, so near-silence makes it emit
    /// boilerplate credits. Drop those instead of pasting them.
    private static let hallucinations = [
        "napisy stworzone przez społeczność amara.org",
        "napisy: społeczność amara.org",
        "subtitles by the amara.org community",
        "zdjęcia i napisy: amara.org",
        "dziękuję za uwagę",
        "thanks for watching",
        "thank you for watching",
        "thank you",
        "you",
    ]

    private static func stripHallucinations(_ text: String) -> String {
        var lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        lines.removeAll { line in
            let normalized = line
                .lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: " .,!?-–—[]()"))
            return normalized.isEmpty || hallucinations.contains(normalized)
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
