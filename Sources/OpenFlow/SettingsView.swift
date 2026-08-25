import SwiftUI

struct SettingsView: View {
    @Bindable var state: AppState

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label(t("settings.general"), systemImage: "gearshape") }
            cleanupTab
                .tabItem { Label(t("settings.ai_cleanup"), systemImage: "wand.and.stars") }
        }
        .frame(width: 480)
        .scenePadding()
    }

    private var generalTab: some View {
        Form {
            Section(t("settings.interface_language")) {
                Picker(t("settings.language"), selection: $state.preferences.appLanguage) {
                    ForEach(AppLanguage.allCases) { appLanguage in
                        Text(appLanguage.nativeName).tag(appLanguage)
                    }
                }
            }

            Section(t("settings.hotkeys")) {
                hotkeyRow(
                    title: t("common.dictation"),
                    role: .dictate,
                    spec: state.preferences.dictationHotkey
                )
                hotkeyRow(
                    title: t("settings.translation_to_english", state.preferences.primaryLanguage.shortLabel),
                    role: .translate,
                    spec: state.preferences.translationHotkey
                )

                if let error = state.captureError {
                    Text(t("error.hotkey_in_use", error.label(language: language)))
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(
                    [state.preferences.dictationHotkey.note(language: language),
                     state.preferences.translationHotkey.note(language: language)].compactMap(\.self),
                    id: \.self
                ) { note in
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section(t("settings.primary_language")) {
                Picker(t("settings.language"), selection: $state.preferences.primaryLanguage) {
                    ForEach(PrimaryLanguage.allCases) { primaryLanguage in
                        Text(primaryLanguage.label(language: language)).tag(primaryLanguage)
                    }
                }
                Text(t("settings.primary_language_help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(t("settings.dictation_language")) {
                Picker(t("settings.mode"), selection: $state.preferences.languageMode) {
                    ForEach(LanguageMode.allCases) { mode in
                        Text(mode.label(
                            primaryLanguage: state.preferences.primaryLanguage,
                            language: language
                        )).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text(t("settings.dictation_language_help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(t("settings.dictation_style")) {
                Picker(t("settings.style"), selection: $state.preferences.dictationStyle) {
                    ForEach(TextStyle.allCases) { style in
                        Text(style.label(language: language)).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                Text(t("settings.dictation_style_help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(t("settings.translation_style")) {
                Picker(t("settings.style"), selection: $state.preferences.translationStyle) {
                    ForEach(TextStyle.allCases) { style in
                        Text(style.label(language: language)).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                Text(t("settings.translation_style_help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(t("settings.speech_model")) {
                Picker(t("settings.model"), selection: $state.preferences.whisperModel) {
                    ForEach(TranscriptionEngine.availableModels, id: \.id) { model in
                        Text(t(model.labelKey)).tag(model.id)
                    }
                }
                .onChange(of: state.preferences.whisperModel) {
                    Task { await state.loadModel() }
                }
                Text(t(
                    "settings.model_help",
                    state.preferences.primaryLanguage.shortLabel
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(t("settings.microphone")) {
                Picker(t("settings.input_device"), selection: $state.preferences.selectedInputDeviceUID) {
                    Text(t("settings.system_default")).tag(String?.none)
                    if let selectedUID = state.preferences.selectedInputDeviceUID,
                       !state.audioInputDevices.contains(where: { $0.id == selectedUID }) {
                        Text(t("settings.unavailable_device")).tag(Optional(selectedUID))
                    }
                    ForEach(state.audioInputDevices) { device in
                        Text(device.name).tag(Optional(device.id))
                    }
                }
                Text(t("settings.microphone_help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(t("settings.behavior")) {
                Toggle(t("settings.play_sounds"), isOn: $state.preferences.playSounds)
                Toggle(t("settings.launch_at_login"), isOn: $state.preferences.launchAtLogin)
            }

            Section(t("settings.permissions")) {
                LabeledContent(t("settings.microphone")) {
                    permissionBadge(state.hasMicrophonePermission)
                }
                LabeledContent(t("settings.accessibility")) {
                    permissionBadge(state.hasAccessibilityPermission)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { state.refreshAudioInputDevices() }
    }

    private var cleanupTab: some View {
        Form {
            Section {
                Toggle(t("settings.cleanup_toggle"), isOn: $state.preferences.cleanupEnabled)
                Text(t("settings.cleanup_help", Int(state.preferences.cleanupTimeout)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(t("settings.provider")) {
                LabeledContent(t("settings.api_key", Preferences.apiKeyVariable)) {
                    Label(
                        state.preferences.apiKey.isEmpty
                            ? t("settings.not_found")
                            : t("settings.loaded_from_environment"),
                        systemImage: state.preferences.apiKey.isEmpty ? "xmark.circle.fill" : "checkmark.circle.fill"
                    )
                    .foregroundStyle(state.preferences.apiKey.isEmpty ? .red : .green)
                    .font(.caption)
                }
                if state.preferences.apiKey.isEmpty {
                    Text(t("settings.api_key_help", Preferences.apiKeyVariable))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                TextField(t("settings.api_address"), text: $state.preferences.cleanupBaseURL)
                TextField(t("settings.model"), text: $state.preferences.cleanupModel)
                LabeledContent(t("settings.timeout")) {
                    Stepper(
                        "\(state.preferences.cleanupTimeout, specifier: "%.0f") s",
                        value: $state.preferences.cleanupTimeout,
                        in: 1...20,
                        step: 1
                    )
                }
                Text(t("settings.provider_help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(t("settings.personal_dictionary")) {
                TextEditor(text: $state.preferences.customInstructions)
                    .font(.body.monospaced())
                    .frame(height: 100)
                Text(t("settings.personal_dictionary_help"))
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
                Text(
                    state.capturingRole == role
                        ? t("settings.press_key")
                        : spec.label(language: language)
                )
                    .frame(minWidth: 130)
            }
            .disabled(!state.hasAccessibilityPermission)
        }
    }

    private func permissionBadge(_ granted: Bool) -> some View {
        Label(
            granted ? t("settings.granted") : t("settings.missing"),
            systemImage: granted ? "checkmark.circle.fill" : "xmark.circle.fill"
        )
        .foregroundStyle(granted ? .green : .red)
        .font(.caption)
    }

    private var language: AppLanguage { state.preferences.appLanguage }

    private func t(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.text(key, language: language, arguments: arguments)
    }
}
