import Foundation

extension Notification.Name {
    static let cueMeExternalAudioReady = Notification.Name("com.feliperun.CueMe.externalAudioReady")
}

enum ExternalAudioInboxError: LocalizedError {
    case unavailable
    case unsupportedAudio

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Não foi possível acessar a caixa de entrada compartilhada do CueMe."
        case .unsupportedAudio:
            return "Este arquivo não é um áudio compatível."
        }
    }
}

enum ExternalAudioInbox {
    static let appGroupIdentifier = "C8D46BZNT3.com.feliperun.CueMe"
    static let wakeURL = URL(string: "cueme://import-ready")!
    nonisolated(unsafe) static var rootOverride: URL?

    private static let supportedExtensions = Set(["m4a", "mp3", "wav", "aif", "aiff", "caf"])
    private static let separator = "__"

    static func isSupported(filename: String) -> Bool {
        supportedExtensions.contains(URL(fileURLWithPath: filename).pathExtension.lowercased())
    }

    @discardableResult
    static func enqueue(data: Data, filename: String) throws -> URL {
        guard isSupported(filename: filename) else { throw ExternalAudioInboxError.unsupportedAudio }
        let destination = try destinationURL(filename: filename)
        let partial = destination.appendingPathExtension("partial")
        try data.write(to: partial, options: .atomic)
        try FileManager.default.moveItem(at: partial, to: destination)
        return destination
    }

    @discardableResult
    static func enqueueCopy(from sourceURL: URL, filename: String? = nil) throws -> URL {
        let sourceName = sourceURL.lastPathComponent
        let resolvedName: String
        if let filename, isSupported(filename: filename) {
            resolvedName = filename
        } else if let filename, isSupported(filename: sourceName) {
            let displayStem = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
            resolvedName = "\(displayStem).\(sourceURL.pathExtension)"
        } else {
            resolvedName = sourceName
        }
        guard isSupported(filename: resolvedName) else { throw ExternalAudioInboxError.unsupportedAudio }
        let destination = try destinationURL(filename: resolvedName)
        let partial = destination.appendingPathExtension("partial")
        try FileManager.default.copyItem(at: sourceURL, to: partial)
        try FileManager.default.moveItem(at: partial, to: destination)
        return destination
    }

    static func pendingURLs() -> [URL] {
        guard let directory = try? inboxDirectory(),
              let urls = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
              ) else { return [] }
        return urls
            .filter { isSupported(filename: $0.lastPathComponent) }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                if left == right { return lhs.path < rhs.path }
                return left < right
            }
    }

    static func displayName(for url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        guard let range = stem.range(of: separator) else { return stem }
        return String(stem[range.upperBound...])
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private static func destinationURL(filename: String) throws -> URL {
        let directory = try inboxDirectory()
        let source = URL(fileURLWithPath: filename)
        let stem = sanitizedStem(source.deletingPathExtension().lastPathComponent)
        let ext = source.pathExtension.lowercased()
        return directory.appendingPathComponent("\(UUID().uuidString)\(separator)\(stem).\(ext)")
    }

    private static func inboxDirectory() throws -> URL {
        let directory: URL
        if let rootOverride {
            directory = rootOverride
        } else if let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) {
            directory = group.appendingPathComponent("IncomingAudio", isDirectory: true)
        } else if !Bundle.main.bundlePath.hasSuffix(".appex") {
            directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("CueMe/IncomingAudio", isDirectory: true)
        } else {
            throw ExternalAudioInboxError.unavailable
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func sanitizedStem(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.whitespaces).union(CharacterSet(charactersIn: "-_"))
        let mapped = raw.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : " " }
        let collapsed = String(mapped)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return String((collapsed.isEmpty ? "Gravação" : collapsed).prefix(96))
    }
}
