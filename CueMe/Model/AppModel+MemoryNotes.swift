import Foundation

@MainActor
extension AppModel {
    var allLabels: [String] {
        Array(Set(history.flatMap(\.labels))).sorted()
    }

    func liveSessionBrief() -> SessionBrief {
        var snapshot = brief
        snapshot.relevantMemoryContext = usePersonalMemoryInCoach
            ? RelevantMemoryContextBuilder.build(for: brief, records: history)
            : nil
        return snapshot
    }

    func reloadWorkspaceFromDisk() {
        guard !isSessionBusy else { return }
        // App activation can race with `.task { delegate.connect(app) }` during
        // UI tests. Never replace the deterministic in-memory corpus with the
        // intentionally empty temporary archive used by the test process.
        if ProcessInfo.processInfo.environment["CUEME_UI_TESTING"] == "1" {
            return
        }
        projects = ProjectWorkspaceStore.loadAll()
        history = SessionStore.loadAll()
        if let selectedSessionID, !history.contains(where: { $0.id == selectedSessionID }) {
            self.selectedSessionID = nil
        }
    }

    @discardableResult
    func createMemoryNote(kind: MemoryNoteKind = .note) -> UUID {
        let now = Date()
        let initialTitle: String
        switch kind {
        case .journal:
            initialTitle = "Diário · \(now.formatted(date: .abbreviated, time: .omitted))"
        case .note:
            initialTitle = "Nota sem título"
        default:
            initialTitle = kind.label
        }
        var note = MemoryNote(
            startedAt: now,
            endedAt: now,
            mode: .recording,
            training: false,
            conversationLang: brief.nativeLang,
            nativeLang: brief.nativeLang,
            goal: "",
            transcript: [],
            coachCards: [],
            summaryBullets: [],
            origin: .written,
            displayTitle: initialTitle,
            projectID: activeProjectID,
            noteKind: kind,
            markdownBody: "",
            titleSource: .fallback
        )
        SessionStore.save(note)
        if let project = projects.first(where: { $0.id == activeProjectID }),
           let moved = SessionStore.relocate(note, to: project) {
            note = moved
        }
        replaceHistoryRecord(note)
        selectedSessionID = note.id
        return note.id
    }

    func renameMemoryNote(_ id: UUID, to title: String) {
        mutateRecord(id) { $0.rename(to: title) }
    }

    func updateMarkdownBody(_ id: UUID, body: String) {
        mutateRecord(id) { $0.markdownBody = body }
    }

    func addLabel(_ rawLabel: String, to id: UUID) {
        mutateRecord(id) { note in
            note.setLabels(note.labels + [rawLabel])
        }
    }

    func removeLabel(_ label: String, from id: UUID) {
        mutateRecord(id) { note in
            note.setLabels(note.labels.filter { $0 != label })
        }
    }

    func addAttachment(from source: URL, to id: UUID) throws {
        guard let note = history.first(where: { $0.id == id }) else { return }
        let secured = source.startAccessingSecurityScopedResource()
        defer { if secured { source.stopAccessingSecurityScopedResource() } }
        let attachments = SessionStore.archiveDirectory(for: note)
            .appendingPathComponent("attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
        let filename = uniqueFilename(source.lastPathComponent, in: attachments)
        try FileManager.default.copyItem(at: source, to: attachments.appendingPathComponent(filename))
        mutateRecord(id) { record in
            record.attachments.append(.init(filename: "attachments/\(filename)", kind: attachmentKind(source)))
        }
    }

    private func uniqueFilename(_ original: String, in directory: URL) -> String {
        let base = (original as NSString).deletingPathExtension
        let ext = (original as NSString).pathExtension
        var candidate = original
        var counter = 2
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            candidate = ext.isEmpty ? "\(base)-\(counter)" : "\(base)-\(counter).\(ext)"
            counter += 1
        }
        return candidate
    }

    private func attachmentKind(_ url: URL) -> NoteAttachmentKind {
        switch url.pathExtension.lowercased() {
        case "m4a", "mp3", "wav", "aif", "aiff", "caf": return .audio
        case "png", "jpg", "jpeg", "heic", "gif": return .image
        case "pdf", "md", "txt", "doc", "docx": return .document
        default: return .file
        }
    }
}
