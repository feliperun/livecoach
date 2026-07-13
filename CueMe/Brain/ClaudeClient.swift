import Foundation

/// Fábrica/localizador do backend via **Claude Code CLI** (`claude`), sem API key.
/// Não faz chamadas: cria `ClaudeSession` persistentes (processos warm) e resolve
/// o binário. Usa o login/assinatura já configurados no `claude` do usuário.
final class ClaudeClient: Sendable {
    // Aliases aceitos pelo `--model` do CLI (resolve pro mais recente de cada tier).
    static let fastModel = "haiku"
    static let liveModel = "sonnet"

    private let cliPath: String?

    init() {
        self.cliPath = Self.resolveCLI()
    }

    /// CLI encontrado no sistema?
    var isAvailable: Bool { cliPath != nil }

    /// Cria uma sessão persistente do Claude CLI (system prompt + modelo fixos).
    func makeSession(model: String, system: String) -> ClaudeSession? {
        guard let cliPath else { return nil }
        return ClaudeSession(cliPath: cliPath, model: model, system: system)
    }

    /// Cria a sessão do coach para o modelo escolhido. DeepSeek fala HTTP direto
    /// (precisa de API key configurada); os demais tiers usam o Claude CLI.
    func makeCoachSession(model: CoachModel, system: String) -> (any CoachSession)? {
        if model.isDeepSeek {
            guard let key = DeepSeekCredential.apiKey, !key.isEmpty,
                  let base = URL(string: DeepSeekCredential.baseURL)
            else { return nil }
            return DeepSeekSession(model: model.backendModel, system: system, apiKey: key, baseURL: base)
        }
        return makeSession(model: model.backendModel, system: system)
    }

    /// Localiza o binário `claude`. Tenta caminhos comuns e, por fim, o login shell.
    private static func resolveCLI() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.bun/bin/claude",
            "\(home)/.npm-global/bin/claude",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        if let path = try? runSyncCapture("/bin/zsh", ["-lc", "command -v claude"]),
           !path.isEmpty,
           FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    private static func runSyncCapture(_ launch: String, _ args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launch)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
