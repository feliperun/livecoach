import AVFoundation
import Foundation

enum DeepgramLiveRequest {
    static func url(config: SttConfig) throws -> URL {
        var components = URLComponents(string: "wss://api.deepgram.com/v1/listen")
        var items = [
            URLQueryItem(name: "model", value: "nova-3"),
            URLQueryItem(name: "language", value: config.localeIdentifier),
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: "16000"),
            URLQueryItem(name: "channels", value: "1"),
            URLQueryItem(name: "interim_results", value: "true"),
            URLQueryItem(name: "endpointing", value: "300"),
            URLQueryItem(name: "utterance_end_ms", value: "1000"),
            URLQueryItem(name: "vad_events", value: "true"),
            URLQueryItem(name: "punctuate", value: "true"),
            URLQueryItem(name: "smart_format", value: "true")
        ]
        items += sanitizedKeyterms(config.keyterms).map { URLQueryItem(name: "keyterm", value: $0) }
        items += sanitizedReplacements(config.replacements).map {
            URLQueryItem(name: "replace", value: "\($0.key):\($0.value)")
        }
        components?.queryItems = items
        guard let url = components?.url else { throw DeepgramError.invalidEndpoint }
        return url
    }

    private static func sanitizedKeyterms(_ values: [String]) -> [String] {
        GlossaryTermPolicy.sanitized(values)
    }

    private static func sanitizedReplacements(_ values: [String: String]) -> [(key: String, value: String)] {
        var result: [(key: String, value: String)] = []
        for (rawKey, rawValue) in values {
            let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty, !key.contains(":"), !value.contains(":") else { continue }
            result.append((String(key.prefix(120)), String(value.prefix(120))))
        }
        result.sort { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
        return Array(result.prefix(200))
    }
}

enum DeepgramError: LocalizedError {
    case missingAPIKey
    case invalidEndpoint
    case connectionFailed

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Configure a chave da Deepgram."
        case .invalidEndpoint: return "Não foi possível configurar a transcrição da Deepgram."
        case .connectionFailed: return "Não foi possível conectar à Deepgram."
        }
    }
}

final class DeepgramAudioEncoder {
    static let sampleRate: Double = 16_000
    private var inputSampleRate: Double?
    private var sourcePosition: Double = 0

    func encode(_ input: AVAudioPCMBuffer) -> Data? {
        let format = input.format
        let frameCount = Int(input.frameLength)
        let channelCount = Int(format.channelCount)
        guard frameCount > 0, channelCount > 0, format.sampleRate > 0 else { return nil }

        if inputSampleRate != format.sampleRate {
            inputSampleRate = format.sampleRate
            sourcePosition = 0
        }

        let step = format.sampleRate / Self.sampleRate
        var output: [Int16] = []
        output.reserveCapacity(Int(Double(frameCount) / step) + 2)
        while sourcePosition < Double(frameCount) {
            let left = min(Int(sourcePosition), frameCount - 1)
            let right = min(left + 1, frameCount - 1)
            let fraction = Float(sourcePosition - Double(left))
            let a = monoSample(input, frame: left, channels: channelCount)
            let b = monoSample(input, frame: right, channels: channelCount)
            let sample = max(-1, min(1, a + (b - a) * fraction))
            output.append(Int16(sample * Float(Int16.max)).littleEndian)
            sourcePosition += step
        }
        sourcePosition -= Double(frameCount)
        return output.withUnsafeBytes { Data($0) }
    }

    private func monoSample(_ buffer: AVAudioPCMBuffer, frame: Int, channels: Int) -> Float {
        var total: Float = 0
        for channel in 0..<channels {
            total += sample(buffer, frame: frame, channel: channel, channels: channels)
        }
        return total / Float(channels)
    }

    private func sample(_ buffer: AVAudioPCMBuffer, frame: Int, channel: Int, channels: Int) -> Float {
        let index = buffer.format.isInterleaved ? frame * channels + channel : frame
        let plane = buffer.format.isInterleaved ? 0 : channel
        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            return buffer.floatChannelData?[plane][index] ?? 0
        case .pcmFormatFloat64:
            let buffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            guard plane < buffers.count, let bytes = buffers[plane].mData else { return 0 }
            return Float(bytes.assumingMemoryBound(to: Double.self)[index])
        case .pcmFormatInt16:
            return Float(buffer.int16ChannelData?[plane][index] ?? 0) / 32_768
        case .pcmFormatInt32:
            return Float(buffer.int32ChannelData?[plane][index] ?? 0) / 2_147_483_648
        default:
            return 0
        }
    }
}

struct DeepgramTranscriptAssembler {
    let speaker: Speaker
    private var committed: [String] = []

    init(speaker: Speaker) {
        self.speaker = speaker
    }

    mutating func consume(_ data: Data) -> TranscriptEvent? {
        guard let message = try? JSONDecoder().decode(DeepgramServerMessage.self, from: data) else {
            return nil
        }
        if message.type == "UtteranceEnd" {
            return flushFinal()
        }
        guard message.type == "Results" else { return nil }

        let transcript = message.channel?.alternatives.first?.transcript
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if message.isFinal == true, !transcript.isEmpty {
            committed.append(transcript)
        }

        if message.speechFinal == true {
            return flushFinal(fallback: transcript)
        }

        let text = joined(transcript: message.isFinal == true ? "" : transcript)
        guard !text.isEmpty else { return nil }
        return TranscriptEvent(speaker: speaker, text: text, isFinal: false, isEndOfTurn: false)
    }

    private mutating func flushFinal(fallback: String = "") -> TranscriptEvent? {
        let text = joined(transcript: committed.isEmpty ? fallback : "")
        committed.removeAll(keepingCapacity: true)
        guard !text.isEmpty else { return nil }
        return TranscriptEvent(speaker: speaker, text: text, isFinal: true, isEndOfTurn: true)
    }

    private func joined(transcript: String) -> String {
        (committed + (transcript.isEmpty ? [] : [transcript]))
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct DeepgramServerMessage: Decodable {
    let type: String?
    let isFinal: Bool?
    let speechFinal: Bool?
    let channel: Channel?

    enum CodingKeys: String, CodingKey {
        case type, channel
        case isFinal = "is_final"
        case speechFinal = "speech_final"
    }

    struct Channel: Decodable {
        let alternatives: [Alternative]
    }

    struct Alternative: Decodable {
        let transcript: String
    }
}
