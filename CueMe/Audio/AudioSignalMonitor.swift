import AVFoundation

/// Análise barata para callbacks de áudio: nível visual e detecção de zero
/// digital no mic. Estado protegido porque mic e ScreenCaptureKit têm filas
/// independentes.
final class AudioSignalMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var zeroSince: [Speaker: TimeInterval] = [:]
    private var lastLevelEmission: [Speaker: TimeInterval] = [:]
    private var reportedState: [Speaker: CaptureChannelState] = [:]

    func reset(_ source: Speaker) {
        lock.withLock {
            zeroSince[source] = nil
            lastLevelEmission[source] = nil
            reportedState[source] = nil
        }
    }

    /// Sistema pode emitir zero quando ninguém fala; só o ciclo do SCStream
    /// determina sua saúde. No mic, near-zero contínuo indica device/tap quebrado.
    func observe(
        _ buffer: AVAudioPCMBuffer,
        source: Speaker,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> [AudioCaptureEvent] {
        let peak = Self.peakAmplitude(buffer)
        let level: Float = peak <= 0 ? 0 : min(1, max(0, (20 * log10(peak) + 60) / 60))

        return lock.withLock {
            var events: [AudioCaptureEvent] = []
            if now - (lastLevelEmission[source] ?? 0) >= 0.15 {
                lastLevelEmission[source] = now
                events.append(.level(source, level))
            }
            if source == .other {
                zeroSince[source] = nil
                appendState(.active, source: source, to: &events)
            } else if peak <= 0.000_04 {
                let began = zeroSince[source] ?? now
                zeroSince[source] = began
                if now - began >= 2 { appendState(.silent, source: source, to: &events) }
            } else {
                zeroSince[source] = nil
                appendState(.active, source: source, to: &events)
            }
            return events
        }
    }

    private func appendState(
        _ state: CaptureChannelState,
        source: Speaker,
        to events: inout [AudioCaptureEvent]
    ) {
        guard reportedState[source] != state else { return }
        reportedState[source] = state
        events.append(.state(source, state))
    }

    private static func peakAmplitude(_ buffer: AVAudioPCMBuffer) -> Float {
        let frames = Int(buffer.frameLength)
        let channels = max(1, Int(buffer.format.channelCount))
        guard frames > 0 else { return 0 }
        let sampleCount = buffer.format.isInterleaved ? frames * channels : frames
        let planes = buffer.format.isInterleaved ? 1 : channels
        var peak: Float = 0

        if let data = buffer.floatChannelData {
            for channel in 0..<planes {
                for i in stride(from: 0, to: sampleCount, by: 4) {
                    peak = max(peak, abs(data[channel][i]))
                }
            }
        } else if let data = buffer.int16ChannelData {
            for channel in 0..<planes {
                for i in stride(from: 0, to: sampleCount, by: 4) {
                    peak = max(peak, abs(Float(data[channel][i])) / 32_768)
                }
            }
        } else if let data = buffer.int32ChannelData {
            for channel in 0..<planes {
                for i in stride(from: 0, to: sampleCount, by: 4) {
                    peak = max(peak, abs(Float(data[channel][i])) / 2_147_483_648)
                }
            }
        }
        return peak
    }
}
