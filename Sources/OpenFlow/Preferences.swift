import Foundation
import Observation
import ServiceManagement

enum PrimaryLanguage: String, CaseIterable, Identifiable {
    case polish = "pl"
    case italian = "it"
    case spanish = "es"
    case bulgarian = "bg"

    var id: String { rawValue }

    var shortLabel: String { rawValue.uppercased() }

    func label(language: AppLanguage) -> String {
        L10n.text("language.\(rawValue)", language: language)
    }
}

/// The semantic dictation mode. The primary language is configured separately.
enum LanguageMode: String, CaseIterable, Identifiable {
    case auto
    case primary
    case english = "en"

    var id: String { rawValue }

    /// What Whisper gets; nil means run the primary/English detector.
    func whisperCode(primaryLanguage: PrimaryLanguage) -> String? {
        switch self {
        case .auto: return nil
        case .primary: return primaryLanguage.rawValue
        case .english: return "en"
        }
    }

    func label(primaryLanguage: PrimaryLanguage, language: AppLanguage) -> String {
        switch self {
        case .auto: return L10n.text("language.auto", language: language)
        case .primary: return primaryLanguage.label(language: language)
        case .english: return L10n.text("language.en", language: language)
        }
    }

    func shortLabel(primaryLanguage: PrimaryLanguage) -> String {
        switch self {
        case .auto: return "Auto"
        case .primary: return primaryLanguage.shortLabel
        case .english: return "EN"
        }
    }

    var next: LanguageMode {
        switch self {
        case .auto: return .primary
        case .primary: return .english
        case .english: return .auto
        }
    }
}

/// Output tone, used by both hotkeys: dictation cleanup and translation to English.
/// Normal is polished prose; loose is chat-style, lowercase, no full stops.
enum TextStyle: String, CaseIterable, Identifiable {
    case normal
    case loose

    var id: String { rawValue }

    func label(language: AppLanguage) -> String {
        switch self {
        case .normal: return L10n.text("style.normal", language: language)
        case .loose: return L10n.text("style.loose", language: language)
        }
    }

    var next: TextStyle {
        self == .normal ? .loose : .normal
    }

    /// Models keep adding sentence-ending periods no matter how the loose
    /// prompt is worded, so they are stripped here. Ellipses, "?" and "!"
    /// are left alone.
    func finish(_ text: String) -> String {
        guard self == .loose else { return text }
        return text
            .components(separatedBy: "\n")
            .map { line in
                var trimmed = Substring(line.trimmingCharacters(in: .whitespaces))
                while trimmed.hasSuffix("."), !trimmed.hasSuffix("...") {
                    trimmed = trimmed.dropLast()
                }
                return String(trimmed)
            }
            .joined(separator: "\n")
    }
}

/// User-facing settings. Everything lives in UserDefaults except the API key,
/// which is read from the environment on each access.
@Observable
final class Preferences {
    private enum Key {
        static let legacyPushToTalk = "pushToTalkKey"
        static let dictationHotkey = "dictationHotkey"
        static let translationHotkey = "translationHotkey"
        static let languageMode = "languageMode"
        static let primaryLanguage = "primaryLanguage"
        static let appLanguage = "appLanguage"
        static let selectedInputDeviceUID = "selectedInputDeviceUID"
        static let dictationStyle = "dictationStyle"
        static let translationStyle = "translationStyle"
        static let cleanupEnabled = "cleanupEnabled"
        static let cleanupBaseURL = "cleanupBaseURL"
        static let cleanupModel = "cleanupModel"
        static let cleanupTimeout = "cleanupTimeout"
        static let customInstructions = "customInstructions"
        static let whisperModel = "whisperModel"
        static let playSounds = "playSounds"
    }

    /// The cleanup API key comes from the environment, never from the UI.
    /// GUI apps inherit launchd's environment, not the shell's, so this is set
    /// with `launchctl setenv OPENROUTER_API_KEY ...`, not in .zshrc.
    static let apiKeyVariable = "OPENROUTER_API_KEY"

    private let defaults: UserDefaults

    var dictationHotkey: HotkeySpec {
        didSet { Self.store(dictationHotkey, in: defaults, forKey: Key.dictationHotkey) }
    }

    var translationHotkey: HotkeySpec {
        didSet { Self.store(translationHotkey, in: defaults, forKey: Key.translationHotkey) }
    }

    var languageMode: LanguageMode {
        didSet { defaults.set(languageMode.rawValue, forKey: Key.languageMode) }
    }

    var primaryLanguage: PrimaryLanguage {
        didSet { defaults.set(primaryLanguage.rawValue, forKey: Key.primaryLanguage) }
    }

    var appLanguage: AppLanguage {
        didSet { defaults.set(appLanguage.rawValue, forKey: Key.appLanguage) }
    }

    /// Nil follows the current system input device.
    var selectedInputDeviceUID: String? {
        didSet {
            if let selectedInputDeviceUID {
                defaults.set(selectedInputDeviceUID, forKey: Key.selectedInputDeviceUID)
            } else {
                defaults.removeObject(forKey: Key.selectedInputDeviceUID)
            }
        }
    }

    var dictationStyle: TextStyle {
        didSet { defaults.set(dictationStyle.rawValue, forKey: Key.dictationStyle) }
    }

    var translationStyle: TextStyle {
        didSet { defaults.set(translationStyle.rawValue, forKey: Key.translationStyle) }
    }

