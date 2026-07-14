import CryptoKit
import Foundation

/// Reusable source material selected before a session (product, customer,
/// project, role, company, domain, etc.). Contexts stay local until the user
/// asks the selected LLM to derive a Deepgram glossary from them.
struct MeetingContext: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    var name: String
    var content: String

    init(id: UUID = UUID(), name: String, content: String = "") {
        self.id = id
        self.name = name
        self.content = content
    }
}

enum GlossaryGenerationState: Equatable {
    case idle
    case generating
    case ready(Int)
    case failed(String)
}

struct ContextGlossaryCache: Codable, Sendable, Equatable {
    var signature: String
    var model: CoachModel
    var terms: [String]
    var generatedAt: Date
}

/// Shared boundary policy for generated, learned and manually entered terms.
/// Deepgram documents a maximum of 100 keyterms / 500 aggregate tokens.
enum GlossaryTermPolicy {
    static let maximumTerms = 100
    static let maximumTokens = 500
    static let maximumCharactersPerTerm = 120

    static func sanitized(_ rawTerms: [String]) -> [String] {
        var result: [String] = []
        var seen: Set<String> = []
        var tokenCount = 0

        for raw in rawTerms {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let bounded = String(trimmed.prefix(maximumCharactersPerTerm))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let identity = bounded.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard !bounded.isEmpty, seen.insert(identity).inserted else { continue }

            let termTokens = estimatedTokenCount(bounded)
            guard tokenCount + termTokens <= maximumTokens else { continue }
            result.append(bounded)
            tokenCount += termTokens
            if result.count == maximumTerms { break }
        }
        return result
    }

    /// Conservative local estimate. The provider tokenizer is not public, so
    /// short word pieces are counted at roughly one token per four UTF-8 bytes.
    static func estimatedTokenCount(_ terms: [String]) -> Int {
        terms.reduce(0) { $0 + estimatedTokenCount($1) }
    }

    static func estimatedTokenCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).reduce(0) { count, piece in
            count + max(1, (piece.utf8.count + 3) / 4)
        }
    }
}

enum ContextGlossaryParser {
    static func parse(_ response: String) -> [String] {
        let trimmed = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let terms = decodeTerms(trimmed) {
            return GlossaryTermPolicy.sanitized(terms)
        }
        if let start = trimmed.firstIndex(of: "["), let end = trimmed.lastIndex(of: "]"), start < end,
           let terms = decodeTerms(String(trimmed[start...end])) {
            return GlossaryTermPolicy.sanitized(terms)
        }

        let fallback = trimmed
            .components(separatedBy: .newlines)
            .flatMap { $0.components(separatedBy: ";") }
            .map {
                $0.replacingOccurrences(
                    of: #"^\s*(?:[-*•]|\d+[.)])\s*"#,
                    with: "",
                    options: .regularExpression
                )
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
            }
        return GlossaryTermPolicy.sanitized(fallback)
    }

    private static func decodeTerms(_ value: String) -> [String]? {
        guard let data = value.data(using: .utf8) else { return nil }
        if let terms = try? JSONDecoder().decode([String].self, from: data) { return terms }
        if let object = try? JSONDecoder().decode([String: [String]].self, from: data) {
            return object["terms"] ?? object["keyterms"]
        }
        return nil
    }
}

enum ContextGlossaryRequest {
    static func signature(contexts: [MeetingContext], brief: SessionBrief, model: CoachModel) -> String {
        let contextBlock = contexts
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { "\($0.id.uuidString)\n\($0.name)\n\($0.content)" }
            .joined(separator: "\n---\n")
        let payload = [
            model.rawValue,
            brief.mode.rawValue,
            brief.conversationLang,
            brief.goal,
            brief.details,
            brief.keyterms.joined(separator: "\n"),
            brief.cv ?? "",
            contextBlock,
        ].joined(separator: "\n===\n")
        return SHA256.hash(data: Data(payload.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func prompt(contexts: [MeetingContext], brief: SessionBrief) -> String {
        let sources = contexts.map { context in
            "## \(context.name)\n\(String(context.content.prefix(16_000)))"
        }.joined(separator: "\n\n")
        let cv = brief.cv.map { String($0.prefix(8_000)) } ?? "(não informado)"
        let existing = brief.keyterms.isEmpty ? "(nenhum)" : brief.keyterms.joined(separator: ", ")
        return """
        Prepare o glossário para uma transcrição de reunião em \(brief.conversationLang).

        OBJETIVO: \(brief.goal)
        DETALHES: \(brief.details)
        TERMOS JÁ INFORMADOS: \(existing)

        CONTEXTOS SELECIONADOS:
        \(String(sources.prefix(40_000)))

        CV OPCIONAL:
        \(cv)

        Retorne SOMENTE um array JSON de strings, sem markdown. Busque 100 termos
        relevantes entre nomes próprios, pessoas, empresas, produtos, siglas, tecnologias e frases
        técnicas que provavelmente serão faladas e que um STT poderia errar.
        Preserve a grafia/capitalização canônica. Não inclua palavras comuns,
        explicações ou variantes duplicadas. Use menos de 100 somente quando as
        fontes não sustentarem mais termos úteis. O total deve ficar abaixo de 500 tokens.
        """
    }
}

enum MeetingContextStore {
    private static let selectedKey = "selectedMeetingContextIDs"

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = base.appendingPathComponent("CueMe", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func load() -> [MeetingContext] {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("contexts.json")),
              let contexts = try? JSONDecoder().decode([MeetingContext].self, from: data) else { return [] }
        return contexts
    }

    static func save(_ contexts: [MeetingContext]) {
        guard let data = try? JSONEncoder().encode(contexts) else { return }
        try? data.write(to: directory.appendingPathComponent("contexts.json"), options: .atomic)
    }

    static func loadSelection() -> Set<UUID> {
        let values = UserDefaults.standard.stringArray(forKey: selectedKey) ?? []
        return Set(values.compactMap(UUID.init(uuidString:)))
    }

    static func saveSelection(_ ids: Set<UUID>) {
        UserDefaults.standard.set(ids.map(\.uuidString).sorted(), forKey: selectedKey)
    }

    static func loadCache() -> ContextGlossaryCache? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("context-glossary.json")) else {
            return nil
        }
        return try? JSONDecoder().decode(ContextGlossaryCache.self, from: data)
    }

    static func saveCache(_ cache: ContextGlossaryCache) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: directory.appendingPathComponent("context-glossary.json"), options: .atomic)
    }
}
