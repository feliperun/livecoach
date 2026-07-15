import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
extension AppModel {
    func chooseAudioFiles() {
        guard !isSessionBusy, audioImportStatus?.isActive != true else { return }
        let panel = NSOpenPanel()
        panel.title = "Importar áudio de reunião"
        panel.prompt = "Importar"
        panel.allowedContentTypes = [.audio]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        Task { await importAudioFiles(urls) }
    }

    func importAudioFiles(_ urls: [URL]) async {
        await importExternalAudioFiles(urls, origin: .audioFile)
    }

    func importDroppedAudio(_ providers: [NSItemProvider]) async {
        guard await ExternalAudioDropReceiver.enqueue(providers) > 0 else { return }
        await consumeExternalAudioInbox()
    }

    func importExternalAudioFiles(
        _ urls: [URL],
        origin: SessionOrigin,
        removeAfterImport: Bool = false
    ) async {
        for url in urls where ExternalAudioInbox.isSupported(filename: url.lastPathComponent) {
            let title = origin == .voiceMemo ? ExternalAudioInbox.displayName(for: url) : nil
            let imported = await importAudio(url: url, origin: origin, title: title)
            if imported, removeAfterImport { ExternalAudioInbox.remove(url) }
        }
    }

    func consumeExternalAudioInbox() async {
        guard !isSessionBusy, audioImportStatus?.isActive != true else { return }
        await importExternalAudioFiles(
            ExternalAudioInbox.pendingURLs(),
            origin: .voiceMemo,
            removeAfterImport: true
        )
    }

    func handleExternalURL(_ url: URL) async {
        if url.scheme?.lowercased() == "cueme" {
            await consumeExternalAudioInbox()
        } else if url.isFileURL, ExternalAudioInbox.isSupported(filename: url.lastPathComponent) {
            await importAudioFiles([url])
        }
    }

    func retryImportedProcessing(sessionID: UUID) async {
        guard let record = history.first(where: { $0.id == sessionID }), record.origin != .live else { return }
        await processImportedRecord(record)
    }

    func dismissAudioImportStatus() {
        guard audioImportStatus?.isActive != true else { return }
        audioImportStatus = nil
    }

    private func importAudio(url: URL, origin: SessionOrigin, title: String?) async -> Bool {
        guard !isSessionBusy, audioImportStatus?.isActive != true else { return false }
        let displayName = title ?? url.deletingPathExtension().lastPathComponent
        audioImportStatus = .init(
            phase: .preparing,
            title: displayName,
            detail: "Copiando e normalizando o áudio…",
            sessionID: nil
        )
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let record = try await AudioImportService.prepare(
                sourceURL: url,
                origin: origin,
                conversationLanguage: brief.conversationLang,
                nativeLanguage: brief.nativeLang,
                title: title
            )
            replaceHistoryRecord(record)
            selectedSessionID = record.id
            await processImportedRecord(record)
            return true
        } catch {
            audioImportStatus = .init(
                phase: .failed,
                title: displayName,
                detail: error.localizedDescription,
                sessionID: nil
            )
            return false
        }
    }

    private func processImportedRecord(_ initialRecord: SessionRecord) async {
        var record = initialRecord
        audioImportStatus = .init(
            phase: .transcribing,
            title: record.title,
            detail: sttSource == .deepgram
                ? "Transcrevendo e separando vozes com Deepgram…"
                : "Transcrevendo localmente…",
            sessionID: record.id
        )
        do {
            let mergedVocabulary = vocabulary.merged(
                keyterms: brief.keyterms + generatedContextKeyterms,
                participantNames: record.participantNames
            )
            let lines = try await PrerecordedAudioTranscriber.transcribe(
                audioURL: MeetingRecording.otherURL(for: record),
                source: sttSource,
                config: .init(
                    speaker: .other,
                    localeIdentifier: record.conversationLang,
                    keyterms: mergedVocabulary.keyterms,
                    replacements: mergedVocabulary.replacements
                ),
                startedAt: record.audioTimelineStart,
                deepgramAPIKey: DeepgramCredential.apiKey
            )
            record.transcript = lines
            if sttSource == .native {
                record.participantNames[.other] = "Gravação"
            }
            for line in lines {
                record.diagnostics.record(.init(kind: .transcription, name: "stt_final", speaker: line.speaker))
            }
            replaceHistoryRecord(record)
            SessionStore.save(record)

            audioImportStatus = .init(
                phase: .enriching,
                title: record.title,
                detail: "Gerando ata, assuntos e ações…",
                sessionID: record.id
            )
            let summaryAvailable = summaryModel.isDeepSeek ? deepSeekAvailable : claudeAvailable
            if summaryAvailable {
                await generateReview(for: record.id)
            }
            let enrichmentFailed = summaryAvailable && postProcessingError != nil
            audioImportStatus = .init(
                phase: enrichmentFailed ? .failed : .completed,
                title: record.title,
                detail: enrichmentFailed
                    ? (postProcessingError ?? "A transcrição foi salva, mas a revisão falhou.")
                    : (summaryAvailable
                        ? "Transcrição, ata e ações prontas."
                        : "Transcrição pronta. Configure um modelo para gerar a ata."),
                sessionID: record.id
            )
        } catch {
            record.diagnostics.record(.init(kind: .error, name: "audio_import_processing_failed"))
            replaceHistoryRecord(record)
            SessionStore.save(record)
            audioImportStatus = .init(
                phase: .failed,
                title: record.title,
                detail: error.localizedDescription,
                sessionID: record.id
            )
        }
    }
}
