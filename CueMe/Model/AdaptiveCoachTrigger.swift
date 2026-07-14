import Foundation

/// Confidence gate for proactive coaching. Direct questions remain fast, while
/// uncertain microphone speech needs stronger evidence to avoid distracting
/// suggestions during the user's own answer.
enum AdaptiveCoachTrigger {
    static func score(text: String, speakerCertain: Bool, stablePartial: Bool) -> Double {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let words = normalized.split(separator: " ").count
        let rawScore = certaintyScore(speakerCertain)
            + questionMarkScore(normalized)
            + stabilityScore(stablePartial)
            + lengthScore(words)
            + questionCueScore(normalized)
            + indirectCueScore(normalized)
        return min(1, rawScore)
    }

    private static func certaintyScore(_ certain: Bool) -> Double { certain ? 0.45 : 0.12 }
    private static func questionMarkScore(_ text: String) -> Double { text.contains("?") ? 0.32 : 0 }
    private static func stabilityScore(_ stable: Bool) -> Double { stable ? 0.12 : 0 }

    private static func lengthScore(_ words: Int) -> Double {
        switch words {
        case 8...: return 0.13
        case 4...: return 0.08
        default: return 0
        }
    }

    private static func questionCueScore(_ text: String) -> Double {
        let cues = [
            "what", "why", "how", "when", "where", "which", "who", "could you", "can you",
            "tell me", "walk me", "describe", "would you", "do you", "have you",
            "o que", "por que", "como", "quando", "onde", "qual", "quem", "me conta", "me fala",
        ]
        return cues.contains(where: text.hasPrefix) ? 0.28 : 0
    }

    private static func indirectCueScore(_ text: String) -> Double {
        let indirect = ["tell me", "walk me", "describe", "me conta", "me fala", "descreva"]
        return indirect.contains(where: text.hasPrefix) ? 0.22 : 0
    }

    static func shouldTrigger(text: String, speakerCertain: Bool, stablePartial: Bool) -> Bool {
        score(text: text, speakerCertain: speakerCertain, stablePartial: stablePartial) >= 0.68
    }
}
