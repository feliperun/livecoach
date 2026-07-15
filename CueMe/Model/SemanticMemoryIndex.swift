import Foundation
import SQLite3

@_silgen_name("sqlite3_vec_init")
private func sqlite3_vec_init(
    _ database: OpaquePointer?,
    _ error: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
    _ api: OpaquePointer?
) -> Int32

/// Rebuildable local index. JSON/Markdown remain canonical; SQLite stores
/// relational metadata, FTS5 BM25 terms and sqlite-vec vectors in one file.
final class SemanticMemoryIndex: @unchecked Sendable {
    /// sqlite-vec reports cosine distance (0 = identical, 1 = orthogonal).
    /// Without a cutoff the nearest chunk is returned even when every chunk is
    /// unrelated, which makes a one-note archive match every possible query.
    private static let maximumSemanticDistance = 0.5
    static let shared: SemanticMemoryIndex = {
        guard ProcessInfo.processInfo.environment["CUEME_UI_TESTING"] == "1" else {
            return SemanticMemoryIndex()
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CueMeUITests-memory.sqlite3")
        return SemanticMemoryIndex(embedder: UITestFixtures.Embedding(), url: url)
    }()
    private let lock = NSLock()
    private let embedder: any EmbeddingProvider
    private var db: OpaquePointer?
    private var indexedFingerprint = ""
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(embedder: any EmbeddingProvider = AppleSentenceEmbeddingProvider(), url: URL? = nil) {
        self.embedder = embedder
        let databaseURL = url ?? Self.defaultURL
        try? FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            db = nil
            return
        }
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_vec_init(db, &error, nil) == SQLITE_OK else {
            if let error { sqlite3_free(error) }
            db = nil
            return
        }
        createSchema()
    }

    deinit { if let db { sqlite3_close(db) } }

    func rebuild(_ records: [SessionRecord]) {
        let chunks = records.flatMap(MemoryChunkBuilder.chunks)
        // The archive is editable after a meeting. Include indexed content in the
        // fingerprint so corrections, notes and regenerated artifacts invalidate
        // the projection even when session metadata did not change.
        let fingerprint = chunks
            .map { "\($0.id):\($0.text.hashValue)" }
            .joined(separator: "|")
        guard fingerprint != indexedFingerprint else { return }
        lock.withLock {
            guard let db else { return }
            exec("BEGIN IMMEDIATE")
            defer { exec("COMMIT") }
            exec("DELETE FROM memory_fts")
            exec("DELETE FROM memory_vec")
            exec("DELETE FROM memory_chunks")
            for chunk in chunks { insert(chunk, database: db) }
            indexedFingerprint = fingerprint
        }
    }

