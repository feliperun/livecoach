import SwiftUI

/// Calm, high-contrast workspace tokens. Static layers keep rendering cheap.
enum Theme {
    static let canvas = Color(red: 0.035, green: 0.043, blue: 0.062)
    static let sidebar = Color(red: 0.046, green: 0.055, blue: 0.078)
    static let panel = Color(red: 0.065, green: 0.076, blue: 0.104)
    static let panelRaised = Color(red: 0.082, green: 0.096, blue: 0.130)
    static let interactive = Color.white.opacity(0.055)
    static let divider = Color.white.opacity(0.075)

    static let violet = Color(red: 0.48, green: 0.55, blue: 1.0)
    static let cyan = Color(red: 0.32, green: 0.72, blue: 0.98)
    static let mint = Color(red: 0.32, green: 0.84, blue: 0.66)
    static let amber = Color(red: 0.94, green: 0.69, blue: 0.35)
    static let rose = Color(red: 0.96, green: 0.39, blue: 0.48)

    static let surface = panel
    static let surfaceStroke = divider

    /// Gradiente de marca (violeta → ciano).
    static let brand = LinearGradient(
        colors: [violet, Color(red: 0.43, green: 0.76, blue: 1.0)],
        startPoint: .leading, endPoint: .trailing
    )

    /// Gradiente do coach (menta → ciano).
    static let coach = LinearGradient(
        colors: [mint, cyan],
        startPoint: .leading, endPoint: .trailing
    )

    static let background = LinearGradient(
        colors: [Color(red: 0.045, green: 0.054, blue: 0.078), canvas],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

// MARK: - Componentes reutilizáveis

/// Opaque panel with a subtle border; avoids runtime blur/material costs.
struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Theme.surfaceStroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 8, y: 3)
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 14) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius))
    }
}

/// Dot de status com pulso quando ativo.
struct PulseDot: View {
    let active: Bool
    var health: RuntimeHealthLevel = .healthy

    var body: some View {
        Image(systemName: "circle.fill")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(active ? color : Color.secondary.opacity(0.5))
            .symbolEffect(.pulse, options: .repeating, isActive: active)
            .shadow(color: active ? color.opacity(0.6) : .clear, radius: 3)
        .frame(width: 16, height: 16)
    }

    private var color: Color {
        switch health {
        case .healthy: return Theme.mint
        case .degraded: return Theme.amber
        case .critical: return Theme.rose
        }
    }
}

/// Botão-ícone minimalista (header).
struct IconButtonStyle: ButtonStyle {
    var isOn: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isOn ? Theme.cyan : .secondary)
            .frame(width: 28, height: 28)
            .background(Circle().fill(isOn ? Theme.violet.opacity(0.18) : Theme.interactive))
            .overlay(Circle().strokeBorder(isOn ? Theme.violet.opacity(0.45) : Theme.divider, lineWidth: 1))
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}

/// Botão principal (Iniciar/Parar) com gradiente.
struct PrimaryButtonStyle: ButtonStyle {
    var danger: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(danger ? Theme.rose : Color.black.opacity(0.85))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background {
                if danger {
                    Capsule().fill(Theme.rose.opacity(0.16))
                } else {
                    Capsule().fill(Theme.brand)
                }
            }
            .overlay(Capsule().strokeBorder(danger ? Theme.rose.opacity(0.5) : .clear, lineWidth: 1))
            .shadow(color: danger ? .clear : Theme.violet.opacity(0.22), radius: configuration.isPressed ? 1 : 5, y: 2)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}
