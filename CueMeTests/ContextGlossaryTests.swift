import XCTest
@testable import CueMe

final class ContextGlossaryTests: XCTestCase {
    func testParserAcceptsJSONArrayDeduplicatesAndPreservesPreferredCasing() {
        let response = #"["CueMe", "DeepSeek V4", "cueme", "Sentrux"]"#

        let terms = ContextGlossaryParser.parse(response)

        XCTAssertEqual(terms, ["CueMe", "DeepSeek V4", "Sentrux"])
    }

    func testParserEnforcesDeepgramTermAndTokenBudgets() {
        let terms = (0..<140).map { "specialized product term \($0)" }
        let responseData = try! JSONEncoder().encode(terms)

        let parsed = ContextGlossaryParser.parse(String(decoding: responseData, as: UTF8.self))

        XCTAssertLessThanOrEqual(parsed.count, GlossaryTermPolicy.maximumTerms)
        XCTAssertLessThanOrEqual(
            GlossaryTermPolicy.estimatedTokenCount(parsed),
            GlossaryTermPolicy.maximumTokens
        )
    }

    func testGlossarySignatureChangesWhenContextOrModelChanges() {
        let context = MeetingContext(name: "Produto", content: "CueMe grava reuniões.")
        let brief = SessionBrief.default

        let first = ContextGlossaryRequest.signature(
            contexts: [context], brief: brief, model: .sonnet
        )
        let changedContext = ContextGlossaryRequest.signature(
            contexts: [.init(id: context.id, name: context.name, content: "CueMe também treina entrevistas.")],
            brief: brief,
            model: .sonnet
        )
        let changedModel = ContextGlossaryRequest.signature(
            contexts: [context], brief: brief, model: .opus
        )

        XCTAssertNotEqual(first, changedContext)
        XCTAssertNotEqual(first, changedModel)
    }

    func testVocabularyNeverExceedsDeepgramBudgets() {
        var vocabulary = CustomVocabulary()
        for index in 0..<180 {
            vocabulary.addKeyterm("important specialized vocabulary number \(index)")
        }

        XCTAssertLessThanOrEqual(vocabulary.keyterms.count, GlossaryTermPolicy.maximumTerms)
        XCTAssertLessThanOrEqual(
            GlossaryTermPolicy.estimatedTokenCount(vocabulary.keyterms),
            GlossaryTermPolicy.maximumTokens
        )
    }

    func testDeepgramRequestRevalidatesGeneratedTermsAtNetworkBoundary() throws {
        let rawTerms = (0..<160).map { "long specialized integration vocabulary \($0)" }
        let config = SttConfig(
            speaker: .other,
            localeIdentifier: "pt-BR",
            keyterms: rawTerms
        )

        let url = try DeepgramLiveRequest.url(config: config)
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let sentTerms = items.filter { $0.name == "keyterm" }.compactMap(\.value)

        XCTAssertLessThanOrEqual(sentTerms.count, GlossaryTermPolicy.maximumTerms)
        XCTAssertLessThanOrEqual(
            GlossaryTermPolicy.estimatedTokenCount(sentTerms),
            GlossaryTermPolicy.maximumTokens
        )
    }

    func testLegacyProfileWithoutContextFieldsStillDecodes() throws {
        let legacy = BriefProfile(
            name: "Entrevista",
            brief: .default,
            coachModel: .sonnet,
            echoCancellation: false,
            recordAudio: true
        )

        let decoded = try JSONDecoder().decode(
            BriefProfile.self,
            from: JSONEncoder().encode(legacy)
        )

        XCTAssertNil(decoded.contextIDs)
        XCTAssertNil(decoded.glossaryModel)
    }
}
