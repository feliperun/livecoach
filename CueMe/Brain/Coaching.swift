import Foundation

/// Raia de coaching: Sonnet (ou Opus para input manual "deep"), streaming e cancelável.
/// Emite `CoachCard` progressivamente conforme o modelo gera.
final class CoachingLane: Sendable {
    private let live: (any CoachSession)?     // modelo escolhido — turno ao vivo
    private let manualS: (any CoachSession)?  // input manual (tier escolhido/profundo)

    init(live: (any CoachSession)?, manual: (any CoachSession)?) {
        self.live = live
        self.manualS = manual
    }

    /// Stream de cards parciais (deltas do CLI). O card final tem `isStreaming = false`.
    /// Stream vazio se não há sessão — o coordinator trata.
    func coach(
        window: [Turn],
        latest: String,
        manual: Bool,
        speakerCertain: Bool = true,
        cardID: UUID = UUID(),
        initialGuide: String? = nil
    ) -> AsyncThrowingStream<CoachCard, Error> {
        AsyncThrowingStream { continuation in
            guard let session = manual ? (manualS ?? live) : live else {
                continuation.finish()
                return
            }
            let user = Prompts.coachUser(window: window, latest: latest, manual: manual, speakerCertain: speakerCertain)

            // O coordinator pode ter mostrado uma dica local antes da chamada. Reusa
            // o mesmo id para a resposta remota substituir o frame, sem criar outro card.
            continuation.yield(CoachCard(
                id: cardID,
                guidePT: initialGuide ?? "",
                kind: manual ? .manual : .answer,
                isStreaming: true
            ))

            let task = Task {
                var accumulated = ""
                do {
                    let deltas = await session.send(user)
                    for try await delta in deltas {
                        if Task.isCancelled { break }
                        accumulated += delta
                        if let card = CoachCardParser.parse(accumulated, id: cardID, manual: manual, streaming: true) {
                            continuation.yield(card)
                        }
                    }
                    if let final = CoachCardParser.parse(accumulated, id: cardID, manual: manual, streaming: false) {
                        continuation.yield(final)
                    } else {
                        // `NADA`/resposta inválida precisa substituir a dica local por
                        // um card vazio; o coordinator então a remove em vez de deixá-la stale.
                        continuation.yield(CoachCard(
                            id: cardID,
                            kind: manual ? .manual : .answer,
                            isStreaming: false
                        ))
                    }
                    continuation.finish()
                } catch {
                    continuation.yield(CoachCard(
                        id: cardID,
                        kind: manual ? .manual : .answer,
                        isStreaming: false
                    ))
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Primeira ajuda, calculada localmente e sem rede. Não tenta responder; só oferece
/// um playbook visual enquanto a frase pronta chega por streaming.
@MainActor
enum InstantCue {
    static func label(for text: String, mode: Mode) -> String? {
        let lower = text.lowercased()
        guard SessionCoordinator.looksLikeQuestion(text) else { return nil }

        if lower.hasPrefix("tell me") || lower.hasPrefix("describe")
            || lower.contains("a time when") || lower.contains("uma vez que") {
            return "⭐ STAR"
        }
        if lower.hasPrefix("how") || lower.hasPrefix("como")
            || lower.contains("walk me through") {
            return "🧭 3 passos"
        }
        if lower.hasPrefix("why") || lower.hasPrefix("por que") {
            return "🎯 Motivo → encaixe"
        }
        if lower.contains("impact") || lower.contains("result")
            || lower.contains("metric") || lower.contains("resultado") {
            return "📈 Resultado + número"
        }
        if mode == .sales, lower.contains("price") || lower.contains("preço") {
            return "💎 Valor antes do preço"
        }
        return "💡 Manchete primeiro"
    }
}

/// Parser do formato de saída do coach (GUIA/DIGA_CONV/DIGA_NATIVE/KEYTERMS/MODO).
enum CoachCardParser {
    static func parse(_ text: String, id: UUID, manual: Bool, streaming: Bool) -> CoachCard? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.uppercased().hasPrefix("NADA") { return nil }

        var keyterms: [String] = []
        let kind: CoachKind = manual ? .manual : .answer

        // Acumula por rótulo até o próximo rótulo (campos podem ter múltiplas linhas).
        let labels = ["GUIA:", "DIGA:", "PT:", "KEY:"]
        var current: String?
        var buffers: [String: String] = [:]

        for rawLine in trimmed.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if let label = labels.first(where: { line.uppercased().hasPrefix($0) }) {
                current = label
                let value = String(line.dropFirst(label.count)).trimmingCharacters(in: .whitespaces)
                buffers[label, default: ""] = value
            } else if let current {
                buffers[current, default: ""] += "\n" + line
            }
        }

        func value(_ label: String) -> String {
            buffers[label]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        let guide = value("GUIA:")
        let conv = value("DIGA:")
        let sayConv: String? = (conv == "-" || conv.isEmpty) ? nil : conv
        let sayNative = value("PT:")

        let ktRaw = value("KEY:")
        if ktRaw != "-" && !ktRaw.isEmpty {
            keyterms = ktRaw
                .split(whereSeparator: { $0 == "·" || $0 == "," || $0 == "|" || $0 == "\n" })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }

        // Nunca materializa prosa fora do contrato ou uma resposta vazia como card.
        // Isso evita placeholders "finalizados" sem nenhuma dica visível.
        if guide.isEmpty && sayConv == nil && sayNative.isEmpty { return nil }

        return CoachCard(
            id: id,
            guidePT: guide,
            sayConversation: sayConv,
            sayNative: sayNative,
            keytermsConversation: keyterms,
            kind: kind,
            severity: kind == .correction ? .warn : .info,
            isStreaming: streaming
        )
    }
}
