import Foundation
import XCTest
@testable import CueMe

final class SemanticMemoryIndexTests: XCTestCase {
    private struct TestEmbedder: EmbeddingProvider {
        let modelID = "test-embedding-v1"
        let dimensions = 512

        func embedding(for text: String) -> [Float] {
            var values = [Float](repeating: 0, count: dimensions)
            let lower = text.lowercased()
            if lower.contains("carro") || lower.contains("automóvel") || lower.contains("veículo") {
                values[7] = 1
            } else if lower.contains("observabilidade") {
                values[13] = 1
            } else {
                values[11] = 1
            }
            return values
        }
    }

    func testSQLiteVecFindsSemanticParaphraseOutsideFTS() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CueMeSemantic-\(UUID().uuidString).sqlite3")
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))
        }
        let record = SessionRecord(
            startedAt: Date(), mode: .meeting, training: false,
            conversationLang: "pt-BR", nativeLang: "pt-BR", goal: "",
            transcript: [], coachCards: [], summaryBullets: [],
            notes: [.init(timeOffset: 0, text: "O veículo será trocado na próxima semana")]
        )
        let index = SemanticMemoryIndex(embedder: TestEmbedder(), url: url)
        let results = index.search(query: "carro", date: .all, type: .all, records: [record])
        XCTAssertEqual(results.first?.recordID, record.id)
    }

    func testSQLiteVecDoesNotReturnAnUnrelatedNearestNeighbor() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CueMeSemantic-\(UUID().uuidString).sqlite3")
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))
        }
        let record = SessionRecord(
            startedAt: Date(), mode: .meeting, training: false,
            conversationLang: "pt-BR", nativeLang: "pt-BR", goal: "",
            transcript: [], coachCards: [], summaryBullets: [],
            notes: [.init(timeOffset: 0, text: "O veículo será trocado na próxima semana")]
        )
        let index = SemanticMemoryIndex(embedder: TestEmbedder(), url: url)

        let results = index.search(query: "observabilidade", date: .all, type: .all, records: [record])

        XCTAssertTrue(results.isEmpty)
    }

    func testLegacyEvidenceFieldsDecodeWithSafeDefaults() throws {
        let action = try JSONDecoder().decode(
            SessionTakeaway.self,
            from: Data(#"{"id":"00000000-0000-0000-0000-000000000001","text":"Enviar ata","isDone":false,"createdAt":0}"#.utf8)
        )
        XCTAssertTrue(action.evidence.isEmpty)
        XCTAssertNil(action.assignee)
    }

    func testEditingArchivedContentInvalidatesTheIndex() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CueMeSemantic-\(UUID().uuidString).sqlite3")
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))
        }
        var record = SessionRecord(
            startedAt: Date(), mode: .meeting, training: false,
            conversationLang: "pt-BR", nativeLang: "pt-BR", goal: "",
            transcript: [], coachCards: [], summaryBullets: [],
            notes: [.init(timeOffset: 0, text: "Primeira versão da anotação")]
        )
        let index = SemanticMemoryIndex(embedder: TestEmbedder(), url: url)
        _ = index.search(query: "primeira", date: .all, type: .all, records: [record])

        record.notes = [.init(timeOffset: 0, text: "Orçamento aprovado pela diretoria")]
        let results = index.search(query: "orçamento", date: .all, type: .all, records: [record])

        XCTAssertTrue(results.first?.snippet?.contains("Orçamento aprovado") == true)
    }
}
