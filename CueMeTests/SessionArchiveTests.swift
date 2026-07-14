import XCTest
@testable import CueMe

final class SessionArchiveTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CueMeArchiveTests-\(UUID().uuidString)", isDirectory: true)
        SessionStore.rootOverride = root
    }

    override func tearDownWithError() throws {
        SessionStore.rootOverride = nil
        try? FileManager.default.removeItem(at: root)
        root = nil
    }

    func testSaveWritesPortableJSONAndMarkdownInsideTimestampedFolder() throws {
        let startedAt = Date(timeIntervalSince1970: 1_704_110_400)
        var line = TranscriptLine(
            speaker: .other,
            text: "Vamos entregar no mono rapo na sexta.",
            translation: "We will deliver on Friday.",
            isFinal: true,
            ts: startedAt.addingTimeInterval(12)
        )
        line.applyCorrection("Vamos entregar no monorepo na sexta-feira.", at: startedAt.addingTimeInterval(20))
        let record = SessionRecord(
            id: UUID(uuidString: "12345678-1234-1234-1234-1234567890AB")!,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(90),
            mode: .meeting,
            training: false,
            conversationLang: "pt-BR",
            nativeLang: "en-US",
            goal: "Definir próximos passos",
            transcript: [line],
            coachCards: [],
            summaryBullets: ["Entrega combinada para sexta."],
            minutes: MeetingMinutes(
                overview: "Entrega e responsáveis foram alinhados.",
                topics: [.init(title: "Cronograma", summary: "Entrega combinada para sexta-feira.")]
            ),
            participantNames: [.self: "Felipe", .other: "Marcelo"],
            notes: [.init(timeOffset: 9, text: "Confirmar responsável")],
            takeaways: [.init(text: "Enviar cronograma")],
            artifacts: [.init(kind: .answer, title: "Follow-up", body: "Mandar e-mail amanhã.")]
        )

        let directory = try XCTUnwrap(SessionStore.save(record))

        XCTAssertTrue(directory.lastPathComponent.hasPrefix("2024-01-01_"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("session.json").path))
        let markdownURL = directory.appendingPathComponent("session.md")
        let markdown = try String(contentsOf: markdownURL, encoding: .utf8)
        XCTAssertTrue(markdown.contains("# Vamos entregar no monorepo na sexta-feira."))
        XCTAssertTrue(markdown.contains("## Anotações"))
        XCTAssertTrue(markdown.contains("[00:09] Confirmar responsável"))
        XCTAssertTrue(markdown.contains("- [ ] Enviar cronograma"))
        XCTAssertTrue(markdown.contains("## Transcrição"))
        XCTAssertTrue(markdown.contains("## Ata"))
        XCTAssertTrue(markdown.contains("#### Cronograma"))
        XCTAssertTrue(markdown.contains("**Marcelo · 00:12**"))
        XCTAssertTrue(markdown.localizedCaseInsensitiveContains("corrigido"))
        XCTAssertTrue(markdown.contains("mono rapo"))
        XCTAssertTrue(markdown.contains("We will deliver on Friday."))
        XCTAssertTrue(markdown.contains("## Conteúdo gerado"))
        XCTAssertTrue(markdown.contains("Mandar e-mail amanhã."))
        XCTAssertEqual(SessionStore.loadAll().map(\.id), [record.id])
    }

    func testFolderNameIsStableAndPortable() {
        let id = UUID(uuidString: "12345678-1234-1234-1234-1234567890AB")!
        let date = Date(timeIntervalSince1970: 1_704_110_400)

        let first = SessionArchive.folderName(startedAt: date, id: id)
        let second = SessionArchive.folderName(startedAt: date, id: id)

        XCTAssertEqual(first, second)
        XCTAssertTrue(first.hasSuffix("_12345678"))
        XCTAssertFalse(first.contains("/"))
    }
}
