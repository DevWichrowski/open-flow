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

        var errorDescription: String? {
            switch self {
            case .notReady:
                return "The model is not loaded yet."
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

    private var pipeline: WhisperKit?
    private var loadedModel: String?

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
            // Only touch the network when the model is genuinely missing;
            // otherwise the app would refuse to start while offline.
            let cached = Self.localFolder(for: model)
            let folder: URL
            if Self.isFullyDownloaded(cached) {
                folder = cached
            } else {
                report(.downloading(0))
                folder = try await WhisperKit.download(
                    variant: model,
                    downloadBase: Self.storageDirectory,
                    from: Self.modelRepo,
                    progressCallback: { progress in
                        report(.downloading(progress.fractionCompleted))
                    }
                )
            }

            try Task.checkCancellation()
            report(.loading)

            let config = WhisperKitConfig(
                model: model,
                downloadBase: Self.storageDirectory,
                modelFolder: folder.path,
                verbose: false,
                logLevel: .error,
                prewarm: false,
                load: true,
                download: false
            )

            pipeline = try await WhisperKit(config)
            loadedModel = model
            report(.ready)
        } catch is CancellationError {
            // A newer prepare() superseded this one; it will report its own state.
        } catch {
            report(.failed(error.localizedDescription))
        }
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
        guard let pipeline else { throw EngineError.notReady }

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

    private func detectLanguage(
        _ samples: [Float],
        primaryLanguage: String,
        using pipeline: WhisperKit
    ) async -> String {
        do {
            let (_, probabilities) = try await pipeline.detectLangauge(audioArray: samples)
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
