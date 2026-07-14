import SwiftUI

struct PreflightView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                ForEach(PreflightCheck.allCases) { check in
                    CheckBadge(label: check.label, status: app.preflight[check] ?? .idle)
                }
            }
            Button(app.preflightRunning ? "Testando…" : "Testar 10s") { app.runPreflight() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(app.preflightRunning)
            if !app.preflightRunning, app.preflight.values.contains(.failed) {
                HStack(spacing: 12) {
                    Button("Permissões") { app.openScreenRecordingSettings() }
                    Button("Fechar") { dismiss() }
                }
                .font(.system(size: 11, weight: .semibold))
            }
        }
        .padding(24)
        .frame(width: 360, height: 170)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .onAppear { if app.preflight.values.allSatisfy({ $0 == .idle }) { app.runPreflight() } }
    }
}

private struct CheckBadge: View {
    let label: String
    let status: PreflightStatus
    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(color)
            Text(label).font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(1)
        }
        .frame(width: 74, height: 62)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
    private var icon: String {
        switch status {
        case .idle: return "circle"
        case .checking: return "ellipsis"
        case .passed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        }
    }
    private var color: Color {
        switch status {
        case .passed: return Theme.mint
        case .failed: return Theme.rose
        default: return .secondary
        }
    }
}
