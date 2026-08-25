import Foundation

/// Removes known boilerplate that Whisper emits for near-silence while leaving
/// normal transcript lines unchanged.
enum TranscriptPostprocessor {
    private static let hallucinations = [
        "napisy stworzone przez społeczność amara.org",
        "napisy: społeczność amara.org",
        "subtitles by the amara.org community",
        "zdjęcia i napisy: amara.org",
        "dziękuję za uwagę",
        "thanks for watching",
        "thank you for watching",
        "thank you",
        "you",
    ]

    static func process(_ text: String) -> String {
        var lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        lines.removeAll { line in
            let normalized = line
                .lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: " .,!?-–\u{2014}[]()"))
            return normalized.isEmpty || hallucinations.contains(normalized)
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
