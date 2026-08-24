import Foundation
import WhisperKit

/// Wraps WhisperKit: downloads and loads a Core ML Whisper model, then turns
/// 16 kHz mono samples into text.
actor TranscriptionEngine {
    struct Model: Identifiable, Hashable {
        let id: String
        let label: String
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
                return "Model nie jest jeszcze załadowany."
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
        .init(id: "openai_whisper-large-v3-v20240930_turbo", label: "Large v3 Turbo — domyślny, najszybszy"),
        .init(id: "openai_whisper-large-v3-v20240930_626MB", label: "Large v3 Turbo — lekki (626 MB)"),
        .init(id: "openai_whisper-large-v3_947MB", label: "Large v3 — wolniejszy, pełny dekoder"),
        .init(id: "openai_whisper-large-v3", label: "Large v3 — pełna precyzja (~3 GB)"),
        .init(id: "openai_whisper-small", label: "Small — tylko do testów"),
    ]

    static let defaultModel = "openai_whisper-large-v3-v20240930_turbo"

    /// The languages we dictate in. Whisper's unconstrained detector happily
    /// picks Czech or Slovak for Polish speech, which wrecks the transcript, so
    /// we only ever choose between these two.
    private static let candidateLanguages = ["pl", "en"]

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
            report(.failed("Nie udało się przygotować modelu: \(error.localizedDescription)"))
        }
    }

    /// `language` nil runs the pl/en detector; "pl"/"en" forces that language
    /// (the TAB-cycled mode from the pill).
    func transcribe(_ samples: [Float], language: String? = nil) async throws -> String {
        guard let pipeline else { throw EngineError.notReady }

        let resolved: String
        if let language {
            resolved = language
        } else {
            resolved = await detectLanguage(samples, using: pipeline)
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
    func translateNatively(_ samples: [Float]) async throws -> String {
        guard let pipeline else { throw EngineError.notReady }

        let options = DecodingOptions(
            task: .translate,
            language: "pl",
            detectLanguage: false,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            chunkingStrategy: .vad
        )

        let results = try await pipeline.transcribe(audioArray: samples, decodeOptions: options)
        let text = results.map(\.text).joined(separator: " ")
        return Self.stripHallucinations(text)
    }

    /// Picks Polish or English by comparing just those two probabilities.
    ///
    /// English wins only when it is clearly ahead. Dev-speak Polish is full of
    /// English terms ("code review", "PR", "deploy"), which drags the detector
    /// towards `en`; a mistaken `en` makes Whisper *translate* Polish speech
    /// instead of transcribing it, which is the worst possible failure. A
    /// mistaken `pl` on English speech merely garbles a dictation that the
    /// user can redo with TAB→EN.
    private static let englishMargin: Float = 0.2

    private func detectLanguage(_ samples: [Float], using pipeline: WhisperKit) async -> String {
        do {
            let (_, probabilities) = try await pipeline.detectLangauge(audioArray: samples)
            let pl = probabilities["pl"] ?? 0
            let en = probabilities["en"] ?? 0
            let language = en > pl + Self.englishMargin ? "en" : "pl"
            NSLog("OpenFlow: detekcja języka: %@ (pl=%.3f en=%.3f)", language, pl, en)
            return language
        } catch {
            NSLog("OpenFlow: detekcja języka nie powiodła się (%@), wymuszam pl", error.localizedDescription)
            return "pl"
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
