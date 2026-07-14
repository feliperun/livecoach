import SwiftUI

struct HistoryDiagnosticsSection: View {
    let record: SessionRecord

    private var report: SessionPerformanceReport {
        SessionPerformanceReport(diagnostics: record.diagnostics)
    }

    private var timeline: [DiagnosticEvent] {
        record.diagnostics.events.filter { $0.kind == .recovery || $0.kind == .error }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SAÚDE")
                .font(.system(size: 10, weight: .heavy)).tracking(1).foregroundStyle(Theme.cyan)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 8)], spacing: 8) {
                DiagnosticChip(label: "STT", value: "\(record.diagnostics.count("stt_final"))")
                DiagnosticChip(label: "COBERTURA", value: "\(report.coveragePercent)%")
                DiagnosticChip(label: "P50", value: report.firstPhraseP50Ms.map { "\($0)ms" } ?? "—")
                DiagnosticChip(label: "P95", value: report.firstPhraseP95Ms.map { "\($0)ms" } ?? "—")
                DiagnosticChip(label: "RECUP.", value: "\(report.recoveries)")
                DiagnosticChip(label: "ERROS", value: "\(report.errors)")
                DiagnosticChip(label: "👍", value: "\(record.coachFeedback.values.filter { $0 == .helpful }.count)")
                DiagnosticChip(label: "👎", value: "\(record.coachFeedback.values.filter { $0 == .notHelpful }.count)")
            }
            if !timeline.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(timeline.prefix(12)) { event in
                        HStack(spacing: 7) {
                            Circle().fill(event.kind == .error ? Theme.rose : Theme.amber).frame(width: 6, height: 6)
                            Text(event.at.formatted(date: .omitted, time: .standard))
                                .font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                            Text(eventLabel(event.name))
                                .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func eventLabel(_ name: String) -> String {
        switch name {
        case "provider_failover": return "Provider alternado"
        case "stt_restarted": return "STT reiniciado"
        case "mic_watchdog_restart": return "Microfone recuperado"
        case "system_watchdog_restart": return "Áudio da chamada recuperado"
        case "recording_stalled": return "Gravação sem avanço"
        default: return name.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

private struct DiagnosticChip: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 8, weight: .heavy)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, weight: .bold, design: .monospaced))
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }
}
