import Testing
@testable import OpenFlow

@Suite("Application integration logic")
struct AppIntegrationLogicTests {
    @Test("it(\"should keep every active dictation phase busy\")")
    func activeDictationPhasesAreBusy() {
        let busy = [
            AppState.Status.recording,
            .transcribing,
            .cleaning,
            .translating,
        ].map(\.isBusy)
        #expect(busy == [true, true, true, true])
    }

    @Test("it(\"should restore the clipboard only when it still contains the inserted transcript\")")
    func clipboardRestoreRequiresUnchangedPasteboard() {
        let decisions = [10, 11].map {
            TextInserter.shouldRestorePasteboard(insertedChangeCount: 10, currentChangeCount: $0)
        }
        #expect(decisions == [true, false])
    }

    @Test("it(\"should provide the same localization keys in all five languages\")")
    func localizationCoverage() {
        let keySets = AppLanguage.allCases.map(L10n.keys)
        #expect(!keySets[0].isEmpty && keySets.dropFirst().allSatisfy { $0 == keySets[0] })
    }

    @Test("it(\"should expose unique named Core Audio input devices\")")
    func audioInputDevices() {
        let devices = AudioDeviceManager().inputDevices()
        #expect(devices.allSatisfy { !$0.id.isEmpty && !$0.name.isEmpty } && Set(devices.map(\.id)).count == devices.count)
    }
}