    var cleanupEnabled: Bool {
        didSet { defaults.set(cleanupEnabled, forKey: Key.cleanupEnabled) }
    }

    var cleanupBaseURL: String {
        didSet { defaults.set(cleanupBaseURL, forKey: Key.cleanupBaseURL) }
    }

    var cleanupModel: String {
        didSet { defaults.set(cleanupModel, forKey: Key.cleanupModel) }
    }

    var cleanupTimeout: Double {
        didSet { defaults.set(cleanupTimeout, forKey: Key.cleanupTimeout) }
    }

    /// Free-form extra rules folded into the cleanup prompt: name spellings,
    /// jargon, preferred formatting. This is the "personal dictionary".
    var customInstructions: String {
        didSet { defaults.set(customInstructions, forKey: Key.customInstructions) }
    }

    var whisperModel: String {
        didSet { defaults.set(whisperModel, forKey: Key.whisperModel) }
    }

    var playSounds: Bool {
        didSet { defaults.set(playSounds, forKey: Key.playSounds) }
    }

    var apiKey: String {
        ProcessInfo.processInfo.environment[Self.apiKeyVariable] ?? ""
    }

    var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("OpenFlow: nie udało się zmienić autostartu: \(error.localizedDescription)")
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.cleanupEnabled: false,
            Key.cleanupBaseURL: CleanupService.defaultBaseURL,
            Key.cleanupModel: CleanupService.defaultModel,
            Key.cleanupTimeout: 4.0,
            Key.whisperModel: TranscriptionEngine.defaultModel,
            Key.playSounds: true,
        ])

        if let stored = Self.loadHotkey(from: defaults, forKey: Key.dictationHotkey) {
            dictationHotkey = stored
        } else if let migrated = Self.migratedLegacyHotkey(from: defaults) {
            dictationHotkey = migrated
            // didSet does not fire during init, so persist by hand; the legacy
            // key is removed below and the migration must survive a relaunch.
            Self.store(migrated, in: defaults, forKey: Key.dictationHotkey)
        } else {
            dictationHotkey = .rightCommand
        }
        translationHotkey = Self.loadHotkey(from: defaults, forKey: Key.translationHotkey)
            ?? .rightControl
        let storedLanguageMode = defaults.string(forKey: Key.languageMode)
        languageMode = storedLanguageMode == "pl"
            ? .primary
            : storedLanguageMode.flatMap(LanguageMode.init(rawValue:)) ?? .auto
        primaryLanguage = defaults.string(forKey: Key.primaryLanguage)
            .flatMap(PrimaryLanguage.init(rawValue:)) ?? .polish
        appLanguage = defaults.string(forKey: Key.appLanguage)
            .flatMap(AppLanguage.init(rawValue:)) ?? .english
        selectedInputDeviceUID = defaults.string(forKey: Key.selectedInputDeviceUID)
        dictationStyle = defaults.string(forKey: Key.dictationStyle)
            .flatMap(TextStyle.init(rawValue:)) ?? .normal
        translationStyle = defaults.string(forKey: Key.translationStyle)
            .flatMap(TextStyle.init(rawValue:)) ?? .normal
        cleanupEnabled = defaults.bool(forKey: Key.cleanupEnabled)
        cleanupBaseURL = defaults.string(forKey: Key.cleanupBaseURL) ?? CleanupService.defaultBaseURL
        cleanupModel = defaults.string(forKey: Key.cleanupModel) ?? CleanupService.defaultModel
        cleanupTimeout = defaults.double(forKey: Key.cleanupTimeout)
        customInstructions = defaults.string(forKey: Key.customInstructions) ?? ""
        whisperModel = defaults.string(forKey: Key.whisperModel) ?? TranscriptionEngine.defaultModel
        playSounds = defaults.bool(forKey: Key.playSounds)
        launchAtLogin = SMAppService.mainApp.status == .enabled

        defaults.removeObject(forKey: Key.legacyPushToTalk)
    }

    // MARK: - Hotkey persistence

    private static func store(_ spec: HotkeySpec, in defaults: UserDefaults, forKey key: String) {
        if let data = try? JSONEncoder().encode(spec) {
            defaults.set(data, forKey: key)
        }
    }

    private static func loadHotkey(from defaults: UserDefaults, forKey key: String) -> HotkeySpec? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HotkeySpec.self, from: data)
    }

    /// Pre-v2 builds stored the dictation key as a `PushToTalkKey` raw value.
    private static func migratedLegacyHotkey(from defaults: UserDefaults) -> HotkeySpec? {
        switch defaults.string(forKey: Key.legacyPushToTalk) {
        case "rightCommand": return .rightCommand
        case "rightControl": return .rightControl
        case "rightOption": return HotkeySpec.modifier(forKeyCode: 61)
        case "fn": return HotkeySpec.modifier(forKeyCode: 63)
        default: return nil
        }
    }

    // MARK: - Service configurations

    var cleanupConfiguration: CleanupService.Configuration {
        .init(
            baseURL: cleanupBaseURL,
            model: cleanupModel,
            apiKey: apiKey,
            timeout: cleanupTimeout,
            customInstructions: customInstructions,
            style: dictationStyle
        )
    }

    var translationConfiguration: TranslationService.Configuration {
        .init(
            baseURL: cleanupBaseURL,
            model: cleanupModel,
            apiKey: apiKey,
            timeout: max(cleanupTimeout, 8),
            customInstructions: customInstructions,
            style: translationStyle,
            sourceLanguage: primaryLanguage
        )
    }
}
