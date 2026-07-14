import Foundation

/// Snapshot de uma sessão terminada (treino ou conversa real), para o histórico.
struct SessionRecord: Codable, Identifiable, Sendable, Hashable {
    static func == (l: SessionRecord, r: SessionRecord) -> Bool { l.id == r.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    let id: UUID
    var startedAt: Date
    var recordingStartedAt: Date?
    var endedAt: Date
    var mode: Mode
    var training: Bool
    var conversationLang: String
    var nativeLang: String
    var goal: String
    var transcript: [TranscriptLine]
    var coachCards: [CoachCard]
    var summaryBullets: [String]
    var hasAudio: Bool
    var audioDuration: TimeInterval

    init(
        id: UUID = UUID(),
        startedAt: Date,
        recordingStartedAt: Date? = nil,
        endedAt: Date = Date(),
        mode: Mode,
        training: Bool,
        conversationLang: String,
        nativeLang: String,
        goal: String,
        transcript: [TranscriptLine],
        coachCards: [CoachCard],
        summaryBullets: [String],
        hasAudio: Bool = false,
        audioDuration: TimeInterval = 0
    ) {
        self.id = id
        self.startedAt = startedAt
        self.recordingStartedAt = recordingStartedAt
        self.endedAt = endedAt
        self.mode = mode
        self.training = training
        self.conversationLang = conversationLang
        self.nativeLang = nativeLang
        self.goal = goal
        self.transcript = transcript
        self.coachCards = coachCards
        self.summaryBullets = summaryBullets
        self.hasAudio = hasAudio
        self.audioDuration = audioDuration
    }

    /// Decode tolerante: sessões salvas antes do gravador não têm hasAudio/audioDuration.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        recordingStartedAt = try c.decodeIfPresent(Date.self, forKey: .recordingStartedAt)
        endedAt = try c.decode(Date.self, forKey: .endedAt)
        mode = try c.decode(Mode.self, forKey: .mode)
        training = try c.decode(Bool.self, forKey: .training)
        conversationLang = try c.decode(String.self, forKey: .conversationLang)
        nativeLang = try c.decode(String.self, forKey: .nativeLang)
        goal = try c.decode(String.self, forKey: .goal)
        transcript = try c.decode([TranscriptLine].self, forKey: .transcript)
        coachCards = try c.decode([CoachCard].self, forKey: .coachCards)
        summaryBullets = try c.decode([String].self, forKey: .summaryBullets)
        hasAudio = try c.decodeIfPresent(Bool.self, forKey: .hasAudio) ?? false
        audioDuration = try c.decodeIfPresent(TimeInterval.self, forKey: .audioDuration) ?? 0
    }

    var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }
    var audioTimelineStart: Date { recordingStartedAt ?? startedAt }

    /// Título: primeira pergunta do interlocutor, senão modo + treino.
    var title: String {
        if let q = transcript.first(where: { $0.speaker == .other && $0.isFinal })?.text, !q.isEmpty {
            return String(q.prefix(80))
        }
        return training ? "Treino · \(mode.label)" : mode.label
    }

    var turnCount: Int { transcript.filter { $0.isFinal }.count }
    var isForeign: Bool { SessionBrief.baseCode(conversationLang) != SessionBrief.baseCode(nativeLang) }

    /// Nome de arquivo sugerido pra exportação.
    var exportFilename: String {
        let stamp = startedAt.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        return "CueMe-\(training ? "treino" : mode.rawValue)-\(stamp).json"
    }

    /// JSON legível (pretty) pra copiar/exportar.
    var prettyJSON: String {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? e.encode(self), let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }
}

/// Persistência do histórico — um JSON por sessão em Application Support.
enum SessionStore {
    private static func dir() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let d = base.appendingPathComponent("CueMe/sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    static func save(_ record: SessionRecord) {
        guard let data = try? encoder.encode(record) else { return }
        try? data.write(to: dir().appendingPathComponent("\(record.id.uuidString).json"), options: .atomic)
    }

    /// Todas as sessões, mais recentes primeiro.
    static func loadAll() -> [SessionRecord] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir(), includingPropertiesForKeys: nil
        ) else { return [] }
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(SessionRecord.self, from: Data(contentsOf: $0)) }
            .sorted { $0.startedAt > $1.startedAt }
    }

    static func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: dir().appendingPathComponent("\(id.uuidString).json"))
        MeetingRecording.delete(for: id)
    }
}
