import Foundation

/// Pure language-selection policy used after Whisper produces token logits.
/// Keeping it separate makes the conservative primary-versus-English bias
/// explicit and independently testable without moving a pipeline across actors.
enum LanguageDetector {
    /// English wins only when it is clearly ahead. Developer speech in a
    /// primary language often contains enough English terms to skew Whisper.
    private static let englishMargin: Float = 0.2

    static func resolvedLanguage(
        probabilities: [String: Float],
        primaryLanguage: String
    ) -> String {
        let primary = probabilities[primaryLanguage] ?? 0
        let english = probabilities["en"] ?? 0
        return english > primary + englishMargin ? "en" : primaryLanguage
    }

    /// Softmax over the language tokens only, matching how Whisper itself
    /// picks a language.
    static func probabilities(logits: [String: Float]) -> [String: Float] {
        guard let maxLogit = logits.values.max() else { return [:] }
        let scaled = logits.mapValues { exp($0 - maxLogit) }
        let total = scaled.values.reduce(0, +)
        return scaled.mapValues { $0 / total }
    }

}
