import SwiftUI

/// Identidade visual do CueMe — dark "command center".
/// Fundo profundo, acento violeta→ciano, verde-menta pro coach, glow sutil.
enum Theme {
    // Fundo em camadas (gradiente profundo, quase-preto azulado).
    static let bgTop = Color(red: 0.055, green: 0.065, blue: 0.10)
    static let bgBottom = Color(red: 0.035, green: 0.04, blue: 0.06)

    // Superfícies (cards/painéis).
    static let surface = Color.white.opacity(0.045)
    static let surfaceStroke = Color.white.opacity(0.08)

    // Acentos.
    static let violet = Color(red: 0.55, green: 0.42, blue: 1.0)
    static let cyan = Color(red: 0.30, green: 0.82, blue: 1.0)
    static let mint = Color(red: 0.30, green: 0.95, blue: 0.65)
    static let amber = Color(red: 1.0, green: 0.72, blue: 0.30)
    static let rose = Color(red: 1.0, green: 0.40, blue: 0.50)

    /// Gradiente de marca (violeta → ciano).
    static let brand = LinearGradient(
        colors: [violet, cyan],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Gradiente do coach (menta → ciano).
    static let coach = LinearGradient(
        colors: [mint, cyan],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let background = LinearGradient(
        colors: [bgTop, bgBottom],
        startPoint: .top, endPoint: .bottom
    )
}

// MARK: - Componentes reutilizáveis

/// Painel "vidro": superfície sutil + borda de 1px.
struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Theme.surfaceStroke, lineWidth: 1)
            )
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
    @State private var pulse = false

    var body: some View {
        ZStack {
            if active {
                Circle()
                    .fill(color.opacity(0.35))
                    .frame(width: 16, height: 16)
                    .scaleEffect(pulse ? 1.6 : 0.8)
                    .opacity(pulse ? 0 : 0.9)
                    .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: pulse)
            }
            Circle()
                .fill(active ? color : Color.secondary.opacity(0.5))
                .frame(width: 8, height: 8)
                .shadow(color: active ? color.opacity(0.8) : .clear, radius: 4)
        }
        .frame(width: 16, height: 16)
        .onAppear { pulse = active }
        .onChange(of: active) { _, on in pulse = on }
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
            .background(
                Circle().fill(isOn ? Theme.cyan.opacity(0.15) : Color.white.opacity(configuration.isPressed ? 0.10 : 0.05))
            )
            .overlay(Circle().strokeBorder(isOn ? Theme.cyan.opacity(0.4) : Theme.surfaceStroke, lineWidth: 1))
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
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
            .shadow(color: danger ? .clear : Theme.violet.opacity(0.4), radius: configuration.isPressed ? 2 : 8, y: 2)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}
