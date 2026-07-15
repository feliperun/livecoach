@preconcurrency import AVFoundation
import Foundation

enum AudioImportError: LocalizedError {
    case unsupportedFile
    case invalidDuration
    case cannotCreateSession
    case conversionFailed
    case transcriptionFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedFile: return "Este arquivo de áudio não é compatível."
        case .invalidDuration: return "Não foi possível identificar a duração do áudio."
        case .cannotCreateSession: return "Não foi possível criar a pasta da sessão."
        case .conversionFailed: return "Não foi possível converter o áudio para M4A."
        case .transcriptionFailed: return "A transcrição do áudio não retornou falas."
        }
    }
}

enum AudioImportService {
    static func prepare(
        sourceURL: URL,
        origin: SessionOrigin,
        conversationLanguage: String,
        nativeLanguage: String,
        title: String? = nil
    ) async throws -> SessionRecord {
        let asset = AVURLAsset(url: sourceURL)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw AudioImportError.invalidDuration }

        let values = try? sourceURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let startedAt = values?.creationDate ?? values?.contentModificationDate ?? Date()
        let id = UUID()
        let record = SessionRecord(
            id: id,
            startedAt: startedAt,
            recordingStartedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(duration),
            mode: .recording,
            training: false,
            conversationLang: conversationLanguage,
            nativeLang: nativeLanguage,
            goal: "Memória importada de \(sourceURL.lastPathComponent)",
            transcript: [],
            coachCards: [],
            summaryBullets: [],
            participantNames: [.self: "Pessoa 2", .other: "Pessoa 1"],
            hasAudio: true,
            audioDuration: duration,
            origin: origin,
            displayTitle: resolvedTitle(title, sourceURL: sourceURL, origin: origin, date: startedAt)
        )
        guard let directory = SessionStore.prepareSession(id: id, startedAt: startedAt) else {
            throw AudioImportError.cannotCreateSession
        }
        let destination = directory.appendingPathComponent(MeetingRecording.otherFilename)
        do {
            if isPortableAAC(sourceURL) {
                try FileManager.default.copyItem(at: sourceURL, to: destination)
            } else {
                try await exportM4A(asset: asset, destination: destination)
            }
            guard SessionStore.save(record) != nil else { throw AudioImportError.cannotCreateSession }
            return record
        } catch {
            try? FileManager.default.removeItem(at: directory)
            if error is AudioImportError { throw error }
            throw AudioImportError.conversionFailed
        }
    }

    private static func exportM4A(asset: AVAsset, destination: URL) async throws {
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw AudioImportError.unsupportedFile
        }
        try await exporter.export(to: destination, as: .m4a)
    }

    private static func isPortableAAC(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "m4a",
              let file = try? AVAudioFile(forReading: url) else { return false }
        return file.fileFormat.streamDescription.pointee.mFormatID == kAudioFormatMPEG4AAC
    }

    private static func resolvedTitle(_ title: String?, sourceURL: URL, origin: SessionOrigin, date: Date) -> String {
        let explicit = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !explicit.isEmpty { return explicit }
        let filename = sourceURL.deletingPathExtension().lastPathComponent
        if origin != .voiceMemo, !filename.isEmpty { return filename }
        return "Voice Memo · \(date.formatted(date: .abbreviated, time: .shortened))"
    }
}

struct VoiceMemoItem: Identifiable, Sendable, Equatable {
    let url: URL
    let title: String
    let createdAt: Date
    let duration: TimeInterval
    var id: String { url.standardizedFileURL.path }
}

enum VoiceMemoLibrary {
    static var knownRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(
                "Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings",
                isDirectory: true
            ),
            home.appendingPathComponent(
                "Library/Application Support/com.apple.voicememos/Recordings",
                isDirectory: true
            )
        ]
    }

    static func audioURLs(in roots: [URL] = knownRoots) -> [URL] {
        let supported = Set(["m4a", "mp3", "wav", "aif", "aiff", "caf"])
        var result: [URL] = []
        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator where supported.contains(url.pathExtension.lowercased()) {
                result.append(url)
            }
        }
        return Array(Set(result.map(\.standardizedFileURL)))
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    static func discover(in roots: [URL] = knownRoots) async -> [VoiceMemoItem] {
        var items: [VoiceMemoItem] = []
        for url in audioURLs(in: roots) {
            let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            let date = values?.creationDate ?? values?.contentModificationDate ?? .distantPast
            let asset = AVURLAsset(url: url)
            let duration = (try? await asset.load(.duration).seconds) ?? 0
            let metadata = try? await asset.load(.commonMetadata)
            let titleItem = metadata.flatMap {
                AVMetadataItem.metadataItems(from: $0, filteredByIdentifier: .commonIdentifierTitle).first
            }
            let embeddedTitle: String?
            if let titleItem {
                embeddedTitle = try? await titleItem.load(.stringValue)
            } else {
                embeddedTitle = nil
            }
            let title = embeddedTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            items.append(.init(
                url: url,
                title: title?.isEmpty == false
                    ? title!
                    : "Voice Memo · \(date.formatted(date: .abbreviated, time: .shortened))",
                createdAt: date,
                duration: duration
            ))
        }
        return items.sorted { $0.createdAt > $1.createdAt }
    }
}
