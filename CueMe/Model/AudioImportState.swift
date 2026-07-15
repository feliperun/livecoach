import Foundation

enum AudioImportPhase: String, Sendable, Equatable {
    case preparing, transcribing, enriching, completed, failed
}

struct AudioImportStatus: Sendable, Equatable {
    let phase: AudioImportPhase
    let title: String
    let detail: String
    let sessionID: UUID?

    var isActive: Bool {
        phase == .preparing || phase == .transcribing || phase == .enriching
    }
}