    func search(query: String, date: HistoryDateFilter, type: HistoryTypeFilter, records: [SessionRecord]) -> [SessionSearchResult] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            return SessionKnowledgeIndex(records: records).search(query: "", date: date, type: type)
        }
        rebuild(records)
        let allowed = Set(records.filter { date.contains($0.startedAt, now: Date()) && type.matches($0) }.map(\.id))
        return lock.withLock {
            let lexical = lexicalCandidates(clean).filter { allowed.contains($0.sessionID) }
            let semantic = vectorCandidates(clean).filter { allowed.contains($0.sessionID) }
            var scores: [UUID: Double] = [:]
            var snippets: [UUID: String] = [:]
            for (rank, item) in lexical.enumerated() {
                scores[item.sessionID, default: 0] += 1 / Double(60 + rank)
                snippets[item.sessionID] = snippets[item.sessionID] ?? item.text
            }
            for (rank, item) in semantic.enumerated() {
                scores[item.sessionID, default: 0] += 1 / Double(60 + rank)
                snippets[item.sessionID] = snippets[item.sessionID] ?? item.text
            }
            return scores.sorted { $0.value > $1.value }.map {
                SessionSearchResult(recordID: $0.key, score: Int($0.value * 1_000_000), snippet: snippets[$0.key].map { String($0.prefix(180)) })
            }
        }
    }

    private struct Candidate { let sessionID: UUID; let text: String }

    private func lexicalCandidates(_ query: String) -> [Candidate] {
        let terms = query.split { $0.isWhitespace || $0.isPunctuation }.map { "\"\($0.replacingOccurrences(of: "\"", with: ""))\"" }
        guard !terms.isEmpty else { return [] }
        return candidates(sql: """
            SELECT c.session_id, c.text FROM memory_fts f
            JOIN memory_chunks c ON c.id = f.chunk_id
            WHERE memory_fts MATCH ? ORDER BY bm25(memory_fts) LIMIT 40
            """, bind: terms.joined(separator: " OR "))
    }

    private func vectorCandidates(_ query: String) -> [Candidate] {
        guard let db else { return [] }
        let blob = Self.blob(embedder.embedding(for: query))
        var statement: OpaquePointer?
        let sql = "SELECT rowid, distance FROM memory_vec WHERE embedding MATCH ? ORDER BY distance LIMIT 40"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        _ = blob.withUnsafeBytes { sqlite3_bind_blob(statement, 1, $0.baseAddress, Int32($0.count), transient) }
        var rowIDs: [Int64] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let distance = sqlite3_column_double(statement, 1)
            guard distance <= Self.maximumSemanticDistance else { continue }
            rowIDs.append(sqlite3_column_int64(statement, 0))
        }
        var result: [Candidate] = []
        var chunkStatement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT session_id,text FROM memory_chunks WHERE rowid=?", -1, &chunkStatement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(chunkStatement) }
        for rowID in rowIDs {
            sqlite3_reset(chunkStatement)
            sqlite3_bind_int64(chunkStatement, 1, rowID)
            guard sqlite3_step(chunkStatement) == SQLITE_ROW,
                  let session = text(chunkStatement, 0), let id = UUID(uuidString: session),
                  let value = text(chunkStatement, 1) else { continue }
            result.append(.init(sessionID: id, text: value))
        }
        return result
    }

    private func candidates(sql: String, bind: String) -> [Candidate] {
        guard let db else { return [] }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, bind, -1, transient)
        var result: [Candidate] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let session = text(statement, 0), let id = UUID(uuidString: session), let value = text(statement, 1) else { continue }
            result.append(.init(sessionID: id, text: value))
        }
        return result
    }

    private func insert(_ chunk: MemoryChunk, database: OpaquePointer) {
        var statement: OpaquePointer?
        let sql = "INSERT INTO memory_chunks(id,session_id,project_id,kind,started_at,time_offset,text,embedding_model) VALUES(?,?,?,?,?,?,?,?)"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return }
        bind(chunk.id, to: statement, at: 1); bind(chunk.sessionID.uuidString, to: statement, at: 2)
        bind(chunk.projectID?.uuidString, to: statement, at: 3); bind(chunk.kind.rawValue, to: statement, at: 4)
        sqlite3_bind_double(statement, 5, chunk.startedAt.timeIntervalSince1970)
        if let timestamp = chunk.timestamp { sqlite3_bind_double(statement, 6, timestamp) } else { sqlite3_bind_null(statement, 6) }
        bind(chunk.text, to: statement, at: 7); bind(embedder.modelID, to: statement, at: 8)
        guard sqlite3_step(statement) == SQLITE_DONE else { sqlite3_finalize(statement); return }
        sqlite3_finalize(statement)
        let rowID = sqlite3_last_insert_rowid(database)

        guard sqlite3_prepare_v2(database, "INSERT INTO memory_fts(rowid,chunk_id,text) VALUES(?,?,?)", -1, &statement, nil) == SQLITE_OK else { return }
        sqlite3_bind_int64(statement, 1, rowID); bind(chunk.id, to: statement, at: 2); bind(chunk.text, to: statement, at: 3)
        sqlite3_step(statement); sqlite3_finalize(statement)

        let vector = Self.blob(embedder.embedding(for: chunk.text))
        guard sqlite3_prepare_v2(database, "INSERT INTO memory_vec(rowid,embedding) VALUES(?,?)", -1, &statement, nil) == SQLITE_OK else { return }
        sqlite3_bind_int64(statement, 1, rowID)
        _ = vector.withUnsafeBytes { sqlite3_bind_blob(statement, 2, $0.baseAddress, Int32($0.count), transient) }
        sqlite3_step(statement); sqlite3_finalize(statement)
    }

    private func createSchema() {
        lock.withLock {
            exec("PRAGMA journal_mode=WAL")
            exec("CREATE TABLE IF NOT EXISTS memory_meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)")
            exec("CREATE TABLE IF NOT EXISTS memory_chunks(id TEXT UNIQUE NOT NULL, session_id TEXT NOT NULL, project_id TEXT, kind TEXT NOT NULL, started_at REAL NOT NULL, time_offset REAL, text TEXT NOT NULL, embedding_model TEXT NOT NULL)")
            exec("CREATE INDEX IF NOT EXISTS memory_chunks_session ON memory_chunks(session_id)")
            exec("CREATE INDEX IF NOT EXISTS memory_chunks_project ON memory_chunks(project_id)")
            exec("CREATE VIRTUAL TABLE IF NOT EXISTS memory_fts USING fts5(chunk_id UNINDEXED, text, tokenize='unicode61 remove_diacritics 2')")
            exec("CREATE VIRTUAL TABLE IF NOT EXISTS memory_vec USING vec0(embedding float[512] distance_metric=cosine)")
        }
    }

    private func exec(_ sql: String) { if let db { sqlite3_exec(db, sql, nil, nil, nil) } }
    private func bind(_ value: String?, to statement: OpaquePointer?, at index: Int32) {
        if let value { sqlite3_bind_text(statement, index, value, -1, transient) } else { sqlite3_bind_null(statement, index) }
    }
    private func text(_ statement: OpaquePointer?, _ column: Int32) -> String? {
        sqlite3_column_text(statement, column).map { String(cString: $0) }
    }
    private static func blob(_ values: [Float]) -> Data { values.withUnsafeBufferPointer(Data.init(buffer:)) }

    private static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CueMe/Memory/memory.sqlite3")
    }

}
