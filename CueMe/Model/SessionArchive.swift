import Foundation

enum SessionArchive {
    static func folderName(startedAt: Date, id: UUID) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "\(formatter.string(from: startedAt))_\(id.uuidString.prefix(8))"
    }

    static func markdown(for record: SessionRecord) -> String {
        var lines = [
            "# \(record.title)",
            "",
            "- Data: \(record.startedAt.formatted(date: .long, time: .shortened))",
            "- Duração: \(clock(record.duration))",
            "- Modo: \(record.mode.label)",
            "- Origem: \(record.origin.label)",
            "- Idioma: \(record.conversationLang)",
            ""
        ]
        appendSummary(record, to: &lines)
        appendTakeaways(record, to: &lines)
        appendReview(record, to: &lines)
        appendNotes(record, to: &lines)
        appendCoach(record, to: &lines)
        appendTranscript(record, to: &lines)
        appendArtifacts(record, to: &lines)
        appendHealth(record, to: &lines)
        return lines.joined(separator: "\n") + "\n"
    }

    static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%02d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }

    private static func appendSummary(_ record: SessionRecord, to lines: inout [String]) {
        guard !record.minutes.isEmpty || !record.summaryBullets.isEmpty else { return }
        lines += ["## Ata", ""]
        if !record.minutes.overview.isEmpty {
            lines += [record.minutes.overview, ""]
        }
        if !record.minutes.topics.isEmpty {
            lines += ["### Assuntos", ""]
            for topic in record.minutes.topics {
                lines += ["#### \(topic.title)", "", topic.summary, ""]
            }
        } else {
            lines += record.summaryBullets.map { "- \($0)" }
        }
        lines.append("")
    }

    private static func appendTakeaways(_ record: SessionRecord, to lines: inout [String]) {
        lines += ["## Pendências", ""]
        if record.takeaways.isEmpty {
            lines.append("_Nenhuma pendência registrada._")
        } else {
            lines += record.takeaways.map { "- [\($0.isDone ? "x" : " ")] \($0.text)" }
        }
        lines.append("")
    }

    private static func appendReview(_ record: SessionRecord, to lines: inout [String]) {
        guard !record.review.isEmpty else { return }
        if !record.review.decisions.isEmpty {
            lines += ["## Decisões", ""]
            lines += record.review.decisions.map { "- \($0.text)" }
            lines.append("")
        }
        if !record.review.openQuestions.isEmpty {
            lines += ["## Questões em aberto", ""]
            lines += record.review.openQuestions.map { "- \($0.text)" }
            lines.append("")
        }
        if !record.review.followUp.isEmpty {
            lines += ["## Follow-up", "", record.review.followUp, ""]
        }
    }

    private static func appendNotes(_ record: SessionRecord, to lines: inout [String]) {
        guard !record.notes.isEmpty else { return }
        lines += ["## Anotações", ""]
        lines += record.notes.sorted { $0.timeOffset < $1.timeOffset }
            .map { "- [\(clock($0.timeOffset))] \($0.text)" }
        lines.append("")
    }

    private static func appendCoach(_ record: SessionRecord, to lines: inout [String]) {
        let cards = record.coachCards.filter(\.hasContent)
        guard !cards.isEmpty else { return }
        lines += ["## Coach", ""]
        for card in cards {
            lines.append("### \(clock(card.ts.timeIntervalSince(record.startedAt)))")
            if !card.guidePT.isEmpty { lines.append(card.guidePT) }
            if let phrase = card.sayConversation ?? (card.sayNative.isEmpty ? nil : card.sayNative) {
                lines.append("")
                lines.append("> \(phrase)")
            }
            lines.append("")
        }
    }

    private static func appendTranscript(_ record: SessionRecord, to lines: inout [String]) {
        guard !record.transcript.isEmpty else { return }
        lines += ["## Transcrição", ""]
        for line in record.transcript where line.isFinal {
            let offset = line.ts.timeIntervalSince(record.audioTimelineStart)
            lines.append("**\(record.participantName(for: line.speaker)) · \(clock(offset))**")
            lines.append(line.text)
            if line.wasEdited, let original = line.originalText {
                lines.append("")
                lines.append("_Corrigido. Original: \(original)_")
            }
            if let translation = line.translation, !translation.isEmpty {
                lines.append("")
                lines.append("_\(translation)_")
            }
            lines.append("")
        }
    }

    private static func appendArtifacts(_ record: SessionRecord, to lines: inout [String]) {
        guard !record.artifacts.isEmpty else { return }
        lines += ["## Conteúdo gerado", ""]
        for artifact in record.artifacts {
            lines += ["### \(artifact.title)", "", artifact.body, ""]
        }
    }

    private static func appendHealth(_ record: SessionRecord, to lines: inout [String]) {
        let report = SessionIntegrityReport(record: record)
        let audioCoverage = report.recordingExpected ? "\(report.audioCoveragePercent)%" : "desativada"
        lines += [
            "## Integridade da sessão", "",
            "- Cobertura de áudio: \(audioCoverage)",
            "- Falas transcritas: \(report.transcriptTurns)",
            "- Recuperações automáticas: \(report.recoveries)",
            "- Erros registrados: \(report.errors)", ""
        ]
    }
}

