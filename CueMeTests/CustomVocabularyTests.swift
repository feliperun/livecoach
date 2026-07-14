import XCTest
@testable import CueMe

final class CustomVocabularyTests: XCTestCase {
    func testCorrectionLearnsOnlyChangedPhraseAndCanonicalKeyterm() {
        var vocabulary = CustomVocabulary()

        XCTAssertTrue(vocabulary.learnCorrection(
            from: "O mono rapo, será migrado amanhã.",
            to: "O monorepo será migrado amanhã."
        ))

        XCTAssertEqual(vocabulary.replacements["mono rapo"], "monorepo")
        XCTAssertTrue(vocabulary.keyterms.contains("monorepo"))
    }

    func testMergedVocabularyIncludesBriefAndParticipantNamesWithoutDuplicates() {
        let merged = CustomVocabulary(keyterms: ["CueMe"], replacements: [:]).merged(
            keyterms: ["cueme", "Sentrux"],
            participantNames: [.self: "Felipe", .other: "Ramon"]
        )

        XCTAssertEqual(merged.keyterms, ["CueMe", "Sentrux", "Felipe", "Ramon"])
    }
}
