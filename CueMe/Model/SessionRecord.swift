import Foundation

enum SessionOrigin: String, Codable, CaseIterable, Sendable, Identifiable {
    case live
    case audioFile
    case voiceMemo
    case written

    var id: String { rawValue }
    var supportsLiveCoach: Bool { self == .live }

    var label: String {
        switch self {
        case .live: return "Ao vivo"
        case .audioFile: return "Áudio importado"
        case .voiceMemo: return "Voice Memo"
        case .written: return "Escrita"
        }
    }
}

/// The canonical domain entity. Session-specific fields are optional enrichment
/// around a user-owned Markdown note rather than the product's primary object.
struct MemoryNote: Codable, Identifiable, Sendable, Hashable {
    static let currentSchemaVersion = 4
    static func == (l: MemoryNote, r: MemoryNote) -> Bool { l.id == r.id }
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
    var noteKind: MemoryNoteKind
    var markdownBody: String
    var labels: [String]
    var attachments: [NoteAttachment]
    var titleSource: NoteTitleSource
    var modifiedAt: Date
    var relativeFolderPath: String?

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
        personIDs: [UUID] = [],
        noteKind: MemoryNoteKind? = nil,
        markdownBody: String = "",
        labels: [String] = [],
        attachments: [NoteAttachment] = [],
        titleSource: NoteTitleSource? = nil,
        modifiedAt: Date? = nil,
        relativeFolderPath: String? = nil
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
        let resolvedFolderName = archiveFolderName ?? SessionArchive.folderName(startedAt: startedAt, id: id)
        self.archiveFolderName = resolvedFolderName
        self.notes = notes
        self.takeaways = takeaways
        self.origin = origin
        self.displayTitle = displayTitle
        self.review = review
        self.artifacts = artifacts
        self.projectID = projectID
        self.personIDs = personIDs
        self.noteKind = noteKind ?? MemoryNoteKind.inferred(mode: mode, origin: origin)
        self.markdownBody = markdownBody
        self.labels = Self.normalizedLabels(labels)
        self.attachments = attachments
        self.titleSource = titleSource ?? (displayTitle == nil ? .fallback : .generated)
        self.modifiedAt = modifiedAt ?? endedAt
        self.relativeFolderPath = relativeFolderPath ?? "_Inbox/\(resolvedFolderName)"
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
        noteKind = try c.decodeIfPresent(MemoryNoteKind.self, forKey: .noteKind)
            ?? MemoryNoteKind.inferred(mode: mode, origin: origin)
        markdownBody = try c.decodeIfPresent(String.self, forKey: .markdownBody) ?? ""
        labels = Self.normalizedLabels(try c.decodeIfPresent([String].self, forKey: .labels) ?? [])
        attachments = try c.decodeIfPresent([NoteAttachment].self, forKey: .attachments) ?? []
        titleSource = try c.decodeIfPresent(NoteTitleSource.self, forKey: .titleSource)
            ?? (displayTitle == nil ? .fallback : .generated)
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? endedAt
        relativeFolderPath = try c.decodeIfPresent(String.self, forKey: .relativeFolderPath)
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

    var storageRelativePath: String {
        guard let relativeFolderPath,
              !relativeFolderPath.hasPrefix("/"),
              !relativeFolderPath.split(separator: "/").contains("..") else {
            return archiveFolderName
        }
        return relativeFolderPath
    }

    var containsRecording: Bool {
        hasAudio || attachments.contains { $0.kind == .recording || $0.kind == .audio }
    }

    mutating func rename(to rawTitle: String) {
        let clean = Self.cleanTitle(rawTitle)
        guard !clean.isEmpty else { return }
        displayTitle = clean
        titleSource = .user
        modifiedAt = Date()
    }

    mutating func applyGeneratedTitle(_ rawTitle: String) {
        guard titleSource != .user else { return }
        let clean = Self.cleanTitle(rawTitle)
        guard !clean.isEmpty else { return }
        displayTitle = clean
        titleSource = .generated
        modifiedAt = Date()
    }

    mutating func setLabels(_ values: [String]) {
        labels = Self.normalizedLabels(values)
        modifiedAt = Date()
    }

    private static func cleanTitle(_ value: String) -> String {
        var clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("#") {
            clean = clean.drop(while: { $0 == "#" || $0.isWhitespace })
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        clean = clean.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
        return String(clean.prefix(120))
    }

    private static func normalizedLabels(_ values: [String]) -> [String] {
        Array(Set(values.compactMap { value -> String? in
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return clean.isEmpty ? nil : String(clean.prefix(48))
        })).sorted()
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

/// Source compatibility while older capture and review modules migrate their
/// vocabulary. New product code should use `MemoryNote`.
typealias SessionRecord = MemoryNote
