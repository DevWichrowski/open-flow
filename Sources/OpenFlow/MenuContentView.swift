import SwiftUI

struct MenuContentView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if case .preparingModel(let progress) = state.status, progress < 1 {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
            }

            if state.status == .needsPermissions {
                permissionsSection
            }

            if state.translationModelState.isPreparing {
                translationModelSection
            } else if case .failed(let detail) = state.translationModelState {
                Label(t("translation_model.failed", detail), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let warning = state.lastWarning {
                Label(warning.message(language: language), systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !state.lastTranscript.isEmpty {
                lastTranscriptSection
            }

            Divider()

            Picker(t("menu.dictation_language"), selection: $state.preferences.languageMode) {
                ForEach(LanguageMode.allCases) { mode in
                    Text(mode.shortLabel(primaryLanguage: state.preferences.primaryLanguage)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)

            Picker(t("menu.dictation_style"), selection: $state.preferences.dictationStyle) {
                ForEach(TextStyle.allCases) { style in
                    Text(style.label(language: language)).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)

            Picker(t("menu.translation_style"), selection: $state.preferences.translationStyle) {
                ForEach(TextStyle.allCases) { style in
                    Text(style.label(language: language)).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)

            Text(t(
                "menu.hotkey_help",
                state.preferences.dictationHotkey.label(language: language),
                state.preferences.translationHotkey.label(language: language),
                state.preferences.primaryLanguage.shortLabel
            ))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Toggle(t("menu.ai_cleanup"), isOn: $state.preferences.cleanupEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(state.preferences.apiKey.isEmpty)

            if state.preferences.apiKey.isEmpty {
                Text(t("menu.api_key_missing", Preferences.apiKeyVariable))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                SettingsLink {
                    Label(t("common.settings"), systemImage: "gearshape")
                }
                // An accessory app is not frontmost, so the settings window
                // would otherwise open behind whatever the user is looking at.
                .simultaneousGesture(TapGesture().onEnded {
                    NSApp.activate(ignoringOtherApps: true)
                })
                Spacer()
                Button(t("common.quit")) { NSApp.terminate(nil) }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 320)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: state.menuBarSymbol)
                .font(.title3)
                .foregroundStyle(state.status == .recording ? .red : .primary)
            VStack(alignment: .leading, spacing: 2) {
                Text("OpenFlow").font(.headline)
                Text(state.statusLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !state.hasMicrophonePermission {
                Label(t("permissions.microphone_missing"), systemImage: "mic.slash")
                    .font(.caption)
                Button(t("permissions.open_microphone")) {
                    openPrivacyPane("Privacy_Microphone")
                }
                .controlSize(.small)
            }
            if !state.hasAccessibilityPermission {
                Label(t("permissions.accessibility_missing"), systemImage: "hand.raised")
                    .font(.caption)
                Text(t("permissions.accessibility_help"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button(t("permissions.request")) {
                    state.requestAccessibilityPermission()
                    openPrivacyPane("Privacy_Accessibility")
                }
                .controlSize(.small)
            }
        }
    }

    /// Offline translation model download/load, so a multi-minute first load
    /// reads as progress rather than a frozen app.
    private var translationModelSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if case .downloading(let progress) = state.translationModelState {
                Label(t("translation_model.downloading", Int(progress * 100)), systemImage: "arrow.down.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
            } else {
                Label(t("translation_model.loading"), systemImage: "arrow.down.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ProgressView()
                    .progressViewStyle(.linear)
            }
        }
    }

    private var lastTranscriptSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t("menu.last_transcript"))
                .font(.caption2)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(state.lastTranscript)
                    .font(.callout)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: 70, maxHeight: 120)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(state.lastTranscript, forType: .string)
            } label: {
                Label(t("common.copy"), systemImage: "doc.on.doc")
            }
            .controlSize(.small)
        }
    }

    private var language: AppLanguage { state.preferences.appLanguage }

    private func t(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.text(key, language: language, arguments)
    }

    private func openPrivacyPane(_ anchor: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
        NSWorkspace.shared.open(url)
    }
}
