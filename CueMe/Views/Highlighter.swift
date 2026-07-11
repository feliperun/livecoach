import SwiftUI
import NaturalLanguage

/// Realça a tradução para leitura rápida sob pressão. Em vez de negrito uniforme,
/// cria uma HIERARQUIA visual on-device (via NaturalLanguage POS + entidades):
///
///  • forte    (nome próprio · número · keyterm)  → cor de acento, semibold, +1pt
///  • conteúdo (substantivo · verbo · adjetivo)    → cor primária, medium
///  • função   (artigo · preposição · pronome…)    → secundária, regular
///
/// O olho pousa nos termos fortes primeiro, o conteúdo sustenta, as palavras
/// funcionais recuam. Tudo em ms, sem rede, sem LLM.
enum Highlighter {

    private static let content: Set<NLTag> = [.noun, .verb, .adjective, .adverb, .number, .otherWord]

    static func translation(
        _ text: String,
        native: String,
        keyterms: [String],
        base: CGFloat = 14
    ) -> AttributedString {
        guard !text.isEmpty else { return AttributedString(text) }

        let tagger = NLTagger(tagSchemes: [.lexicalClass, .nameType])
        tagger.string = text
        if let lang = NLLanguage(rawValueOrNil: SessionBrief.baseCode(native)) {
            tagger.setLanguage(lang, range: text.startIndex..<text.endIndex)
        }
        let keySet = Set(keyterms.map { $0.lowercased() })
        let opts: NLTagger.Options = [.omitPunctuation, .omitWhitespace]

        var result = AttributedString()
        var cursor = text.startIndex

        tagger.enumerateTags(in: text.startIndex..<text.endIndex,
                             unit: .word, scheme: .lexicalClass, options: opts) { tag, range in
            // Texto entre tokens (espaços/pontuação) — estilo neutro/função.
            if cursor < range.lowerBound {
                result += styled(String(text[cursor..<range.lowerBound]), .function, base)
            }
            let word = String(text[range])
            let name = tagger.tag(at: range.lowerBound, unit: .word, scheme: .nameType).0
            let isName = name == .personalName || name == .placeName || name == .organizationName
            let isKey = keySet.contains(word.lowercased())

            let tier: Tier
            if isName || tag == .number || isKey { tier = .strong }
            else if let tag, content.contains(tag) { tier = .content }
            else { tier = .function }

            result += styled(word, tier, base)
            cursor = range.upperBound
            return true
        }
        if cursor < text.endIndex {
            result += styled(String(text[cursor...]), .function, base)
        }
        return result
    }

    private enum Tier { case strong, content, function }

    private static func styled(_ s: String, _ tier: Tier, _ base: CGFloat) -> AttributedString {
        var a = AttributedString(s)
        switch tier {
        case .strong:
            a.foregroundColor = Theme.cyan
            a.font = .system(size: base + 1, weight: .semibold)
        case .content:
            a.foregroundColor = .primary.opacity(0.92)
            a.font = .system(size: base, weight: .medium)
        case .function:
            a.foregroundColor = .secondary
            a.font = .system(size: base, weight: .regular)
        }
        return a
    }
}

private extension NLLanguage {
    init?(rawValueOrNil code: String) {
        let map: [String: NLLanguage] = [
            "pt": .portuguese, "en": .english, "es": .spanish,
            "fr": .french, "de": .german, "it": .italian,
        ]
        guard let lang = map[code.lowercased()] else { return nil }
        self = lang
    }
}
