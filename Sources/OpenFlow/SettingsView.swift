import SwiftUI

struct SettingsView: View {
    @Bindable var state: AppState

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("Ogólne", systemImage: "gearshape") }
            cleanupTab
                .tabItem { Label("Poprawianie AI", systemImage: "wand.and.stars") }
        }
        .frame(width: 480)
        .scenePadding()
    }

    private var generalTab: some View {
        Form {
            Section("Skróty (przytrzymaj i mów)") {
                hotkeyRow(
                    title: "Dyktowanie",
                    role: .dictate,
                    spec: state.preferences.dictationHotkey
                )
                hotkeyRow(
                    title: "Tłumaczenie PL→EN",
                    role: .translate,
                    spec: state.preferences.translationHotkey
                )

                if let error = state.captureError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(
                    [state.preferences.dictationHotkey.note,
                     state.preferences.translationHotkey.note].compactMap(\.self),
                    id: \.self
                ) { note in
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("Język dyktowania") {
                Picker("Język", selection: $state.preferences.languageMode) {
                    ForEach(LanguageMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text("To samo przełącza TAB naciśnięty w trakcie trzymania skrótu dyktowania.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Styl dyktowania") {
                Picker("Styl", selection: $state.preferences.dictationStyle) {
                    ForEach(TextStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                Text("Normalny: pełna interpunkcja i wielkie litery. Luźny: wszystko "
                     + "małymi literami, bez kropek, tylko przecinki, jak na czacie. "
                     + "Styl nakłada przebieg Poprawiania AI, więc działa przy włączonym "
                     + "poprawianiu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Styl tłumaczenia") {
                Picker("Styl", selection: $state.preferences.translationStyle) {
                    ForEach(TextStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                Text("Normalny: wierny, do PR-ów i ticketów. Luźny: swobodny, jak na Slacku. "
                     + "TAB w trakcie trzymania skrótu tłumaczenia przełącza styl. "
                     + "Bez klucza API tłumaczy lokalny Whisper (bez stylu).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Model rozpoznawania mowy") {
                Picker("Model", selection: $state.preferences.whisperModel) {
                    ForEach(TranscriptionEngine.availableModels, id: \.id) { model in
                        Text(model.label).tag(model.id)
                    }
                }
                .onChange(of: state.preferences.whisperModel) {
                    Task { await state.loadModel() }
                }
                Text("Język wykrywany automatycznie (polski / angielski). "
                     + "Modele pobierają się raz i działają offline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Zachowanie") {
                Toggle("Dźwięk startu i końca nagrywania", isOn: $state.preferences.playSounds)
                Toggle("Uruchamiaj przy logowaniu", isOn: $state.preferences.launchAtLogin)
            }

            Section("Uprawnienia") {
                LabeledContent("Mikrofon") {
                    permissionBadge(state.hasMicrophonePermission)
                }
                LabeledContent("Dostępność") {
                    permissionBadge(state.hasAccessibilityPermission)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var cleanupTab: some View {
        Form {
            Section {
                Toggle("Poprawiaj transkrypcję przez AI", isOn: $state.preferences.cleanupEnabled)
                Text("Drugi przebieg poprawia interpunkcję, usuwa „yyy” i naprawia "
                     + "polskie końcówki oraz znaki diakrytyczne. Gdy API nie odpowie "
                     + "w \(Int(state.preferences.cleanupTimeout)) s, wklejany jest surowy tekst.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Dostawca") {
                LabeledContent("Klucz API (\(Preferences.apiKeyVariable))") {
                    Label(
                        state.preferences.apiKey.isEmpty ? "Nie znaleziono" : "Wczytany ze środowiska",
                        systemImage: state.preferences.apiKey.isEmpty ? "xmark.circle.fill" : "checkmark.circle.fill"
                    )
                    .foregroundStyle(state.preferences.apiKey.isEmpty ? .red : .green)
                    .font(.caption)
                }
                if state.preferences.apiKey.isEmpty {
                    Text("Ustaw w terminalu: launchctl setenv \(Preferences.apiKeyVariable) sk-or-... "
                         + "i uruchom aplikację ponownie.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                TextField("Adres API", text: $state.preferences.cleanupBaseURL)
                TextField("Model", text: $state.preferences.cleanupModel)
                LabeledContent("Timeout") {
                    Stepper(
                        "\(state.preferences.cleanupTimeout, specifier: "%.0f") s",
                        value: $state.preferences.cleanupTimeout,
                        in: 1...20,
                        step: 1
                    )
                }
                Text("Domyślnie DeepSeek V4 Flash przez OpenRouter. "
                     + "Zadziała każde API zgodne z formatem OpenAI: "
                     + "wystarczy zmienić adres i model.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Słownik osobisty") {
                TextEditor(text: $state.preferences.customInstructions)
                    .font(.body.monospaced())
                    .frame(height: 100)
                Text("Dodatkowe reguły doklejane do promptu, np. pisownia nazwisk, "
                     + "nazwy projektów, żargon. Jedna reguła na linię.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    /// Click-then-press hotkey recorder: the button arms capture in
    /// HotkeyManager and the next key pressed becomes the binding.
    private func hotkeyRow(title: String, role: HotkeyRole, spec: HotkeySpec) -> some View {
        LabeledContent(title) {
            Button {
                if state.capturingRole == role {
                    state.cancelHotkeyCapture()
                } else {
                    state.startHotkeyCapture(role: role)
                }
            } label: {
                Text(state.capturingRole == role ? "Naciśnij klawisz… (Esc anuluje)" : spec.label)
                    .frame(minWidth: 130)
            }
            .disabled(!state.hasAccessibilityPermission)
        }
    }

    private func permissionBadge(_ granted: Bool) -> some View {
        Label(
            granted ? "Przyznane" : "Brak",
            systemImage: granted ? "checkmark.circle.fill" : "xmark.circle.fill"
        )
        .foregroundStyle(granted ? .green : .red)
        .font(.caption)
    }
}
