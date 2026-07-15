import Foundation

/// The user-owned unit of memory. A note may be plain writing, a journal entry,
/// or an enriched experience with recording, transcript, Coach and review data.
enum MemoryNoteKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case note
    case journal
    case meeting
    case interview
    case sales
    case difficultConversation = "difficult-conversation"
    case recording
    case importedAudio = "imported-audio"
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .note: return "Nota"
        case .journal: return "Diário"
        case .meeting: return "Reunião"
        case .interview: return "Entrevista"
        case .sales: return "Vendas"
        case .difficultConversation: return "Conversa difícil"
        case .recording: return "Gravação"
        case .importedAudio: return "Áudio importado"
        case .custom: return "Personalizado"
        }
    }

    var icon: String {
        switch self {
        case .note: return "doc.text.fill"
        case .journal: return "book.closed.fill"
        case .meeting: return "person.3.fill"
        case .interview: return "person.crop.rectangle.stack.fill"
        case .sales: return "chart.line.uptrend.xyaxis"
        case .difficultConversation: return "heart.text.square.fill"
        case .recording: return "waveform.circle.fill"
        case .importedAudio: return "square.and.arrow.down.fill"
        case .custom: return "sparkles.rectangle.stack.fill"
        }
    }

    static func inferred(mode: Mode, origin: SessionOrigin) -> MemoryNoteKind {
        if origin == .written { return .note }
        if origin != .live { return .importedAudio }
        switch mode {
        case .interview: return .interview
        case .sales: return .sales
        case .difficult: return .difficultConversation
        case .meeting: return .meeting
        case .recording: return .recording
        case .custom: return .custom
        }
    }
}

enum NoteTitleSource: String, Codable, Sendable {
    case fallback
    case generated
    case user
}

enum NoteAttachmentKind: String, Codable, Sendable {
    case recording
    case audio
    case image
    case document
    case file
}

struct NoteAttachment: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var filename: String
    var kind: NoteAttachmentKind
    var addedAt: Date

    init(
        id: UUID = UUID(),
        filename: String,
        kind: NoteAttachmentKind = .file,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.filename = filename
        self.kind = kind
        self.addedAt = addedAt
    }
}
