import Foundation

struct BriefProfile: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    var name: String
    var brief: SessionBrief
    var coachModel: CoachModel
    var summaryModel: CoachModel?
    var echoCancellation: Bool
    var recordAudio: Bool
    var contextIDs: [UUID]?
    var glossaryModel: CoachModel?

    init(
        id: UUID = UUID(),
        name: String,
        brief: SessionBrief,
        coachModel: CoachModel,
        summaryModel: CoachModel? = nil,
        echoCancellation: Bool,
        recordAudio: Bool,
        contextIDs: [UUID]? = nil,
        glossaryModel: CoachModel? = nil
    ) {
        self.id = id
        self.name = name
        self.brief = brief
        self.coachModel = coachModel
        self.summaryModel = summaryModel
        self.echoCancellation = echoCancellation
        self.recordAudio = recordAudio
        self.contextIDs = contextIDs
        self.glossaryModel = glossaryModel
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
