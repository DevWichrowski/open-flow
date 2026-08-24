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

            if let warning = state.lastWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !state.lastTranscript.isEmpty {
                lastTranscriptSection
            }

            Divider()

            Picker("Język dyktowania", selection: $state.preferences.languageMode) {
                ForEach(LanguageMode.allCases) { mode in
                    Text(mode.shortLabel).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)

            Picker("Styl dyktowania", selection: $state.preferences.dictationStyle) {
                ForEach(TextStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)

            Picker("Styl tłumaczenia", selection: $state.preferences.translationStyle) {
                ForEach(TextStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)

            Text("Przytrzymaj \(state.preferences.dictationHotkey.label): dyktowanie · "
                 + "\(state.preferences.translationHotkey.label): tłumaczenie PL→EN · "
                 + "TAB w trakcie przełącza.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Toggle("Poprawiaj tekst przez AI", isOn: $state.preferences.cleanupEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(state.preferences.apiKey.isEmpty)

            if state.preferences.apiKey.isEmpty {
                Text("Brak klucza: ustaw zmienną \(Preferences.apiKeyVariable) (szczegóły w Ustawieniach).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                SettingsLink {
                    Label("Ustawienia…", systemImage: "gearshape")
                }
                // An accessory app is not frontmost, so the settings window
                // would otherwise open behind whatever the user is looking at.
                .simultaneousGesture(TapGesture().onEnded {
                    NSApp.activate(ignoringOtherApps: true)
                })
                Spacer()
                Button("Zakończ") { NSApp.terminate(nil) }
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
                Label("Brak dostępu do mikrofonu", systemImage: "mic.slash")
                    .font(.caption)
                Button("Otwórz ustawienia mikrofonu") {
                    openPrivacyPane("Privacy_Microphone")
                }
                .controlSize(.small)
            }
            if !state.hasAccessibilityPermission {
                Label("Brak uprawnienia Dostępność", systemImage: "hand.raised")
                    .font(.caption)
                Text("Potrzebne, żeby wykrywać skrót i wklejać tekst.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button("Poproś o uprawnienie") {
                    state.requestAccessibilityPermission()
                    openPrivacyPane("Privacy_Accessibility")
                }
                .controlSize(.small)
            }
        }
    }

    private var lastTranscriptSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Ostatnia transkrypcja")
                .font(.caption2)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(state.lastTranscript)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 90)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(state.lastTranscript, forType: .string)
            } label: {
                Label("Kopiuj", systemImage: "doc.on.doc")
            }
            .controlSize(.small)
        }
    }

    private func openPrivacyPane(_ anchor: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
        NSWorkspace.shared.open(url)
    }
}
