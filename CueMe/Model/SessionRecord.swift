import Foundation

enum SessionOrigin: String, Codable, CaseIterable, Sendable, Identifiable {
    case live
    case audioFile
    case voiceMemo

    var id: String { rawValue }
    var supportsLiveCoach: Bool { self == .live }

    var label: String {
        switch self {
        case .live: return "Ao vivo"
        case .audioFile: return "Áudio importado"
        case .voiceMemo: return "Voice Memo"
        }
    }
}

/// Snapshot de uma sessão terminada (treino ou conversa real), para o histórico.
struct SessionRecord: Codable, Identifiable, Sendable, Hashable {
    static let currentSchemaVersion = 3
    static func == (l: SessionRecord, r: SessionRecord) -> Bool { l.id == r.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    let id: UUID
    var schemaVersion: Int
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
    var minutes: MeetingMinutes
    var participantNames: [Speaker: String]
    var coachModel: CoachModel?
    var summaryModel: CoachModel?
    var vocabulary: CustomVocabulary
    var hasAudio: Bool
    var audioDuration: TimeInterval
    var diagnostics: SessionDiagnostics
    var coachFeedback: [UUID: CoachFeedback]
    var archiveFolderName: String
    var notes: [SessionNote]
    var takeaways: [SessionTakeaway]
    var origin: SessionOrigin
    var displayTitle: String?
    var review: MeetingReview
    var artifacts: [SessionArtifact]
    var projectID: UUID?
    var personIDs: [UUID]

    init(
        id: UUID = UUID(),
        schemaVersion: Int = SessionRecord.currentSchemaVersion,
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
        minutes: MeetingMinutes = .empty,
        participantNames: [Speaker: String] = [.self: "Você", .other: "Interlocutor"],
        coachModel: CoachModel? = nil,
        summaryModel: CoachModel? = nil,
        vocabulary: CustomVocabulary = .init(),
        hasAudio: Bool = false,
        audioDuration: TimeInterval = 0,
        diagnostics: SessionDiagnostics = .init(),
        coachFeedback: [UUID: CoachFeedback] = [:],
        archiveFolderName: String? = nil,
        notes: [SessionNote] = [],
        takeaways: [SessionTakeaway] = [],
        origin: SessionOrigin = .live,
        displayTitle: String? = nil,
        review: MeetingReview = .empty,
        artifacts: [SessionArtifact] = [],
        projectID: UUID? = nil,
        personIDs: [UUID] = []
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
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
        self.minutes = minutes
        self.participantNames = participantNames
        self.coachModel = coachModel
        self.summaryModel = summaryModel
        self.vocabulary = vocabulary
        self.hasAudio = hasAudio
        self.audioDuration = audioDuration
        self.diagnostics = diagnostics
        self.coachFeedback = coachFeedback
        self.archiveFolderName = archiveFolderName ?? SessionArchive.folderName(startedAt: startedAt, id: id)
        self.notes = notes
        self.takeaways = takeaways
        self.origin = origin
        self.displayTitle = displayTitle
        self.review = review
        self.artifacts = artifacts
        self.projectID = projectID
        self.personIDs = personIDs
    }

    /// Decode tolerante: sessões salvas antes do gravador não têm hasAudio/audioDuration.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
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
        minutes = try c.decodeIfPresent(MeetingMinutes.self, forKey: .minutes)
            ?? (summaryBullets.isEmpty ? .empty : MeetingMinutes(overview: summaryBullets.joined(separator: " ")))
        participantNames = try c.decodeIfPresent([Speaker: String].self, forKey: .participantNames)
            ?? [.self: "Você", .other: "Interlocutor"]
        coachModel = try c.decodeIfPresent(CoachModel.self, forKey: .coachModel)
        summaryModel = try c.decodeIfPresent(CoachModel.self, forKey: .summaryModel)
        vocabulary = try c.decodeIfPresent(CustomVocabulary.self, forKey: .vocabulary) ?? .init()
        hasAudio = try c.decodeIfPresent(Bool.self, forKey: .hasAudio) ?? false
        audioDuration = try c.decodeIfPresent(TimeInterval.self, forKey: .audioDuration) ?? 0
        diagnostics = try c.decodeIfPresent(SessionDiagnostics.self, forKey: .diagnostics) ?? .init()
        coachFeedback = try c.decodeIfPresent([UUID: CoachFeedback].self, forKey: .coachFeedback) ?? [:]
        archiveFolderName = try c.decodeIfPresent(String.self, forKey: .archiveFolderName)
            ?? SessionArchive.folderName(startedAt: startedAt, id: id)
        notes = try c.decodeIfPresent([SessionNote].self, forKey: .notes) ?? []
        takeaways = try c.decodeIfPresent([SessionTakeaway].self, forKey: .takeaways) ?? []
        origin = try c.decodeIfPresent(SessionOrigin.self, forKey: .origin) ?? .live
        displayTitle = try c.decodeIfPresent(String.self, forKey: .displayTitle)
        review = try c.decodeIfPresent(MeetingReview.self, forKey: .review) ?? .empty
        artifacts = try c.decodeIfPresent([SessionArtifact].self, forKey: .artifacts) ?? []
        projectID = try c.decodeIfPresent(UUID.self, forKey: .projectID)
        personIDs = try c.decodeIfPresent([UUID].self, forKey: .personIDs) ?? []
    }

    var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }
    var audioTimelineStart: Date { recordingStartedAt ?? startedAt }

    /// Título: primeira pergunta do interlocutor, senão modo + treino.
    var title: String {
        if let displayTitle = displayTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !displayTitle.isEmpty {
            return String(displayTitle.prefix(120))
        }
        if let q = transcript.first(where: { $0.speaker == .other && $0.isFinal })?.text, !q.isEmpty {
            return String(q.prefix(80))
        }
        return training ? "Treino · \(mode.label)" : mode.label
    }

    var turnCount: Int { transcript.filter { $0.isFinal }.count }
    var isForeign: Bool { SessionBrief.baseCode(conversationLang) != SessionBrief.baseCode(nativeLang) }

    func participantName(for speaker: Speaker) -> String {
        let fallback = speaker.label
        let value = participantNames[speaker]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? fallback : value
    }

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
