import Foundation
import OSLog

/// Sessão de coach falando DIRETO com a API DeepSeek (endpoint OpenAI-compatível,
/// streaming SSE). Otimizada para latência ao vivo:
///
/// - **Stateless por turno**: o prompt do coach já carrega a janela de contexto,
///   então cada requisição é independente (system + user). Menos tokens, sem
///   serialização, sem cold start de processo. O cache de contexto da DeepSeek
///   barateia o system prompt repetido do lado deles.
/// - **`URLSession` persistente**: reusa conexão TLS/HTTP2 entre turnos.
/// - **`thinking: disabled`**: modo não-pensante — sem tokens de raciocínio antes
///   da resposta, corta a latência do 1º token.
actor DeepSeekSession: CoachSession {
    private let log = Logger(subsystem: "CueMe", category: "DeepSeekSession")

    private let model: String
    private let system: String
    private let apiKey: String
    private let endpoint: URL
    private let urlSession: URLSession

    init(model: String, system: String, apiKey: String, baseURL: URL) {
        self.model = model
        self.system = system
        self.apiKey = apiKey
        self.endpoint = baseURL.appendingPathComponent("chat/completions")

        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 60
        cfg.waitsForConnectivity = false
        cfg.httpMaximumConnectionsPerHost = 2
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.urlSession = URLSession(configuration: cfg)
    }

    // MARK: - Envio de um turno (streaming de deltas de texto)

    nonisolated func send(_ user: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { await self.run(user: user, continuation: continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Aquece a conexão (TLS/HTTP2) com um turno trivial descartado.
    nonisolated func prewarm() {
        Task { [weak self] in
            _ = try? await self?.complete("(aquecimento — responda apenas: NADA)")
        }
    }

    func complete(_ user: String) async throws -> String {
        var acc = ""
        for try await delta in send(user) { acc += delta }
        return acc.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func shutdown() {
        urlSession.invalidateAndCancel()
    }

    // MARK: - Requisição + parse do SSE

    private func run(user: String, continuation: AsyncThrowingStream<String, Error>.Continuation) async {
        let body: [String: Any] = [
            "model": model,
            "stream": true,
            "thinking": ["type": "disabled"],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            continuation.finish(throwing: DeepSeekError.encodeFailed)
            return
        }
        request.httpBody = data

        do {
            let (bytes, response) = try await urlSession.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                continuation.finish(throwing: DeepSeekError.badResponse)
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                let detail = try? await Self.drain(bytes)
                continuation.finish(throwing: DeepSeekError.http(http.statusCode, detail))
                return
            }

            for try await line in bytes.lines {
                if Task.isCancelled { break }
                guard line.hasPrefix("data:") else { continue }
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if payload.isEmpty { continue }
                if payload == "[DONE]" { break }
                if let text = Self.deltaContent(payload), !text.isEmpty {
                    continuation.yield(text)
                }
            }
            continuation.finish()
        } catch {
            if Task.isCancelled {
                continuation.finish()
            } else {
                continuation.finish(throwing: error)
            }
        }
    }

    /// Extrai `choices[0].delta.content` de um chunk SSE. Ignora `reasoning_content`
    /// (não deve aparecer com thinking desligado, mas fica robusto).
    private static func deltaContent(_ json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any],
              let content = delta["content"] as? String
        else { return nil }
        return content
    }

    /// Lê o corpo de erro (curto) para uma mensagem melhor, sem vazar internals.
    private static func drain(_ bytes: URLSession.AsyncBytes) async throws -> String {
        var acc = ""
        for try await line in bytes.lines {
            acc += line
            if acc.count > 500 { break }
        }
        return acc
    }

    enum DeepSeekError: LocalizedError {
        case encodeFailed
        case badResponse
        case http(Int, String?)

        var errorDescription: String? {
            switch self {
            case .encodeFailed: return "Falha ao serializar a requisição para a DeepSeek."
            case .badResponse: return "Resposta inválida da API DeepSeek."
            case .http(let code, _): return "API DeepSeek retornou \(code)."
            }
        }
    }
}
