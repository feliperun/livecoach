import SwiftUI
import AppKit

/// Calm, high-contrast workspace tokens. Static layers keep rendering cheap.
enum Theme {
    static let canvas = adaptive(
        light: NSColor(srgbRed: 0.965, green: 0.958, blue: 0.945, alpha: 1),
        dark: NSColor(srgbRed: 0.035, green: 0.043, blue: 0.062, alpha: 1)
    )
    static let sidebar = adaptive(
        light: NSColor(srgbRed: 0.935, green: 0.925, blue: 0.905, alpha: 1),
        dark: NSColor(srgbRed: 0.046, green: 0.055, blue: 0.078, alpha: 1)
    )
    static let panel = adaptive(
        light: NSColor(srgbRed: 0.992, green: 0.988, blue: 0.978, alpha: 1),
        dark: NSColor(srgbRed: 0.065, green: 0.076, blue: 0.104, alpha: 1)
    )
    static let panelRaised = adaptive(
        light: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
        dark: NSColor(srgbRed: 0.082, green: 0.096, blue: 0.130, alpha: 1)
    )
    static let interactive = adaptive(
        light: NSColor.black.withAlphaComponent(0.045),
        dark: NSColor.white.withAlphaComponent(0.055)
    )
    static let divider = adaptive(
        light: NSColor.black.withAlphaComponent(0.10),
        dark: NSColor.white.withAlphaComponent(0.075)
    )

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
        colors: [sidebar.opacity(0.72), canvas],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
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
