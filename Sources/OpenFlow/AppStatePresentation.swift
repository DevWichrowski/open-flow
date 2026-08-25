import Foundation

extension AppState {
    var menuBarSymbol: String {
        switch status {
        case .needsPermissions, .failed: return "mic.slash"
        case .preparingModel: return "arrow.down.circle"
        case .idle: return "mic"
        case .recording: return "mic.fill"
        case .transcribing, .cleaning, .translating: return "waveform"
        }
    }

    var statusLabel: String {
        let language = preferences.appLanguage
        switch status {
        case .needsPermissions:
            return L10n.text("status.permissions_missing", language: language)
        case .preparingModel(let progress):
            return progress < 1
                ? L10n.text("status.downloading_model", language: language, Int(progress * 100))
                : L10n.text("status.loading_model", language: language)
        case .idle:
            return L10n.text(
                "status.ready",
                language: language,
                preferences.dictationHotkey.label(language: language),
                preferences.translationHotkey.label(language: language)
            )
        case .recording: return L10n.text("status.recording", language: language)
        case .transcribing: return L10n.text("status.transcribing", language: language)
        case .cleaning: return L10n.text("status.cleaning", language: language)
        case .translating: return L10n.text("status.translating", language: language)
        case .failed(let failure): return failure.message(language: language)
        }
    }
}
