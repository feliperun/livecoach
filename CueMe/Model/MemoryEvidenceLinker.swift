import Foundation

enum MemoryEvidenceLinker {
    static func evidence(for text: String, in record: SessionRecord?) -> [MemoryEvidence] {
        guard let record else { return [] }
        let wanted = tokens(text)
        guard wanted.count >= 2 else { return [] }
        return record.transcript.filter(\.isFinal).compactMap { line in
            let candidate = tokens(line.text)
            let overlap = wanted.intersection(candidate).count
            guard Double(overlap) / Double(max(1, min(wanted.count, candidate.count))) >= 0.45 else { return nil }
            return MemoryEvidence(
                turnID: line.id,
                timestamp: line.ts.timeIntervalSince(record.audioTimelineStart),
                quote: String(line.text.prefix(280))
            )
        }.prefix(3).map { $0 }
    }

    private static func tokens(_ text: String) -> Set<String> {
        Set(text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased().split { $0.isWhitespace || $0.isPunctuation }
            .map(String.init).filter { $0.count > 2 })
    }
}
