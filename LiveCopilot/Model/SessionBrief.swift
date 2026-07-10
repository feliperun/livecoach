import Foundation

enum Mode: String, Codable, CaseIterable, Sendable, Identifiable {
    case interview
    case sales
    case difficult
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .interview: return "Entrevista"
        case .sales: return "Vendas"
        case .difficult: return "Conversa difícil"
        case .custom: return "Custom"
        }
    }
}

enum CoachModel: String, Codable, CaseIterable, Sendable, Identifiable {
    case opus
    case sonnet

    var id: String { rawValue }
    var cliAlias: String { rawValue }   // "opus" | "sonnet"
    var label: String {
        switch self {
        case .opus: return "Opus (profundo)"
        case .sonnet: return "Sonnet (rápido)"
        }
    }
}

enum SttSource: String, Codable, CaseIterable, Sendable, Identifiable {
    case native      // SpeechAnalyzer / SpeechTranscriber (on-device)
    case assemblyAI  // reservado (Fase 2)

    var id: String { rawValue }

    var label: String {
        switch self {
        case .native: return "Nativo (on-device)"
        case .assemblyAI: return "AssemblyAI"
        }
    }
}

/// Pauta prévia da sessão, persistida em JSON no app container.
struct SessionBrief: Codable, Sendable, Equatable {
    var mode: Mode
    var conversationLang: String   // ex.: "en-US" — idioma em que a conversa acontece
    var nativeLang: String         // ex.: "pt-BR" — idioma nativo (coach sempre aqui)
    var goal: String
    var details: String
    var keyterms: [String]

    static let `default` = SessionBrief(
        mode: .interview,
        conversationLang: "en-US",
        nativeLang: "pt-BR",
        goal: "Ir bem na entrevista e demonstrar senioridade técnica.",
        details: "Vaga de engenharia. Destacar autonomia ponta a ponta. Evitar falar mal de empregadores.",
        keyterms: ["end-to-end ownership", "technical growth", "scope"]
    )

    /// true quando a conversa acontece em idioma diferente do nativo (mostra tradução).
    var isForeign: Bool {
        Self.baseCode(conversationLang) != Self.baseCode(nativeLang)
    }

    /// "en-US" -> "en", "pt-BR" -> "pt"
    static func baseCode(_ id: String) -> String {
        id.split(separator: "-").first.map(String.init)?.lowercased() ?? id.lowercased()
    }
}

/// Persistência simples do brief em Application Support.
enum BriefStore {
    static func url() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("LiveCopilot", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("brief.json")
    }

    static func load() -> SessionBrief {
        guard
            let data = try? Data(contentsOf: url()),
            let brief = try? JSONDecoder().decode(SessionBrief.self, from: data)
        else { return .default }
        return brief
    }

    static func save(_ brief: SessionBrief) {
        guard let data = try? JSONEncoder().encode(brief) else { return }
        try? data.write(to: url(), options: .atomic)
    }
}
