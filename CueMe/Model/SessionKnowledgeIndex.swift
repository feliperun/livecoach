import Foundation

enum HistoryDateFilter: String, CaseIterable, Sendable, Identifiable {
    case all, today, last7Days, last30Days, thisYear
    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "Qualquer data"
        case .today: return "Hoje"
        case .last7Days: return "Últimos 7 dias"
        case .last30Days: return "Últimos 30 dias"
        case .thisYear: return "Este ano"
        }
    }

    func contains(_ date: Date, now: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .all: return true
        case .today: return calendar.isDate(date, inSameDayAs: now)
        case .last7Days: return date >= now.addingTimeInterval(-7 * 86_400) && date <= now
        case .last30Days: return date >= now.addingTimeInterval(-30 * 86_400) && date <= now
        case .thisYear:
            return calendar.component(.year, from: date) == calendar.component(.year, from: now)
        }
    }
}

enum HistoryTypeFilter: String, CaseIterable, Sendable, Identifiable {
    case all, live, imported, voiceMemo, interview, meeting, recording
    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "Todos os tipos"
        case .live: return "Sessões ao vivo"
        case .imported: return "Áudios importados"
        case .voiceMemo: return "Voice Memos"
        case .interview: return "Entrevistas"
        case .meeting: return "Reuniões"
        case .recording: return "Somente gravação"
        }
    }

    func matches(_ record: SessionRecord) -> Bool {
        switch self {
        case .all: return true
        case .live: return record.origin == .live
        case .imported: return record.origin != .live
        case .voiceMemo: return record.origin == .voiceMemo
        case .interview: return record.mode == .interview
        case .meeting: return record.mode == .meeting
        case .recording: return record.mode == .recording
        }
    }
}

struct SessionSearchResult: Sendable, Equatable {
    let recordID: UUID
    let score: Int
    let snippet: String?
}

struct SessionKnowledgeIndex: Sendable {
    private struct Field: Sendable {
        let original: String
        let normalized: String
        let weight: Int
    }

    private struct Document: Sendable {
        let id: UUID
        let startedAt: Date
        let origin: SessionOrigin
        let mode: Mode
        let fields: [Field]
    }

    private var documents: [Document]

    init(records: [SessionRecord] = []) {
        documents = records.map(Self.document)
    }

    mutating func rebuild(_ records: [SessionRecord]) {
        documents = records.map(Self.document)
    }

    func search(
        query: String,
        date: HistoryDateFilter,
        type: HistoryTypeFilter,
        now: Date = Date()
    ) -> [SessionSearchResult] {
        let normalizedQuery = Self.normalize(query)
        let tokens = normalizedQuery.split(separator: " ").map(String.init)
        return documents.compactMap { document -> (result: SessionSearchResult, date: Date)? in
            guard date.contains(document.startedAt, now: now), Self.matches(type, document) else { return nil }
            guard !tokens.isEmpty else {
                return (SessionSearchResult(recordID: document.id, score: 0, snippet: nil), document.startedAt)
            }
            guard tokens.allSatisfy({ token in document.fields.contains { $0.normalized.contains(token) } }) else {
                return nil
            }
            var score = 0
            var best: (weight: Int, text: String)?
            for field in document.fields {
                let matches = tokens.filter(field.normalized.contains).count
                guard matches > 0 else { continue }
                let phraseBonus = field.normalized.contains(normalizedQuery) ? field.weight * 2 : 0
                score += matches * field.weight + phraseBonus
                if best == nil || field.weight > best!.weight { best = (field.weight, field.original) }
            }
            return (
                SessionSearchResult(
                    recordID: document.id,
                    score: score,
                    snippet: best.map { String($0.text.prefix(140)) }
                ),
                document.startedAt
            )
        }
        .sorted { lhs, rhs in
            if lhs.result.score != rhs.result.score { return lhs.result.score > rhs.result.score }
            return lhs.date > rhs.date
        }
        .map(\.result)
    }

    private static func matches(_ filter: HistoryTypeFilter, _ document: Document) -> Bool {
        switch filter {
        case .all: return true
        case .live: return document.origin == .live
        case .imported: return document.origin != .live
        case .voiceMemo: return document.origin == .voiceMemo
        case .interview: return document.mode == .interview
        case .meeting: return document.mode == .meeting
        case .recording: return document.mode == .recording
        }
    }

    private static func document(_ record: SessionRecord) -> Document {
        var fields = [Field(original: record.title, normalized: normalize(record.title), weight: 8)]
        func append(_ value: String, weight: Int) {
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            fields.append(.init(original: text, normalized: normalize(text), weight: weight))
        }
        append(record.goal, weight: 7)
        append(record.minutes.overview, weight: 6)
        record.minutes.topics.forEach { append($0.title, weight: 8); append($0.summary, weight: 6) }
        record.review.decisions.forEach { append($0.text, weight: 5) }
        record.review.openQuestions.forEach { append($0.text, weight: 5) }
        append(record.review.followUp, weight: 5)
        record.takeaways.forEach { append($0.text, weight: 5) }
        record.notes.forEach { append($0.text, weight: 5) }
        record.transcript.filter(\.isFinal).forEach { append($0.text, weight: 2) }
        record.artifacts.forEach { append($0.title, weight: 4); append($0.body, weight: 2) }
        return .init(id: record.id, startedAt: record.startedAt, origin: record.origin, mode: record.mode, fields: fields)
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .joined(separator: " ")
    }
}
