import AppKit
import SwiftUI

/// A small floating pill near the bottom of the screen showing that dictation
/// is live. The menu bar icon is not enough on its own: it is hidden whenever
/// the frontmost app is full screen, which is exactly when you are dictating.
@MainActor
final class RecordingIndicator {
    private let state: AppState
    private let panel: NSPanel

    init(state: AppState) {
        self.state = state

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let hosting = NSHostingView(rootView: IndicatorView(state: state))
        hosting.frame = panel.contentRect(forFrameRect: panel.frame)
        panel.contentView = hosting

        observeStatus()
    }

    /// `withObservationTracking` fires once, so it has to be re-armed after
    /// every change.
    private func observeStatus() {
        withObservationTracking {
            _ = state.status
        } onChange: {
            Task { @MainActor [weak self] in
                self?.syncVisibility()
                self?.observeStatus()
            }
        }
        syncVisibility()
    }

    private func syncVisibility() {
        switch state.status {
        case .recording, .transcribing, .cleaning, .translating:
            moveToBottomCenter()
            panel.orderFrontRegardless()
        default:
            panel.orderOut(nil)
        }
    }

    private func moveToBottomCenter() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(
            NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.minY + 90
            )
        )
    }
}

private struct IndicatorView: View {
    @Bindable var state: AppState

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(state.status == .recording ? .red : .secondary)
                .symbolEffect(.variableColor.iterative, isActive: true)

            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)

            if let badge {
                Text(badge)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
    }

    private var symbol: String {
        state.status == .recording ? "waveform" : "ellipsis"
    }

    private var label: String {
        switch state.status {
        case .recording: return t("indicator.listening")
        case .transcribing: return t("indicator.transcribing")
        case .cleaning: return t("indicator.cleaning")
        case .translating:
            return state.translationModelState.isPreparing
                ? t("indicator.loading_translation_model")
                : t("indicator.translating")
        default: return ""
        }
    }

    /// While recording, shows what TAB currently has selected: the dictation
    /// language or the translation style.
    private var badge: String? {
        guard state.status == .recording else { return nil }
        switch state.currentMode {
        case .dictate:
            return state.preferences.languageMode.shortLabel(
                primaryLanguage: state.preferences.primaryLanguage
            ) + " ⇥"
        case .translate:
            return state.preferences.primaryLanguage.shortLabel
                + "→EN "
                + state.preferences.translationStyle.label(language: state.preferences.appLanguage)
                + " ⇥"
        }
    }

    private func t(_ key: String) -> String {
        L10n.text(key, language: state.preferences.appLanguage)
    }
}
