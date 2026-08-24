import Foundation
import Observation
import ServiceManagement

/// The dictation language forced by the user, cycled with TAB while recording.
enum LanguageMode: String, CaseIterable, Identifiable {
    case auto
    case polish = "pl"
    case english = "en"

    var id: String { rawValue }

    /// What Whisper gets; nil means run the pl/en detector.
    var whisperCode: String? {
        self == .auto ? nil : rawValue
    }

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .polish: return "Polski"
        case .english: return "Angielski"
        }
    }

    var shortLabel: String {
        switch self {
        case .auto: return "Auto"
        case .polish: return "PL"
        case .english: return "EN"
        }
    }

    var next: LanguageMode {
        switch self {
        case .auto: return .polish
        case .polish: return .english
        case .english: return .auto
        }
    }
}

/// Output tone, used by both hotkeys: dictation cleanup and PL→EN translation.
/// Normal is polished prose; loose is chat-style, lowercase, no full stops.
enum TextStyle: String, CaseIterable, Identifiable {
    case normal
    case loose

    var id: String { rawValue }

    var label: String {
        switch self {
        case .normal: return "Normalny"
        case .loose: return "Luźny"
        }
    }

    var next: TextStyle {
        self == .normal ? .loose : .normal
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

    private let defaults = UserDefaults.standard

    var dictationHotkey: HotkeySpec {
        didSet { Self.store(dictationHotkey, in: defaults, forKey: Key.dictationHotkey) }
    }

    var translationHotkey: HotkeySpec {
        didSet { Self.store(translationHotkey, in: defaults, forKey: Key.translationHotkey) }
    }

    var languageMode: LanguageMode {
        didSet { defaults.set(languageMode.rawValue, forKey: Key.languageMode) }
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

    init() {
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
        languageMode = defaults.string(forKey: Key.languageMode)
            .flatMap(LanguageMode.init(rawValue:)) ?? .auto
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
            style: translationStyle
        )
    }
}
