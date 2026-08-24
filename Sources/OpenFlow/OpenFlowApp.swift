import SwiftUI

@main
struct OpenFlowApp: App {
    @State private var state = AppState.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(state: state)
        } label: {
            Image(systemName: state.menuBarSymbol)
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(state: state)
        }
    }
}

/// SwiftUI has no hook for "app finished launching" in a menu-bar-only app, and
/// the indicator panel needs AppKit anyway.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var indicator: RecordingIndicator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        indicator = RecordingIndicator(state: .shared)
        Task { await AppState.shared.start() }
    }
}

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
        switch status {
        case .needsPermissions: return "Brakuje uprawnień"
        case .preparingModel(let progress):
            return progress < 1
                ? "Pobieranie modelu… \(Int(progress * 100))%"
                : "Ładowanie modelu…"
        case .idle:
            return "Gotowe. \(preferences.dictationHotkey.label) dyktuje, "
                + "\(preferences.translationHotkey.label) tłumaczy na angielski."
        case .recording: return "Nagrywanie…"
        case .transcribing: return "Rozpoznawanie mowy…"
        case .cleaning: return "Poprawianie tekstu…"
        case .translating: return "Tłumaczenie…"
        case .failed(let message): return message
        }
    }
}
