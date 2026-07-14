import AVFoundation
import XCTest
@testable import CueMe

final class DeepgramTranscriberTests: XCTestCase {
    func testLiveURLUsesLowLatencyNova3SettingsAndRepeatedKeyterms() throws {
        let config = SttConfig(
            speaker: .other,
            localeIdentifier: "pt-BR",
            keyterms: ["CueMe", "Ramon Silva"],
            replacements: ["mono rapo": "monorepo", "centrics": "Sentry"]
        )

        let url = try DeepgramLiveRequest.url(config: config)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = components.queryItems ?? []

        XCTAssertEqual(components.scheme, "wss")
        XCTAssertEqual(components.host, "api.deepgram.com")
        XCTAssertEqual(components.path, "/v1/listen")
        XCTAssertTrue(items.contains(.init(name: "model", value: "nova-3")))
        XCTAssertTrue(items.contains(.init(name: "language", value: "pt-BR")))
        XCTAssertTrue(items.contains(.init(name: "encoding", value: "linear16")))
        XCTAssertTrue(items.contains(.init(name: "sample_rate", value: "16000")))
        XCTAssertTrue(items.contains(.init(name: "interim_results", value: "true")))
        XCTAssertTrue(items.contains(.init(name: "endpointing", value: "300")))
        XCTAssertTrue(items.contains(.init(name: "utterance_end_ms", value: "1000")))
        XCTAssertEqual(items.filter { $0.name == "keyterm" }.compactMap(\.value), ["CueMe", "Ramon Silva"])
        XCTAssertEqual(
            items.filter { $0.name == "replace" }.compactMap(\.value).sorted(),
            ["centrics:Sentry", "mono rapo:monorepo"]
        )
    }

    func testAssemblerCombinesFinalSegmentsUntilSpeechFinal() throws {
        var assembler = DeepgramTranscriptAssembler(speaker: .other)

        let first = try XCTUnwrap(assembler.consume(json(
            transcript: "Bom dia",
            isFinal: true,
            speechFinal: false
        )))
        XCTAssertEqual(first.text, "Bom dia")
        XCTAssertFalse(first.isFinal)

        let interim = try XCTUnwrap(assembler.consume(json(
            transcript: "Felipe",
            isFinal: false,
            speechFinal: false
        )))
        XCTAssertEqual(interim.text, "Bom dia Felipe")
        XCTAssertFalse(interim.isFinal)

        let final = try XCTUnwrap(assembler.consume(json(
            transcript: "Felipe.",
            isFinal: true,
            speechFinal: true
        )))
        XCTAssertEqual(final.speaker, .other)
        XCTAssertEqual(final.text, "Bom dia Felipe.")
        XCTAssertTrue(final.isFinal)
        XCTAssertTrue(final.isEndOfTurn)
    }

    func testUtteranceEndFlushesCommittedTextOnlyOnce() throws {
        var assembler = DeepgramTranscriptAssembler(speaker: .self)
        _ = assembler.consume(json(transcript: "Vamos começar", isFinal: true, speechFinal: false))

        let end = try XCTUnwrap(assembler.consume(Data(#"{"type":"UtteranceEnd"}"#.utf8)))
        XCTAssertEqual(end.text, "Vamos começar")
        XCTAssertTrue(end.isFinal)
        XCTAssertNil(assembler.consume(Data(#"{"type":"UtteranceEnd"}"#.utf8)))
    }

    func testAudioEncoderProducesMono16kLinearPCM() throws {
        let inputFormat = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        ))
        let frames = AVAudioFrameCount(inputFormat.sampleRate / 10)
        let input = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frames))
        input.frameLength = frames
        for frame in 0..<Int(frames) {
            input.floatChannelData?[0][frame] = sin(Float(frame) * 2 * .pi * 440 / 48_000) * 0.25
        }

        let encoder = DeepgramAudioEncoder()
        var encodedBytes = 0
        for _ in 0..<10 {
            let count = try XCTUnwrap(encoder.encode(input)).count
            encodedBytes += count
        }

        let expectedBytes = 16_000 * MemoryLayout<Int16>.size
        XCTAssertLessThanOrEqual(abs(encodedBytes - expectedBytes), 512)
    }

    func testProviderFactorySelectsDeepgramAndRejectsMissingKey() throws {
        let provider = try SttProviderFactory.make(source: .deepgram, deepgramAPIKey: "test-key")
        let config = SttConfig(speaker: .self, localeIdentifier: "en-US", keyterms: [])

        XCTAssertTrue(provider.makeSession(config: config) is DeepgramTranscriber)
        XCTAssertThrowsError(try SttProviderFactory.make(source: .deepgram, deepgramAPIKey: nil))
    }

    func testLiveDeepgramTranscribesSyntheticSpeech() async throws {
        let defaultAudioPath = "/tmp/cueme-deepgram-test.aiff"
        let audioPath = ProcessInfo.processInfo.environment["DEEPGRAM_TEST_AUDIO_PATH"] ?? defaultAudioPath
        let enabled = ProcessInfo.processInfo.environment["CUEME_DEEPGRAM_LIVE_TEST"] == "1"
            || FileManager.default.fileExists(atPath: defaultAudioPath)
        guard enabled else {
            throw XCTSkip("Live Deepgram test is opt-in.")
        }
        let key = try XCTUnwrap(DeepgramCredential.apiKey)
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: audioPath))
        let session = DeepgramTranscriber(
            config: .init(speaker: .self, localeIdentifier: "pt-BR", keyterms: ["transcrição"]),
            apiKey: key
        )
        let transcriptTask = Task<String?, Never> {
            for await event in session.events where event.isFinal { return event.text }
            return nil
        }

        try await session.start()
        try await Task.sleep(for: .milliseconds(250))
        while file.framePosition < file.length {
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 2_048))
            try file.read(into: buffer)
            await session.feed(buffer)
            try await Task.sleep(for: .milliseconds(35))
        }
        try await Task.sleep(for: .seconds(3))
        await session.finish()

        let transcriptValue = await transcriptTask.value
        let transcript = try XCTUnwrap(transcriptValue).lowercased()
        XCTAssertTrue(transcript.contains("teste") || transcript.contains("transcrição"), transcript)
    }

    private func json(transcript: String, isFinal: Bool, speechFinal: Bool) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "type": "Results",
            "is_final": isFinal,
            "speech_final": speechFinal,
            "channel": ["alternatives": [["transcript": transcript]]]
        ])
    }
}