enum SessionStore {
    nonisolated(unsafe) static var rootOverride: URL?
    private static let configuredRootKey = "sessionArchiveRootPath"

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static var rootURL: URL {
        if let rootOverride { return rootOverride }
        if let path = UserDefaults.standard.string(forKey: configuredRootKey), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("CueMe/Session Archive", isDirectory: true)
    }

    static var hasCustomRoot: Bool {
        UserDefaults.standard.string(forKey: configuredRootKey) != nil
    }

    static func setRoot(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        UserDefaults.standard.set(url.standardizedFileURL.path, forKey: configuredRootKey)
    }

    static func archiveDirectory(for record: SessionRecord) -> URL {
        rootURL.appendingPathComponent(record.archiveFolderName, isDirectory: true)
    }

    static func prepareSession(id: UUID, startedAt: Date) -> URL? {
        let directory = rootURL.appendingPathComponent(
            SessionArchive.folderName(startedAt: startedAt, id: id),
            isDirectory: true
        )
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        } catch {
            return nil
        }
    }

    @discardableResult
    static func save(_ record: SessionRecord) -> URL? {
        let directory = archiveDirectory(for: record)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try encoder.encode(record)
            try data.write(to: directory.appendingPathComponent("session.json"), options: .atomic)
            try SessionArchive.markdown(for: record)
                .write(to: directory.appendingPathComponent("session.md"), atomically: true, encoding: .utf8)
            return directory
        } catch {
            return nil
        }
    }

    static func loadAll() -> [SessionRecord] {
        var records: [UUID: SessionRecord] = [:]
        for record in loadArchive() { records[record.id] = record }
        for record in loadLegacy() where records[record.id] == nil { records[record.id] = record }
        return records.values.sorted { $0.startedAt > $1.startedAt }
    }

    static func delete(_ record: SessionRecord) {
        try? FileManager.default.removeItem(at: archiveDirectory(for: record))
        try? FileManager.default.removeItem(at: legacyDirectory().appendingPathComponent("\(record.id.uuidString).json"))
        MeetingRecording.deleteLegacy(for: record.id)
    }

    static func delete(_ id: UUID) {
        if let record = loadAll().first(where: { $0.id == id }) {
            delete(record)
        } else {
            try? FileManager.default.removeItem(at: legacyDirectory().appendingPathComponent("\(id.uuidString).json"))
            MeetingRecording.deleteLegacy(for: id)
        }
    }

    private static func loadArchive() -> [SessionRecord] {
        guard let folders = try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return folders.compactMap { folder in
            let url = folder.appendingPathComponent("session.json")
            return try? decoder.decode(SessionRecord.self, from: Data(contentsOf: url))
        }
    }

    private static func loadLegacy() -> [SessionRecord] {
        guard rootOverride == nil,
              let files = try? FileManager.default.contentsOfDirectory(
                at: legacyDirectory(),
                includingPropertiesForKeys: nil
              ) else { return [] }
        return files.filter { $0.pathExtension == "json" }.compactMap {
            try? decoder.decode(SessionRecord.self, from: Data(contentsOf: $0))
        }
    }

    private static func legacyDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("CueMe/sessions", isDirectory: true)
    }
}
