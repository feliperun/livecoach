import AVFoundation
import Foundation
import XCTest
@testable import CueMe

final class AudioImportAndKnowledgeTests: XCTestCase {
    func testImportedSessionKeepsSourceAndExplicitTitle() throws {
        let record = SessionRecord(
            startedAt: Date(timeIntervalSince1970: 1_000),
            mode: .recording,
            training: false,
            conversationLang: "pt-BR",
            nativeLang: "pt-BR",
            goal: "",
            transcript: [],
            coachCards: [],
            summaryBullets: [],
            origin: .audioFile,
            displayTitle: "Reunião de arquitetura"
        )

        XCTAssertEqual(record.title, "Reunião de arquitetura")
        XCTAssertEqual(record.origin, .audioFile)
        XCTAssertFalse(record.origin.supportsLiveCoach)

        var payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any]
        )
        payload.removeValue(forKey: "origin")
        payload.removeValue(forKey: "displayTitle")
        let legacy = try JSONSerialization.data(withJSONObject: payload)
        let decoded = try JSONDecoder().decode(SessionRecord.self, from: legacy)
        XCTAssertEqual(decoded.origin, .live)
    }

    func testKnowledgeSearchFindsTopicsNotesAndTodosIgnoringAccents() {
        let architecture = makeRecord(
            title: "Revisão técnica",
            startedAt: Date(timeIntervalSince1970: 10_000),
            origin: .live,
            topic: "Migração",
            summary: "Arquitetura do monorepo e estratégia de rollback",
            note: "Validar observabilidade",
            takeaway: "Felipe prepara o plano"
        )
        let sales = makeRecord(
            title: "Cliente ACME",
            startedAt: Date(timeIntervalSince1970: 20_000),
            origin: .audioFile,
            topic: "Proposta",
            summary: "Preço e prazo comercial",
            note: "Enviar contrato",
            takeaway: "Revisar orçamento"
        )
        let index = SessionKnowledgeIndex(records: [architecture, sales])

        XCTAssertEqual(
            index.search(query: "migracao rollback", date: .all, type: .all).map(\.recordID),
            [architecture.id]
        )
        XCTAssertEqual(
            index.search(query: "observabilidade", date: .all, type: .all).first?.recordID,
            architecture.id
        )
        XCTAssertEqual(
            index.search(query: "", date: .all, type: .imported).map(\.recordID),
            [sales.id]
        )
    }

    func testKnowledgeDateFilterUsesMeetingDate() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let recent = makeRecord(
            title: "Recente", startedAt: now.addingTimeInterval(-2 * 86_400), origin: .voiceMemo
        )
        let old = makeRecord(
            title: "Antiga", startedAt: now.addingTimeInterval(-45 * 86_400), origin: .live
        )
        let index = SessionKnowledgeIndex(records: [old, recent])

        XCTAssertEqual(
            index.search(query: "", date: .last30Days, type: .all, now: now).map(\.recordID),
            [recent.id]
        )
    }

    func testDeepgramBatchRequestAndParserPreserveSpeakerAndTimeline() throws {
        let config = SttConfig(
            speaker: .other,
            localeIdentifier: "pt-BR",
            keyterms: ["CueMe"],
            replacements: ["cu mi": "CueMe"]
        )
        let url = try XCTUnwrap(DeepgramPrerecordedRequest.url(config: config))
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.first { $0.name == "model" }?.value, "nova-3")
        XCTAssertEqual(items.first { $0.name == "diarize_model" }?.value, "latest")
        XCTAssertEqual(items.first { $0.name == "utterances" }?.value, "true")
        XCTAssertEqual(items.first { $0.name == "keyterm" }?.value, "CueMe")

        let startedAt = Date(timeIntervalSince1970: 1_000)
        let response = """
        {"results":{"utterances":[
          {"start":1.5,"end":3.0,"transcript":"Primeira fala","speaker":0},
          {"start":4.0,"end":6.0,"transcript":"Segunda fala","speaker":1}
        ]}}
        """
        let lines = try DeepgramPrerecordedResponseParser.parse(Data(response.utf8), startedAt: startedAt)
        XCTAssertEqual(lines.map(\.speaker), [.other, .self])
        XCTAssertEqual(lines.map(\.text), ["Primeira fala", "Segunda fala"])
        XCTAssertEqual(lines[0].ts, startedAt.addingTimeInterval(1.5))
        XCTAssertEqual(lines[1].ts, startedAt.addingTimeInterval(4.0))
    }

    func testAudioImportCopiesPortableRecordingIntoSessionArchive() async throws {
        let sourceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CueMeImportSource-\(UUID().uuidString)", isDirectory: true)
        let archiveDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CueMeImportArchive-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
        defer {
            SessionStore.rootOverride = nil
            try? FileManager.default.removeItem(at: sourceDirectory)
            try? FileManager.default.removeItem(at: archiveDirectory)
        }
        SessionStore.rootOverride = archiveDirectory
        let sourceURL = sourceDirectory.appendingPathComponent("planning.m4a")
        var sourceFile: AVAudioFile? = try AVAudioFile(
            forWriting: sourceURL,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128_000
            ]
        )
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800))
        buffer.frameLength = 4_800
        try sourceFile?.write(from: buffer)
        sourceFile = nil

        let record = try await AudioImportService.prepare(
            sourceURL: sourceURL,
            origin: .audioFile,
            conversationLanguage: "pt-BR",
            nativeLanguage: "pt-BR",
            title: "Planning"
        )

        XCTAssertEqual(record.origin, .audioFile)
        XCTAssertEqual(record.title, "Planning")
        XCTAssertTrue(record.hasAudio)
        XCTAssertTrue(FileManager.default.fileExists(atPath: MeetingRecording.otherURL(for: record).path))
        XCTAssertTrue(record.coachCards.isEmpty)
    }

    func testExternalAudioInboxAcceptsPortableAudioAndRejectsOtherFiles() {
        XCTAssertTrue(ExternalAudioInbox.isSupported(filename: "Voice Memo.m4a"))
        XCTAssertTrue(ExternalAudioInbox.isSupported(filename: "interview.WAV"))
        XCTAssertTrue(ExternalAudioInbox.isSupported(filename: "meeting.mp3"))
        XCTAssertFalse(ExternalAudioInbox.isSupported(filename: "Voice Memos.sqlite"))
        XCTAssertFalse(ExternalAudioInbox.isSupported(filename: "notes.pdf"))
    }

    func testExternalAudioInboxQueuesAtomicallyAndPreservesDisplayName() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CueMeExternalInboxTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        ExternalAudioInbox.rootOverride = directory
        defer {
            ExternalAudioInbox.rootOverride = nil
            try? FileManager.default.removeItem(at: directory)
        }

        let queued = try ExternalAudioInbox.enqueue(
            data: Data("audio".utf8),
            filename: "Planejamento: Q3.m4a"
        )

        XCTAssertEqual(
            ExternalAudioInbox.pendingURLs().map { $0.resolvingSymlinksInPath() },
            [queued.resolvingSymlinksInPath()]
        )
        XCTAssertEqual(ExternalAudioInbox.displayName(for: queued), "Planejamento Q3")
        XCTAssertEqual(queued.pathExtension, "m4a")
        XCTAssertFalse(queued.lastPathComponent.contains(":"))

        ExternalAudioInbox.remove(queued)
        XCTAssertTrue(ExternalAudioInbox.pendingURLs().isEmpty)
    }

    func testExternalAudioInboxRefusesUnsupportedPayloads() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CueMeExternalInboxReject-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        ExternalAudioInbox.rootOverride = directory
        defer {
            ExternalAudioInbox.rootOverride = nil
            try? FileManager.default.removeItem(at: directory)
        }

        XCTAssertThrowsError(try ExternalAudioInbox.enqueue(data: Data(), filename: "database.sqlite"))
        XCTAssertTrue(ExternalAudioInbox.pendingURLs().isEmpty)
    }

    func testExternalAudioInboxFallsBackToSourceExtensionForPromisedFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CueMeExternalInboxPromised-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        ExternalAudioInbox.rootOverride = directory
        defer {
            ExternalAudioInbox.rootOverride = nil
            try? FileManager.default.removeItem(at: directory)
        }
        let source = directory.appendingPathComponent("temporary.m4a")
        try Data("audio".utf8).write(to: source)

        let queued = try ExternalAudioInbox.enqueueCopy(from: source, filename: "Daily stand-up")

        XCTAssertEqual(queued.pathExtension, "m4a")
        XCTAssertEqual(ExternalAudioInbox.displayName(for: queued), "Daily stand-up")
    }

    func testAudioImportConvertsWAVToAACM4A() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("CueMeWAVImport-\(UUID().uuidString)", isDirectory: true)
        let archive = base.appendingPathComponent("archive", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer {
            SessionStore.rootOverride = nil
            try? FileManager.default.removeItem(at: base)
        }
        SessionStore.rootOverride = archive
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44_100,
            channels: 1,
            interleaved: false
        ))
        let source = base.appendingPathComponent("meeting.wav")
        var file: AVAudioFile? = try AVAudioFile(forWriting: source, settings: format.settings)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_410))
        buffer.frameLength = 4_410
        try file?.write(from: buffer)
        file = nil

        let record = try await AudioImportService.prepare(
            sourceURL: source,
            origin: .audioFile,
            conversationLanguage: "pt-BR",
            nativeLanguage: "pt-BR"
        )
        let imported = try AVAudioFile(forReading: MeetingRecording.otherURL(for: record))

        XCTAssertEqual(imported.fileFormat.streamDescription.pointee.mFormatID, kAudioFormatMPEG4AAC)
        XCTAssertEqual(MeetingRecording.otherURL(for: record).pathExtension, "m4a")
    }

    @MainActor
    func testAppModelReindexesWhenSessionMemoryChanges() {
        let app = AppModel()
        var record = makeRecord(title: "Planejamento", startedAt: Date(), origin: .audioFile)
        app.history = [record]
        app.historySearch = "observabilidade"
        XCTAssertTrue(app.filteredHistory.isEmpty)

        record.minutes = MeetingMinutes(
            overview: "Definimos métricas de observabilidade.",
            topics: [.init(title: "Operação", summary: "Logs e alertas")]
        )
        app.replaceHistoryRecord(record)

        XCTAssertEqual(app.filteredHistory.map(\.id), [record.id])
    }

    private func makeRecord(
        title: String,
        startedAt: Date,
        origin: SessionOrigin,
        topic: String = "",
        summary: String = "",
        note: String = "",
        takeaway: String = ""
    ) -> SessionRecord {
        SessionRecord(
            startedAt: startedAt,
            mode: .meeting,
            training: false,
            conversationLang: "pt-BR",
            nativeLang: "pt-BR",
            goal: "",
            transcript: [],
            coachCards: [],
            summaryBullets: [],
            minutes: MeetingMinutes(
                overview: summary,
                topics: topic.isEmpty ? [] : [.init(title: topic, summary: summary)]
            ),
            notes: note.isEmpty ? [] : [.init(timeOffset: 0, text: note)],
            takeaways: takeaway.isEmpty ? [] : [.init(text: takeaway)],
            origin: origin,
            displayTitle: title
        )
    }
}
