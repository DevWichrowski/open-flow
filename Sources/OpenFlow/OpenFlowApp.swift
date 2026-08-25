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
@MainActor
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
            // Local event monitors run on the main thread, but the older AppKit
            // callback type does not express that actor isolation to Swift.
            let language = MainActor.assumeIsolated {
                AppState.shared.preferences.appLanguage
            }
            let quit = NSMenuItem(
                title: L10n.text("common.quit", language: language),
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
