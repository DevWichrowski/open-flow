import AppKit
import SwiftUI

/// A setup window that appears while a permission is missing. Each row shows
/// what is granted and jumps straight to the right System Settings pane. The
/// window closes on its own once everything is in place, since `AppState`
/// polls the permissions every two seconds.
@MainActor
final class PermissionsWindow {
    private let state: AppState
    private var window: NSWindow?
    /// "Later" hides the window until the next launch.
    private var dismissed = false

    init(state: AppState) {
        self.state = state
        observe()
    }

    /// `withObservationTracking` fires once, so it has to be re-armed after
    /// every change.
    private func observe() {
        withObservationTracking {
            _ = state.permissionsChecked
            _ = state.hasMicrophonePermission
            _ = state.hasAccessibilityPermission
        } onChange: {
            Task { @MainActor [weak self] in
                self?.sync()
                self?.observe()
            }
        }
        sync()
    }

    private func sync() {
        let missing = state.permissionsChecked
            && !(state.hasMicrophonePermission && state.hasAccessibilityPermission)
        if missing && !dismissed {
            show()
        } else {
            window?.close()
            window = nil
        }
    }

    private func show() {
        guard window == nil else { return }

        let view = PermissionsView(state: state) { [weak self] in
            self?.dismissed = true
            self?.sync()
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 10),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "OpenFlow"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.setContentSize(window.contentView!.fittingSize)
        window.center()
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

private struct PermissionsView: View {
    @Bindable var state: AppState
    let onLater: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "mic.badge.xmark")
                    .font(.system(size: 30))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(t("permissions.window_title")).font(.title3.bold())
                    Text(t("permissions.window_subtitle"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            permissionRow(
                granted: state.hasMicrophonePermission,
                symbol: "mic",
                title: t("settings.microphone"),
                help: t("permissions.microphone_help")
            ) {
                openPrivacyPane("Privacy_Microphone")
            }

            permissionRow(
                granted: state.hasAccessibilityPermission,
                symbol: "hand.raised",
                title: t("settings.accessibility"),
                help: t("permissions.accessibility_help")
            ) {
                state.requestAccessibilityPermission()
                openPrivacyPane("Privacy_Accessibility")
            }

            HStack {
                Spacer()
                Button(t("permissions.later"), action: onLater)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func permissionRow(
        granted: Bool,
        symbol: String,
        title: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .frame(width: 28)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title).font(.headline)
                    Label(
                        granted ? t("settings.granted") : t("settings.missing"),
                        systemImage: granted ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .foregroundStyle(granted ? .green : .red)
                    .font(.caption)
                }
                Text(help)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !granted {
                Button(t("permissions.open_settings"), action: action)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func t(_ key: String) -> String {
        L10n.text(key, language: state.preferences.appLanguage)
    }

    private func openPrivacyPane(_ anchor: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
        NSWorkspace.shared.open(url)
    }
}
