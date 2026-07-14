import AppKit
import Foundation

@MainActor
extension AppModel {
    var selectedSession: SessionRecord? {
        guard let selectedSessionID else { return nil }
        return history.first { $0.id == selectedSessionID }
    }

    var archivePath: String { SessionStore.rootURL.path }

    func showLiveSession() {
        selectedSessionID = nil
    }

    func selectSession(_ id: UUID) {
        selectedSessionID = id
    }

    func addLiveNote() {
        let text = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let startedAt = sessionStartTime else { return }
        sessionNotes.append(.init(timeOffset: Date().timeIntervalSince(startedAt), text: text))
        noteDraft = ""
        persistLiveSnapshot()
    }

    func addNote(to sessionID: UUID, text rawText: String, timeOffset: TimeInterval) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        mutateRecord(sessionID) { record in
            record.notes.append(.init(timeOffset: timeOffset, text: text))
        }
    }

    func updateLiveNote(_ noteID: UUID, text rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let index = sessionNotes.firstIndex(where: { $0.id == noteID }) else { return }
        sessionNotes[index].text = text
        persistLiveSnapshot()
    }

    func deleteLiveNote(_ noteID: UUID) {
        sessionNotes.removeAll { $0.id == noteID }
        persistLiveSnapshot()
    }

    func updateNote(sessionID: UUID, noteID: UUID, text rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        mutateRecord(sessionID) { record in
            guard let index = record.notes.firstIndex(where: { $0.id == noteID }) else { return }
            record.notes[index].text = text
        }
    }

    func deleteNote(sessionID: UUID, noteID: UUID) {
        mutateRecord(sessionID) { $0.notes.removeAll { $0.id == noteID } }
    }

    func setParticipantName(_ rawName: String, for speaker: Speaker, sessionID: UUID) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        mutateRecord(sessionID) { record in
            record.participantNames[speaker] = name.isEmpty ? speaker.label : name
            if !name.isEmpty { record.vocabulary.addKeyterm(name) }
        }
        if !name.isEmpty { vocabulary.addKeyterm(name) }
    }

    func correctTranscript(sessionID: UUID, lineID: UUID, text rawText: String, learn: Bool = true) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        mutateRecord(sessionID) { record in
            guard let index = record.transcript.firstIndex(where: { $0.id == lineID }) else { return }
            let original = record.transcript[index].text
            record.transcript[index].applyCorrection(text)
            if record.isForeign { record.transcript[index].translation = nil }
            if learn, original != record.transcript[index].text {
                _ = record.vocabulary.learnCorrection(from: original, to: record.transcript[index].text)
                _ = vocabulary.learnCorrection(from: original, to: record.transcript[index].text)
            }
        }
    }

    func addTakeaway(to sessionID: UUID, text rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        mutateRecord(sessionID) { record in
            record.takeaways.append(.init(text: text))
        }
    }

    func toggleTakeaway(sessionID: UUID, takeawayID: UUID) {
        mutateRecord(sessionID) { record in
            guard let index = record.takeaways.firstIndex(where: { $0.id == takeawayID }) else { return }
            record.takeaways[index].isDone.toggle()
        }
    }

    func chooseArchiveRoot() {
        guard !isSessionBusy else { return }
        let panel = NSOpenPanel()
        panel.title = "Escolha onde salvar suas reuniões"
        panel.prompt = "Usar esta pasta"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SessionStore.setRoot(url)
            history = SessionStore.loadAll()
            selectedSessionID = nil
        } catch {
            postProcessingError = "Não foi possível usar essa pasta."
        }
    }

    func revealArchive() {
        try? FileManager.default.createDirectory(at: SessionStore.rootURL, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([SessionStore.rootURL])
    }

    func generateSummary(for sessionID: UUID) async {
        await generateArtifact(
            for: sessionID,
            request: "Resuma decisões, contexto e pontos em aberto.",
            kind: .summary,
            title: "Resumo atualizado"
        )
    }

    func generateTakeaways(for sessionID: UUID) async {
        await generateArtifact(
            for: sessionID,
            request: "Extraia apenas ações, tarefas e combinados que ainda precisam ser feitos.",
            kind: .takeaways,
            title: "Pendências extraídas"
        )
    }

    func askAboutSession(_ sessionID: UUID) {
        let request = postSessionPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }
        postSessionPrompt = ""
        Task {
            await generateArtifact(
                for: sessionID,
                request: request,
                kind: .answer,
                title: request
            )
        }
    }

    func generateArtifact(
        for sessionID: UUID,
        request: String,
        kind: SessionArtifactKind,
        title: String
    ) async {
        guard postProcessingSessionID == nil,
              let record = history.first(where: { $0.id == sessionID }) else { return }
        postProcessingSessionID = sessionID
        postProcessingError = nil
        do {
            let output = try await SessionPostProcessor.generate(
                record: record,
                request: request,
                kind: kind,
                model: kind == .summary ? summaryModel : coachModel
            )
            mutateRecord(sessionID) { updated in
                updated.artifacts.append(.init(kind: kind, title: title, body: output))
                switch kind {
                case .summary:
                    if let minutes = MeetingMinutes.parse(modelOutput: output, preserving: updated.minutes) {
                        updated.minutes = minutes
                        updated.summaryBullets = minutes.topics.map { "\($0.title): \($0.summary)" }
                    }
                case .takeaways:
                    let generated = SessionPostProcessor.parseTakeaways(output)
                    let existing = Set(updated.takeaways.map { $0.text.lowercased() })
                    updated.takeaways.append(contentsOf: generated.filter { !existing.contains($0.text.lowercased()) })
                case .answer, .custom:
                    break
                }
            }
        } catch {
            postProcessingError = error.localizedDescription
        }
        postProcessingSessionID = nil
    }

    func replaceHistoryRecord(_ record: SessionRecord) {
        history.removeAll { $0.id == record.id }
        history.append(record)
        history.sort { $0.startedAt > $1.startedAt }
    }

    private func mutateRecord(_ id: UUID, mutation: (inout SessionRecord) -> Void) {
        guard let index = history.firstIndex(where: { $0.id == id }) else { return }
        mutation(&history[index])
        SessionStore.save(history[index])
    }

    func persistLiveSnapshot() {
        guard let startedAt = sessionStartTime, let id = currentSessionID else { return }
        let record = SessionRecord(
            id: id,
            startedAt: startedAt,
            endedAt: Date(),
            mode: brief.mode,
            training: trainingMode,
            conversationLang: brief.conversationLang,
            nativeLang: brief.nativeLang,
            goal: brief.goal,
            transcript: transcript,
            coachCards: coachCards.filter(\.hasContent),
            summaryBullets: summaryBullets,
            minutes: minutes,
            participantNames: participantNames,
            coachModel: coachModel,
            summaryModel: summaryModel,
            vocabulary: vocabulary,
            hasAudio: recordAudio,
            audioDuration: Date().timeIntervalSince(startedAt),
            diagnostics: diagnostics,
            coachFeedback: coachFeedback,
            notes: sessionNotes,
            takeaways: sessionTakeaways,
            artifacts: sessionArtifacts
        )
        SessionStore.save(record)
    }

    private static func parseBullets(_ output: String) -> [String] {
        output.split(whereSeparator: \Character.isNewline).compactMap { raw in
            var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("- ") { line.removeFirst(2) }
            return line.isEmpty ? nil : line
        }
    }
}
