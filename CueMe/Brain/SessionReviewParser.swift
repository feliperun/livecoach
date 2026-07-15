import Foundation

enum SessionReviewParser {
    static func parseTakeaways(_ output: String) -> [SessionTakeaway] {
        let normalized = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.uppercased() != "NENHUMA" else { return [] }
        return normalized.split(whereSeparator: \Character.isNewline).compactMap { raw in
            var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            for prefix in ["- [ ] ", "- [x] ", "- [X] ", "- ", "* "] where text.hasPrefix(prefix) {
                text.removeFirst(prefix.count); break
            }
            if let dot = text.firstIndex(of: "."), !text[..<dot].isEmpty, text[..<dot].allSatisfy(\.isNumber) {
                text = String(text[text.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
            }
            return text.isEmpty ? nil : SessionTakeaway(text: text)
        }
    }

    static func parseReview(_ output: String, preserving existing: MeetingMinutes) -> SessionReviewExtraction? {
        struct Payload: Decodable {
            struct Topic: Decodable { let title: String; let summary: String }
            let overview: String; let topics: [Topic]; let decisions: [String]
            let actions: [String]; let openQuestions: [String]; let followUp: String
        }
        var value = output.replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = value.firstIndex(of: "{"), let end = value.lastIndex(of: "}") else { return nil }
        value = String(value[start...end])
        guard let payload = try? JSONDecoder().decode(Payload.self, from: Data(value.utf8)) else { return nil }
        let old = Dictionary(uniqueKeysWithValues: existing.topics.map {
            ($0.title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current), $0)
        })
        let clean: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let topics = payload.topics.prefix(12).compactMap { topic -> MeetingTopic? in
            let title = clean(topic.title), summary = clean(topic.summary)
            guard !title.isEmpty, !summary.isEmpty else { return nil }
            let key = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            return MeetingTopic(id: old[key]?.id ?? UUID(), title: title, summary: summary)
        }
        let decisions = payload.decisions.prefix(20).map(clean).filter { !$0.isEmpty }.map { MeetingReviewItem(text: $0) }
        let questions = payload.openQuestions.prefix(20).map(clean).filter { !$0.isEmpty }.map { MeetingReviewItem(text: $0) }
        let actions = payload.actions.prefix(30).map(clean).filter { !$0.isEmpty }.map { SessionTakeaway(text: $0) }
        let minutes = MeetingMinutes(overview: clean(payload.overview), topics: topics, updatedAt: Date())
        let review = MeetingReview(decisions: decisions, openQuestions: questions, followUp: clean(payload.followUp))
        guard !minutes.isEmpty || !actions.isEmpty || !review.isEmpty else { return nil }
        return .init(minutes: minutes, takeaways: actions, review: review)
    }
}
