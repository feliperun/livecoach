import Foundation

enum Mode: String, Codable, CaseIterable, Sendable, Identifiable {
    case interview
    case sales
    case difficult
    case meeting
    case recording
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .interview: return "Entrevista"
        case .sales: return "Vendas"
        case .difficult: return "Conversa difícil"
        case .meeting: return "Reunião assistida"
        case .recording: return "Somente gravação"
        case .custom: return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .interview: return "person.crop.rectangle.stack.fill"
        case .sales: return "chart.line.uptrend.xyaxis.circle.fill"
        case .difficult: return "heart.text.square.fill"
        case .meeting: return "person.3.fill"
        case .recording: return "waveform.circle.fill"
        case .custom: return "slider.horizontal.3"
        }
    }

    /// Captura/transcrição pura. Reuniões normais mantêm um coach pouco intrusivo.
    var isPassive: Bool { self == .recording }
}

enum CoachModel: String, Codable, CaseIterable, Sendable, Identifiable {
    case deepseekPro = "deepseek-pro"
    case deepseekFlash = "deepseek-flash"
    case opus
    case sonnet

    var id: String { rawValue }

    /// Modelo passado ao `--model` do CLI. Para DeepSeek é o id do endpoint
    /// Anthropic-compatível; para Claude, o alias de tier.
    var backendModel: String {
        switch self {
        case .deepseekPro: return "deepseek-v4-pro"
        case .deepseekFlash: return "deepseek-v4-flash"
        case .opus: return "opus"
        case .sonnet: return "sonnet"
        }
    }

    /// DeepSeek roda o mesmo CLI apontado para outro endpoint (env override).
    var isDeepSeek: Bool { self == .deepseekPro || self == .deepseekFlash }

    var label: String {
        switch self {
        case .deepseekPro: return "DeepSeek V4 Pro (profundo)"
        case .deepseekFlash: return "DeepSeek V4 Flash (rápido)"
        case .opus: return "Opus (profundo)"
        case .sonnet: return "Sonnet (rápido)"
        }
    }

    static func defaultSummaryModel(for coachModel: CoachModel) -> CoachModel {
        coachModel.isDeepSeek ? .deepseekPro : .opus
    }

    /// Resolve uma preferência persistida sem deixar o app apontando para um
    /// provedor indisponível quando o outro já está pronto.
    static func resolved(
        preferred: CoachModel,
        claudeAvailable: Bool,
        deepSeekAvailable: Bool
    ) -> CoachModel {
        if preferred.isDeepSeek, !deepSeekAvailable, claudeAvailable { return .sonnet }
        if !preferred.isDeepSeek, !claudeAvailable, deepSeekAvailable { return .deepseekPro }
        return preferred
    }
}

enum SttSource: String, Codable, CaseIterable, Sendable, Identifiable {
    case native      // SpeechAnalyzer / SpeechTranscriber (on-device)
    case deepgram    // Nova-3 streaming via WebSocket

    var id: String { rawValue }

    var label: String {
        switch self {
        case .native: return "Nativo (on-device)"
        case .deepgram: return "Deepgram Nova-3"
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
    var cv: String?                // currículo completo (modo entrevista) — opcional
    var contexts: [MeetingContext]? = nil // snapshots dos contextos ativos desta sessão
    /// Snapshot bounded and explicitly enabled for this live session only.
    /// It is derived from user-owned Note files and never becomes canonical data.
    var relevantMemoryContext: String? = nil

    static let `default` = SessionBrief(
        mode: .interview,
        conversationLang: "en-US",
        nativeLang: "pt-BR",
        goal: "Ir bem na entrevista e demonstrar senioridade técnica.",
        details: "Vaga de engenharia. Destacar autonomia ponta a ponta. Evitar falar mal de empregadores.",
        keyterms: ["end-to-end ownership", "technical growth", "scope"],
        cv: nil
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
        let dir = base.appendingPathComponent("CueMe", isDirectory: true)
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
