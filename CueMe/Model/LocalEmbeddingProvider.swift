import CryptoKit
import Foundation
import NaturalLanguage

protocol EmbeddingProvider: Sendable {
    var modelID: String { get }
    var dimensions: Int { get }
    func embedding(for text: String) -> [Float]
}

struct AppleSentenceEmbeddingProvider: EmbeddingProvider {
    let modelID = "apple-nl-sentence-v1"
    let dimensions = 512

    func embedding(for text: String) -> [Float] {
        let language = NLLanguageRecognizer.dominantLanguage(for: text) ?? .english
        if let model = NLEmbedding.sentenceEmbedding(for: language), let values = model.vector(for: text), !values.isEmpty {
            return normalize(values.prefix(dimensions).map(Float.init))
        }
        return normalize(hashedSubwords(text))
    }

    private func hashedSubwords(_ text: String) -> [Float] {
        let words = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased().split { $0.isWhitespace || $0.isPunctuation }.map(String.init)
        var vector = [Float](repeating: 0, count: dimensions)
        for word in words {
            let pieces = [word] + (word.count >= 3 ? (0...(word.count - 3)).map { offset in
                let start = word.index(word.startIndex, offsetBy: offset)
                return String(word[start..<word.index(start, offsetBy: 3)])
            } : [])
            for piece in pieces {
                let digest = Array(SHA256.hash(data: Data(piece.utf8)))
                vector[(Int(digest[0]) << 1 | Int(digest[1] & 1)) % dimensions] += digest[2] & 1 == 0 ? 1 : -1
            }
        }
        return vector
    }

    private func normalize(_ values: [Float]) -> [Float] {
        var result = Array(values.prefix(dimensions))
        if result.count < dimensions { result += repeatElement(0, count: dimensions - result.count) }
        let norm = sqrt(result.reduce(Float.zero) { $0 + $1 * $1 })
        return norm > 0 ? result.map { $0 / norm } : result
    }
}
