@preconcurrency import AVFoundation
import Foundation
import Speech

enum PrerecordedAudioTranscriber {
    static func transcribe(
        audioURL: URL,
        source: SttSource,
        config: SttConfig,
        startedAt: Date,
        deepgramAPIKey: String?
    ) async throws -> [TranscriptLine] {
        let lines: [TranscriptLine]
        switch source {
        case .native:
            lines = try await transcribeNatively(audioURL: audioURL, config: config, startedAt: startedAt)
        case .deepgram:
            let key = deepgramAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !key.isEmpty else { throw DeepgramError.missingAPIKey }
            lines = try await transcribeWithDeepgram(
                audioURL: audioURL,
                config: config,
                startedAt: startedAt,
                apiKey: key
            )
        }
        guard !lines.isEmpty else { throw AudioImportError.transcriptionFailed }
        return lines
    }

    private static func transcribeNatively(
        audioURL: URL,
        config: SttConfig,
        startedAt: Date
    ) async throws -> [TranscriptLine] {
        let locale = Locale(identifier: config.localeIdentifier)
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )
        try await NativeTranscriber.ensureModel(for: transcriber, locale: locale)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let audioFile = try AVAudioFile(forReading: audioURL)
        let collector = Task<[TranscriptLine], Error> {
            var lines: [TranscriptLine] = []
            for try await result in transcriber.results {
                let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let offset = max(0, result.range.start.seconds)
                lines.append(.init(
                    speaker: .other,
                    text: text,
                    isFinal: true,
                    ts: startedAt.addingTimeInterval(offset)
                ))
            }
            return lines
        }
        do {
            try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)
            return try await collector.value
        } catch {
            collector.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }

    private static func transcribeWithDeepgram(
        audioURL: URL,
        config: SttConfig,
        startedAt: Date,
        apiKey: String
    ) async throws -> [TranscriptLine] {
        guard let url = DeepgramPrerecordedRequest.url(config: config) else {
            throw DeepgramError.invalidEndpoint
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType(for: audioURL), forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60 * 60
        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: audioURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DeepgramError.connectionFailed
        }
        return try DeepgramPrerecordedResponseParser.parse(data, startedAt: startedAt)
    }

    private static func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "m4a": return "audio/mp4"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "aif", "aiff": return "audio/aiff"
        case "caf": return "audio/x-caf"
        default: return "application/octet-stream"
        }
    }
}
