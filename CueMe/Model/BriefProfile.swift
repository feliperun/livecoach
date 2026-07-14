import Foundation

struct BriefProfile: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    var name: String
    var brief: SessionBrief
    var coachModel: CoachModel
    var echoCancellation: Bool
    var recordAudio: Bool

    init(
        id: UUID = UUID(),
        name: String,
        brief: SessionBrief,
        coachModel: CoachModel,
        echoCancellation: Bool,
        recordAudio: Bool
    ) {
        self.id = id
        self.name = name
        self.brief = brief
        self.coachModel = coachModel
        self.echoCancellation = echoCancellation
        self.recordAudio = recordAudio
    }
}

enum BriefProfileStore {
    private static func url() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = base.appendingPathComponent("CueMe", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("profiles.json")
    }

    static func load() -> [BriefProfile] {
        guard let data = try? Data(contentsOf: url()),
              let profiles = try? JSONDecoder().decode([BriefProfile].self, from: data) else { return [] }
        return profiles.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func save(_ profiles: [BriefProfile]) {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        try? data.write(to: url(), options: .atomic)
    }
}
