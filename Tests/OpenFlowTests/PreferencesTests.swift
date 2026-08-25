import Testing
@testable import OpenFlow

@Suite("Preferences")
struct PreferencesTests {
    @Test("it(\"should use English UI, Polish primary, Auto mode and system microphone by default\")")
    func defaultPreferences() {
        let preferences = makePreferences()
        #expect((preferences.appLanguage, preferences.primaryLanguage, preferences.languageMode, preferences.selectedInputDeviceUID) == (.english, .polish, .auto, nil))
    }

    @Test("it(\"should migrate the legacy Polish mode to the semantic primary mode\")")
    func legacyPolishMigration() {
        let defaults = makeDefaults()
        defaults.set("pl", forKey: "languageMode")
        #expect(Preferences(defaults: defaults).languageMode == .primary)
    }

    @Test("it(\"should resolve the primary dictation code for every supported language\")")
    func primaryLanguageCodes() {
        let codes = PrimaryLanguage.allCases.map {
            LanguageMode.primary.whisperCode(primaryLanguage: $0)
        }
        #expect(codes == ["pl", "it", "es", "bg"])
    }

    @Test("it(\"should always cycle Auto, Primary and English\")")
    func languageModeCycle() {
        #expect([LanguageMode.auto.next, LanguageMode.primary.next, LanguageMode.english.next] == [.primary, .english, .auto])
    }

    @Test("it(\"should display Auto with title casing\")")
    func autoDisplayLabel() {
        #expect(LanguageMode.auto.shortLabel(primaryLanguage: .polish) == "Auto")
    }

    @Test("it(\"should configure translation from the selected primary language\")")
    func translationSourceLanguage() {
        let defaults = makeDefaults()
        defaults.set("it", forKey: "primaryLanguage")
        #expect(Preferences(defaults: defaults).translationConfiguration.sourceLanguage == .italian)
    }
}
