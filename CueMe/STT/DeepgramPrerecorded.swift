import Foundation

enum DeepgramPrerecordedRequest {
    static func url(config: SttConfig) -> URL? {
        var components = URLComponents(string: "https://api.deepgram.com/v1/listen")
        var items = [
            URLQueryItem(name: "model", value: "nova-3"),
            URLQueryItem(name: "language", value: config.localeIdentifier),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "punctuate", value: "true"),
            URLQueryItem(name: "utterances", value: "true"),
            URLQueryItem(name: "diarize_model", value: "latest"),
            URLQueryItem(name: "mip_opt_out", value: "true")
        ]
        items += GlossaryTermPolicy.sanitized(config.keyterms).map {
            URLQueryItem(name: "keyterm", value: $0)
        }
        items += sanitizedReplacements(config.replacements).map {
            URLQueryItem(name: "replace", value: "\($0.key):\($0.value)")
        }
        components?.queryItems = items
        return components?.url
    }

    private static func sanitizedReplacements(_ values: [String: String]) -> [(key: String, value: String)] {
        values.compactMap { rawKey, rawValue in
            let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty, !key.contains(":"), !value.contains(":") else { return nil }
            return (String(key.prefix(120)), String(value.prefix(120)))
        }
        .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
        .prefix(200)
        .map { $0 }
    }
}

enum DeepgramPrerecordedResponseParser {
    static func parse(_ data: Data, startedAt: Date) throws -> [TranscriptLine] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        return (response.results.utterances ?? []).compactMap { utterance in
            let text = utterance.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return TranscriptLine(
                speaker: utterance.speaker.isMultiple(of: 2) ? .other : .self,
                text: text,
                isFinal: true,
                ts: startedAt.addingTimeInterval(max(0, utterance.start))
            )
        }
    }

    private struct Response: Decodable {
        let results: Results
    }

    private struct Results: Decodable {
        let utterances: [Utterance]?
    }

    private struct Utterance: Decodable {
        let start: TimeInterval
        let transcript: String
        let speaker: Int
    }
}
