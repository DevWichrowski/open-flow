import Testing
@testable import OpenFlow

@Suite("Transcription")
struct TranscriptionTests {
    @Test("it(\"should select English only when it clears the configured margin\")")
    func englishDetectionMargin() {
        let language = LanguageDetector.resolvedLanguage(
            probabilities: ["es": 0.40, "en": 0.59],
            primaryLanguage: "es"
        )
        #expect(language == "es")
    }

    @Test("it(\"should select English when it clearly leads the primary language\")")
    func englishDetectionLead() {
        let language = LanguageDetector.resolvedLanguage(
            probabilities: ["it": 0.40, "en": 0.61],
            primaryLanguage: "it"
        )
        #expect(language == "en")
    }

    @Test("it(\"should turn language logits into probabilities that sum to one\")")
    func languageProbabilitiesNormalized() {
        let probabilities = LanguageDetector.probabilities(
            logits: ["pl": 2.0, "en": 3.0, "de": -1.0]
        )
        #expect(abs(probabilities.values.reduce(0, +) - 1) < 0.0001)
    }

    @Test("it(\"should rank the language with the highest logit first\")")
    func languageProbabilitiesOrder() {
        let probabilities = LanguageDetector.probabilities(
            logits: ["pl": 2.0, "en": 3.0, "de": -1.0]
        )
        #expect(probabilities["en"]! > probabilities["pl"]! && probabilities["pl"]! > probabilities["de"]!)
    }

    @Test("it(\"should treat every turbo variant as unable to translate\")")
    func turboCannotTranslate() {
        let turbo = TranscriptionEngine.availableModels
            .map(\.id)
            .filter { $0.contains("v20240930") }
            .map(TranscriptionEngine.supportsTranslation)
        #expect(turbo == [false, false])
    }

    @Test("it(\"should translate locally with the full large-v3 models\")")
    func largeCanTranslate() {
        let translating = ["openai_whisper-large-v3_947MB", "openai_whisper-large-v3", "openai_whisper-small"]
            .map(TranscriptionEngine.supportsTranslation)
        #expect(translating == [true, true, true])
    }

    @Test("it(\"should remove known silence hallucinations without changing real text\")")
    func transcriptPostprocessing() {
        let processed = TranscriptPostprocessor.process(
            "Napisy: społeczność Amara.org\nReal transcript\nThanks for watching!"
        )
        #expect(processed == "Real transcript")
    }
}
