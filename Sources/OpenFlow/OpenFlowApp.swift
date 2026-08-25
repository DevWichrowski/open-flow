import SwiftUI

@main
struct OpenFlowApp: App {
    @State private var state = AppState.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(state: state)
                .environment(\.locale, state.preferences.appLanguage.locale)
        } label: {
            Image(systemName: state.menuBarSymbol)
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(state: state)
                .environment(\.locale, state.preferences.appLanguage.locale)
        }
    }
}

/// SwiftUI has no hook for "app finished launching" in a menu-bar-only app, and
/// the indicator panel needs AppKit anyway.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var indicator: RecordingIndicator?
    private var permissions: PermissionsWindow?
    private var rightClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        indicator = RecordingIndicator(state: .shared)
        permissions = PermissionsWindow(state: .shared)
        installRightClickQuit()
        Task { await AppState.shared.start() }
    }

    /// `MenuBarExtra` has no right-click hook, so catch the click on the
    /// status item's own window and offer Quit there.
    private func installRightClickQuit() {
        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { event in
            guard let window = event.window,
                  window.className == "NSStatusBarWindow",
                  let view = window.contentView
            else { return event }

            let menu = NSMenu()
            let quit = NSMenuItem(
                title: L10n.text("common.quit", language: AppState.shared.preferences.appLanguage),
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
            quit.target = NSApp
            menu.addItem(quit)
            NSMenu.popUpContextMenu(menu, with: event, for: view)
            return nil
        }
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
