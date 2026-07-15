import XCTest
@testable import CueMe

final class MemoryNoteTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CueMeMemoryNoteTests-\(UUID().uuidString)", isDirectory: true)
        SessionStore.rootOverride = root
    }

    override func tearDownWithError() throws {
        SessionStore.rootOverride = nil
        try? FileManager.default.removeItem(at: root)
        root = nil
    }

    func testMemoryNoteIsTheBaseEntityForWritingAndRecordedExperiences() {
        let note = MemoryNote(
            startedAt: Date(timeIntervalSince1970: 1_000),
            mode: .recording,
            training: false,
            conversationLang: "pt-BR",
            nativeLang: "pt-BR",
            goal: "",
            transcript: [],
            coachCards: [],
            summaryBullets: [],
            noteKind: .journal,
            markdownBody: "Hoje percebi que preciso desacelerar."
        )

        XCTAssertEqual(note.noteKind, .journal)
        XCTAssertEqual(note.noteKind.icon, "book.closed.fill")
        XCTAssertEqual(note.markdownBody, "Hoje percebi que preciso desacelerar.")
        XCTAssertFalse(note.containsRecording)
    }

    func testNoteMarkdownFrontmatterIsCanonicalWhenEditedOutsideCueMe() throws {
        var note = MemoryNote(
            id: UUID(uuidString: "12345678-1234-1234-1234-1234567890AB")!,
            startedAt: Date(timeIntervalSince1970: 1_704_110_400),
            mode: .recording,
            training: false,
            conversationLang: "pt-BR",
            nativeLang: "pt-BR",
            goal: "",
            transcript: [],
            coachCards: [],
            summaryBullets: [],
            noteKind: .note,
            markdownBody: "Rascunho inicial",
            labels: ["ideias"]
        )
        note.rename(to: "Ideia inicial")

        let directory = try XCTUnwrap(SessionStore.save(note))
        let markdownURL = directory.appendingPathComponent("note.md")
        let saved = try String(contentsOf: markdownURL, encoding: .utf8)
        XCTAssertTrue(saved.hasPrefix("---\n"))
        XCTAssertTrue(saved.contains("title: \"Ideia inicial\""))
        XCTAssertTrue(saved.contains("kind: note"))
        XCTAssertTrue(saved.contains("labels: [\"ideias\"]"))

        let externallyEdited = saved
            .replacingOccurrences(of: "title: \"Ideia inicial\"", with: "title: \"Ideia amadurecida\"")
            .replacingOccurrences(of: "labels: [\"ideias\"]", with: "labels: [\"ideias\",\"produto\"]")
            .replacingOccurrences(of: "Rascunho inicial", with: "## Hipótese\n\nUm registro soberano do usuário.")
        try externallyEdited.write(to: markdownURL, atomically: true, encoding: .utf8)

        let loaded = try XCTUnwrap(SessionStore.loadAll().first)
        XCTAssertEqual(loaded.title, "Ideia amadurecida")
        XCTAssertEqual(loaded.labels, ["ideias", "produto"])
        XCTAssertTrue(loaded.markdownBody.contains("Um registro soberano do usuário."))
    }

    func testGeneratedTitleNeverOverwritesAUserRename() {
        var note = MemoryNote(
            startedAt: Date(timeIntervalSince1970: 1_000),
            mode: .meeting,
            training: false,
            conversationLang: "pt-BR",
            nativeLang: "pt-BR",
            goal: "",
            transcript: [],
            coachCards: [],
            summaryBullets: []
        )

        note.applyGeneratedTitle("Plano de lançamento")
        XCTAssertEqual(note.title, "Plano de lançamento")
        XCTAssertEqual(note.titleSource, .generated)

        note.rename(to: "Lançamento do CueMe 1.0")
        note.applyGeneratedTitle("Título tardio da IA")

        XCTAssertEqual(note.title, "Lançamento do CueMe 1.0")
        XCTAssertEqual(note.titleSource, .user)
    }

    func testRelocatingNotePlacesItInsideTheProjectFolder() throws {
        let project = KnowledgeProject(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            name: "Projeto Vida"
        )
        var note = MemoryNote(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            startedAt: Date(timeIntervalSince1970: 1_704_110_400),
            mode: .recording,
            training: false,
            conversationLang: "pt-BR",
            nativeLang: "pt-BR",
            goal: "",
            transcript: [],
            coachCards: [],
            summaryBullets: [],
            noteKind: .journal,
            markdownBody: "Registro do dia"
        )
        _ = try XCTUnwrap(SessionStore.save(note))

        note = try XCTUnwrap(SessionStore.relocate(note, to: project))
        let directory = SessionStore.archiveDirectory(for: note)

        XCTAssertTrue(directory.path.hasPrefix(ProjectWorkspaceStore.directory(for: project).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("note.md").path))
        XCTAssertEqual(SessionStore.loadAll().first?.projectID, project.id)
    }

    func testLabelsAreNormalizedAndDeduplicated() {
        var note = MemoryNote(
            startedAt: Date(), mode: .recording, training: false,
            conversationLang: "pt-BR", nativeLang: "pt-BR", goal: "",
            transcript: [], coachCards: [], summaryBullets: []
        )

        note.setLabels([" Trabalho ", "trabalho", "PESSOAL", ""])

        XCTAssertEqual(note.labels, ["pessoal", "trabalho"])
    }

    func testProjectMarkdownIsDiscoveredAsCanonicalFilesystemMetadata() throws {
        let project = KnowledgeProject(
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            name: "Projeto original"
        )
        let directory = try XCTUnwrap(ProjectWorkspaceStore.save(project))
        let url = directory.appendingPathComponent("project.md")
        let markdown = try String(contentsOf: url, encoding: .utf8)
            .replacingOccurrences(of: "name: \"Projeto original\"", with: "name: \"Projeto soberano\"")
        try markdown.write(to: url, atomically: true, encoding: .utf8)

        let loaded = try XCTUnwrap(ProjectWorkspaceStore.loadAll().first)

        XCTAssertEqual(loaded.id, project.id)
        XCTAssertEqual(loaded.name, "Projeto soberano")
        XCTAssertEqual(loaded.folderName, directory.lastPathComponent)
    }
}
