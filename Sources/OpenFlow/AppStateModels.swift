import Foundation

extension AppState {
    struct Failure: Equatable {
        let key: String
        let detail: String

        func message(language: AppLanguage) -> String {
            L10n.text(key, language: language, detail)
        }
    }

    enum Notice {
        case microphoneFallback
        case cleanupFailed(String)
        case translationAPIFailed(String)
        case translationFailed(String, PrimaryLanguage)

        func message(language: AppLanguage) -> String {
            switch self {
            case .microphoneFallback:
                return L10n.text("warning.microphone_fallback", language: language)
            case .cleanupFailed(let detail):
                return L10n.text("warning.cleanup_failed", language: language, detail)
            case .translationAPIFailed(let detail):
                return L10n.text("warning.translation_api_failed", language: language, detail)
            case .translationFailed(let detail, let sourceLanguage):
                return L10n.text(
                    "warning.translation_failed",
                    language: language,
                    detail,
                    sourceLanguage.label(language: language)
                )
            }
        }
    }

    enum Status: Equatable {
        case needsPermissions
        case preparingModel(progress: Double)
        case idle
        case recording
        case transcribing
        case cleaning
        case translating
        case failed(Failure)

        var isBusy: Bool {
            switch self {
            case .recording, .transcribing, .cleaning, .translating: return true
            default: return false
            }
        }
    }

    /// The offline translation model that sits next to a turbo model. Shown in
    /// the menu and the indicator because a cold large-v3 load takes minutes.
    enum TranslationModelState: Equatable {
        case idle
        case downloading(Double)
        case loading
        case ready
        case failed(String)

        init(_ state: TranscriptionEngine.PrepareState) {
            switch state {
            case .downloading(let progress): self = .downloading(progress)
            case .loading: self = .loading
            case .ready: self = .ready
            case .failed(let message): self = .failed(message)
            }
        }

        var isPreparing: Bool {
            switch self {
            case .downloading, .loading: return true
            default: return false
            }
        }
    }

    /// Which hotkey started the current recording.
    enum DictationMode {
        case dictate
        case translate
    }
}
