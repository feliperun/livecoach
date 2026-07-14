import Foundation
import OSLog

/// Sessão persistente do Claude Code CLI: um processo `claude -p` mantido VIVO
/// em modo streaming-json bidirecional. Paga cold start uma vez; cada turno
/// seguinte é só inferência (~1–2s). System prompt e modelo são fixos por sessão.
///
/// A conversa é única (o histórico acumula) → turnos são SERIALIZADOS. Para
/// coach/resumo isso é natural; para tradução, uma sessão serial dá conta
/// (utterances chegam espaçadas), e o prompt cache barateia o histórico.
actor ClaudeSession {
    private let log = Logger(subsystem: "CueMe", category: "ClaudeSession")

    private let cliPath: String
    private let model: String
    private let system: String
    private let shell = "/bin/zsh"

    private var process: Process?
    private var stdin: FileHandle?
    private var readerTask: Task<Void, Never>?
    private var stderrTask: Task<Void, Never>?
    private var turnTimeoutTask: Task<Void, Never>?
    private var shuttingDown = false

    // Turno em andamento (só um por vez).
    private final class Turn: @unchecked Sendable {
        let continuation: AsyncThrowingStream<String, Error>.Continuation
        var cancelled = false   // set por onTermination (fora do actor); race benigna
        var buffer = ""
        init(_ c: AsyncThrowingStream<String, Error>.Continuation) { continuation = c }
    }
    private var current: Turn?

    // Serialização de turnos (conversa única) — interno ao actor, sem await cruzado.
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(cliPath: String, model: String, system: String) {
        self.cliPath = cliPath
        self.model = model
        self.system = system
    }

    // MARK: - Spawn

    private func startIfNeeded() throws {
        guard !shuttingDown else { throw ClaudeSessionError.notRunning }
        if let p = process, p.isRunning { return }

        let script = #"exec "$LC_CLAUDE" -p --model "$LC_MODEL" --system-prompt "$LC_SYS" --input-format stream-json --output-format stream-json --include-partial-messages --verbose --tools "" --strict-mcp-config --mcp-config '{"mcpServers":{}}' --disable-slash-commands --no-chrome --no-session-persistence --setting-sources project,local --settings "$LC_SETTINGS""#

        var env = ProcessInfo.processInfo.environment
        env["LC_CLAUDE"] = cliPath
        env["LC_MODEL"] = model
        env["LC_SYS"] = system
        env["LC_SETTINGS"] = #"{"disableAllHooks":true}"#

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: shell)
        proc.arguments = ["-lc", script]
        proc.environment = env
        // cwd isolado + zero tools/MCP/plugins/user settings: evita carregar contexto
        // pessoal e reduz drasticamente tokens/latência do processo de texto puro.
        let isolated = FileManager.default.temporaryDirectory.appendingPathComponent("CueMeCLI", isDirectory: true)
        try? FileManager.default.createDirectory(at: isolated, withIntermediateDirectories: true)
        proc.currentDirectoryURL = isolated

        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        try proc.run()

        self.process = proc
        self.stdin = inPipe.fileHandleForWriting
        let outHandle = outPipe.fileHandleForReading
        let errHandle = errPipe.fileHandleForReading

        readerTask = Task { [weak self] in
            do {
                for try await line in outHandle.bytes.lines {
                    await self?.handle(line: line)
                }
            } catch {
                // pipe fechado / processo morreu
            }
            await self?.readerEnded()
        }
        // `claude --verbose` pode escrever bastante em stderr. Um Pipe sem leitor
        // enche e bloqueia o processo filho; drenamos continuamente por segurança.
        stderrTask = Task {
            do {
                for try await _ in errHandle.bytes.lines { }
            } catch { }
        }
        log.info("ClaudeSession spawn (\(self.model, privacy: .public))")
    }

    // MARK: - Envio de um turno (streaming de deltas de texto)

    func send(_ user: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task { await self.enqueue(user: user, continuation: continuation) }
        }
    }

    /// Aquece o processo (paga o cold start ANTES da conversa). Manda um turno
    /// trivial e descarta a resposta. Sistema prompt + CV já carregam no spawn.
    func prewarm() async throws {
        _ = try await complete("(aquecimento — se não houver nada a fazer responda apenas: NADA)")
    }

    /// Conveniência: coleta o stream inteiro num texto só (tradução/resumo).
    func complete(_ user: String) async throws -> String {
        var acc = ""
        for try await delta in send(user) { acc += delta }
        return acc.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func acquire() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()   // segue ocupado; o próximo turno assume
        } else {
            busy = false
        }
    }

    private func enqueue(user: String, continuation: AsyncThrowingStream<String, Error>.Continuation) async {
        await acquire()
        do {
            try startIfNeeded()
        } catch {
            release()
            continuation.finish(throwing: error)
            return
        }
        guard let stdin else {
            release()
            continuation.finish(throwing: ClaudeSessionError.notRunning)
            return
        }

        let turn = Turn(continuation)
        current = turn
        turnTimeoutTask?.cancel()
        turnTimeoutTask = Task { [weak self, weak turn] in
            do { try await Task.sleep(for: .seconds(60)) }
            catch { return }
            guard let turn else { return }
            await self?.timeout(turn)
        }
        continuation.onTermination = { [weak self, weak turn] _ in
            turn?.cancelled = true
            _ = self   // o gate é liberado quando chega o `result`
        }

        // Mensagem de usuário no formato stream-json de entrada.
        let payload: [String: Any] = [
            "type": "user",
            "message": ["role": "user", "content": user],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            finishCurrent(throwing: ClaudeSessionError.encodeFailed)
            return
        }
        var line = data
        line.append(0x0A) // \n
        stdin.write(line)
    }

    // MARK: - Parser dos eventos JSONL

    private func handle(line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String
        else { return }

        switch type {
        case "stream_event":
            guard let event = obj["event"] as? [String: Any],
                  (event["type"] as? String) == "content_block_delta",
                  let delta = event["delta"] as? [String: Any],
                  (delta["type"] as? String) == "text_delta",
                  let text = delta["text"] as? String
            else { return }
            // Ignora thinking_delta (index 0); só texto conta.
            if let turn = current, !turn.cancelled {
                turn.buffer += text
                turn.continuation.yield(text)
            }

        case "result":
            let isError = (obj["is_error"] as? Bool) ?? false
            if isError {
                let msg = (obj["result"] as? String) ?? "erro no CLI"
                finishCurrent(throwing: ClaudeSessionError.turnFailed(msg))
            } else {
                finishCurrent(throwing: nil)
            }

        default:
            break
        }
    }

    private func finishCurrent(throwing error: Error?) {
        guard let turn = current else { return }
        turnTimeoutTask?.cancel()
        turnTimeoutTask = nil
        current = nil
        if let error {
            turn.continuation.finish(throwing: error)
        } else {
            turn.continuation.finish()
        }
        release()
    }

    private func timeout(_ turn: Turn) {
        guard current === turn else { return }
        try? stdin?.close()
        stdin = nil
        if let process, process.isRunning { process.terminate() }
        process = nil
        finishCurrent(throwing: ClaudeSessionError.timedOut)
    }

    private func readerEnded() {
        // Processo morreu no meio de um turno → erro; libera o gate.
        if current != nil {
            finishCurrent(throwing: ClaudeSessionError.notRunning)
        }
        process = nil
        stdin = nil
    }

    // MARK: - Shutdown

    func shutdown() {
        shuttingDown = true
        readerTask?.cancel()
        readerTask = nil
        stderrTask?.cancel()
        stderrTask = nil
        turnTimeoutTask?.cancel()
        turnTimeoutTask = nil
        try? stdin?.close()
        stdin = nil
        if let p = process, p.isRunning { p.terminate() }
        process = nil
        if let turn = current {
            current = nil
            turn.continuation.finish(throwing: ClaudeSessionError.notRunning)
        }
        let queued = waiters
        waiters.removeAll()
        busy = false
        for waiter in queued { waiter.resume() }
    }

    enum ClaudeSessionError: LocalizedError {
        case notRunning
        case encodeFailed
        case timedOut
        case turnFailed(String)

        var errorDescription: String? {
            switch self {
            case .notRunning: return "Sessão do Claude CLI não está ativa."
            case .encodeFailed: return "Falha ao serializar a mensagem para o CLI."
            case .timedOut: return "O Claude CLI não respondeu em 60 segundos."
            case .turnFailed(let m): return "Turno do Claude CLI falhou: \(m)"
            }
        }
    }
}
