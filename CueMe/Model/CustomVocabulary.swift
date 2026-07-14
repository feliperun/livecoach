import Foundation

struct CustomVocabulary: Codable, Sendable, Hashable {
    var keyterms: [String] = []
    var replacements: [String: String] = [:]

    mutating func addKeyterm(_ raw: String) {
        let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, !keyterms.contains(where: { $0.caseInsensitiveCompare(term) == .orderedSame }) else { return }
        keyterms.append(term)
        while keyterms.count > GlossaryTermPolicy.maximumTerms
                || GlossaryTermPolicy.estimatedTokenCount(keyterms) > GlossaryTermPolicy.maximumTokens {
            keyterms.removeFirst()
        }
    }

    @discardableResult
    mutating func learnCorrection(from original: String, to corrected: String) -> Bool {
        let cleanup = CharacterSet.punctuationCharacters.union(.symbols)
        let before = original.split(separator: " ").map { String($0).trimmingCharacters(in: cleanup) }
        let after = corrected.split(separator: " ").map { String($0).trimmingCharacters(in: cleanup) }
        var prefix = 0
        while prefix < min(before.count, after.count), before[prefix].caseInsensitiveCompare(after[prefix]) == .orderedSame {
            prefix += 1
        }
        var suffix = 0
        while suffix < min(before.count - prefix, after.count - prefix),
              before[before.count - 1 - suffix].caseInsensitiveCompare(after[after.count - 1 - suffix]) == .orderedSame {
            suffix += 1
        }
        let oldEnd = before.count - suffix
        let newEnd = after.count - suffix
        guard prefix < oldEnd, prefix < newEnd else { return false }
        let heard = before[prefix..<oldEnd].joined(separator: " ").lowercased()
        let canonical = after[prefix..<newEnd].joined(separator: " ")
        guard heard.split(separator: " ").count <= 5,
              canonical.split(separator: " ").count <= 5,
              heard.caseInsensitiveCompare(canonical) != .orderedSame else { return false }
        replacements[heard] = canonical
        addKeyterm(canonical)
        if replacements.count > 200, let first = replacements.keys.sorted().first {
            replacements.removeValue(forKey: first)
        }
        return true
    }

    func merged(keyterms sessionTerms: [String], participantNames: [Speaker: String]) -> CustomVocabulary {
        var result = self
        for term in sessionTerms { result.addKeyterm(term) }
        for name in participantNames.values.sorted() where name != "Você" && name != "Interlocutor" {
            result.addKeyterm(name)
        }
        return result
    }
}

enum CustomVocabularyStore {
    private static var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = base.appendingPathComponent("CueMe", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("vocabulary.json")
    }

    static func load() -> CustomVocabulary {
        guard let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(CustomVocabulary.self, from: data) else { return .init() }
        return value
    }

    static func save(_ vocabulary: CustomVocabulary) {
        guard let data = try? JSONEncoder().encode(vocabulary) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
