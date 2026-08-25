import Foundation
import Testing
@testable import OpenFlow

@Suite("OpenFlow multilingual behavior")
struct OpenFlowTests {
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

    @Test("it(\"should select English only when it clears the configured margin\")")
    func englishDetectionMargin() {
        let language = TranscriptionEngine.resolvedLanguage(
            probabilities: ["es": 0.40, "en": 0.59],
            primaryLanguage: "es"
        )
        #expect(language == "es")
    }

    @Test("it(\"should select English when it clearly leads the primary language\")")
    func englishDetectionLead() {
        let language = TranscriptionEngine.resolvedLanguage(
            probabilities: ["it": 0.40, "en": 0.61],
            primaryLanguage: "it"
        )
        #expect(language == "en")
    }

    @Test("it(\"should provide the same localization keys in all five languages\")")
    func localizationCoverage() {
        let keySets = AppLanguage.allCases.map(L10n.keys)
        #expect(!keySets[0].isEmpty && keySets.dropFirst().allSatisfy { $0 == keySets[0] })
    }

    @Test("it(\"should configure translation from the selected primary language\")")
    func translationSourceLanguage() {
        let defaults = makeDefaults()
        defaults.set("it", forKey: "primaryLanguage")
        #expect(Preferences(defaults: defaults).translationConfiguration.sourceLanguage == .italian)
    }

    @Test("it(\"should expose unique named Core Audio input devices\")")
    func audioInputDevices() {
        let devices = AudioDeviceManager().inputDevices()
        #expect(devices.allSatisfy { !$0.id.isEmpty && !$0.name.isEmpty } && Set(devices.map(\.id)).count == devices.count)
    }

    private func makePreferences() -> Preferences {
        Preferences(defaults: makeDefaults())
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "OpenFlowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
