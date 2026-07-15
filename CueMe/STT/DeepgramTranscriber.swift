import AVFoundation
import Foundation
import OSLog

/// Low-latency Deepgram Nova-3 streaming session for one capture origin.
actor DeepgramTranscriber: SttSession {
    private let log = Logger(subsystem: "CueMe", category: "DeepgramTranscriber")
    private let config: SttConfig
    private let apiKey: String
    private let encoder = DeepgramAudioEncoder()
    private var assembler: DeepgramTranscriptAssembler

    nonisolated let events: AsyncStream<TranscriptEvent>
    private let eventsContinuation: AsyncStream<TranscriptEvent>.Continuation
    private let audioStream: AsyncStream<Data>
    private let audioContinuation: AsyncStream<Data>.Continuation

    private var socket: URLSessionWebSocketTask?
    private var networkSession: URLSession?
    private var senderTask: Task<Void, Never>?
    private var receiverTask: Task<Void, Never>?
    private var keepAliveTask: Task<Void, Never>?
    private var isActive = false

    init(config: SttConfig, apiKey: String) {
        self.config = config
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.assembler = DeepgramTranscriptAssembler(speaker: config.speaker)

        let (events, eventsContinuation) = AsyncStream<TranscriptEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(256)
        )
        self.events = events
        self.eventsContinuation = eventsContinuation
        let (audioStream, audioContinuation) = AsyncStream<Data>.makeStream(
            bufferingPolicy: .bufferingNewest(300)
        )
        self.audioStream = audioStream
        self.audioContinuation = audioContinuation
    }

    func start() async throws {
        guard !apiKey.isEmpty else { throw DeepgramError.missingAPIKey }
        let connection = try await DeepgramSocketConnector.connect(config: config, apiKey: apiKey)
        self.networkSession = connection.session
        self.socket = connection.socket
        isActive = true

        senderTask = Task { [weak self, audioStream] in
            for await data in audioStream {
                guard let self, !Task.isCancelled else { return }
                await self.sendAudio(data)
            }
        }
        receiverTask = Task { [weak self] in await self?.receiveLoop() }
        keepAliveTask = Task { [weak self] in await self?.keepAliveLoop() }

        log.info("Deepgram Nova-3 iniciado (\(self.config.speaker.rawValue, privacy: .public), \(self.config.localeIdentifier, privacy: .public))")
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        guard isActive, let data = encoder.encode(buffer), !data.isEmpty else { return }
        audioContinuation.yield(data)
    }

    func finish() async {
        guard isActive else {
            eventsContinuation.finish()
            return
        }
        isActive = false
        audioContinuation.finish()
        await senderTask?.value
        if let socket {
            try? await socket.send(.string(#"{"type":"CloseStream"}"#))
            try? await Task.sleep(for: .milliseconds(180))
            socket.cancel(with: .normalClosure, reason: nil)
        }
        senderTask?.cancel()
        receiverTask?.cancel()
        keepAliveTask?.cancel()
        senderTask = nil
        receiverTask = nil
        keepAliveTask = nil
        socket = nil
        networkSession?.invalidateAndCancel()
        networkSession = nil
        eventsContinuation.finish()
    }

    private func sendAudio(_ data: Data) async {
        guard isActive, let socket else { return }
        do {
            try await socket.send(.data(data))
        } catch {
            log.error("Falha ao enviar áudio para a Deepgram")
        }
    }

    private func receiveLoop() async {
        guard let socket else { return }
        do {
            while isActive, !Task.isCancelled {
                let message = try await socket.receive()
                let data: Data
                switch message {
                case .data(let value): data = value
                case .string(let value): data = Data(value.utf8)
                @unknown default: continue
                }
                if let event = assembler.consume(data) {
                    eventsContinuation.yield(event)
                }
            }
        } catch {
            if isActive { log.error("Stream da Deepgram foi interrompido") }
        }
    }

    private func keepAliveLoop() async {
        while isActive, !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            guard isActive, let socket else { return }
            try? await socket.send(.string(#"{"type":"KeepAlive"}"#))
        }
    }

}
