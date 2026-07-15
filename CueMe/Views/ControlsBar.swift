import SwiftUI

/// Header fino: status, captura do interlocutor, pin, silêncio, ajustes, iniciar/parar.
struct HeaderBar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @State private var showParticipants = false
    @State private var selfName = ""
    @State private var otherName = ""

    var body: some View {
        @Bindable var app = app

        HStack(spacing: 8) {
            if app.selectedSession != nil, !app.isSessionBusy {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.violet)
                Text("Biblioteca")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            } else {
                PulseDot(active: app.isRunning, health: app.runtimeHealth.level)
                Text(app.statusText)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(app.isRunning ? .primary : .secondary)
                    .lineLimit(1)
            }

            if app.isRunning || app.sessionState == .preparing {
                ChannelHealthButton(
                    icon: "mic.fill",
                    state: app.micCaptureState,
                    level: app.micLevel,
                    repair: app.repairMicrophone
                )
                ChannelHealthButton(
                    icon: "headphones",
                    state: app.systemCaptureState,
                    level: app.systemLevel,
                    repair: app.repairSystemCapture
                )
                if app.recordAudio {
                    RecDot()
                }
            }

            Spacer()

            if app.isRunning {
                Button {
                    selfName = app.participantNames[.self] ?? "Você"
                    otherName = app.participantNames[.other] ?? "Interlocutor"
                    showParticipants.toggle()
                } label: {
                    Image(systemName: "person.2")
                }
                .buttonStyle(IconButtonStyle())
                .help("Nomear participantes")
                .popover(isPresented: $showParticipants) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Participantes", systemImage: "person.2.fill")
                            .font(.system(size: 12, weight: .bold))
                        TextField("Você", text: $selfName)
                        TextField("Interlocutor", text: $otherName)
                        Button("Salvar") {
                            app.setParticipantName(selfName, for: .self)
                            app.setParticipantName(otherName, for: .other)
                            showParticipants = false
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .textFieldStyle(.roundedBorder)
                    .padding(14)
                    .frame(width: 240)
                }

                Toggle(isOn: Binding(get: { app.silenceMode }, set: { _ in app.toggleSilence() })) {
                    Image(systemName: app.silenceMode ? "moon.fill" : "moon")
                }
                .toggleStyle(.button)
                .buttonStyle(IconButtonStyle(isOn: app.silenceMode))
                .help("Pausar dicas")
            }

            Menu {
                Toggle("Sempre no topo", isOn: $app.pinned)
                Toggle("Modo treino", isOn: $app.trainingMode)
                    .disabled(app.isSessionBusy || app.brief.mode.isPassive)
                Divider()
                if !app.profiles.isEmpty {
                    Menu("Perfis") {
                        ForEach(app.profiles) { profile in
                            Button(profile.name) { app.applyProfile(profile.id) }
                        }
                    }
                    .disabled(app.isSessionBusy)
                }
                Button("Camera Rail") { openWindow(id: "camera-rail") }
                Button("Testar setup") { app.showPreflight = true }
                    .disabled(app.isSessionBusy)
                Button("Buscar atualizações…") { app.checkForUpdates() }
                Button("Histórico") { app.sidebarCollapsed = false }
                Button("Configurar sessão") { app.showSettings = true }
                    .disabled(app.isSessionBusy)
            } label: {
                Image(systemName: "ellipsis")
            }
            .buttonStyle(IconButtonStyle())
            .help("Mais")

            if app.isRunning || !app.transcript.isEmpty || !app.coachCards.isEmpty {
                Button {
                    app.newSession()
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(IconButtonStyle())
                .help("Nova sessão: encerra a atual (salva no histórico) e começa uma limpa")
                .keyboardShortcut("n", modifiers: [.command])
                .disabled(app.sessionState == .preparing || app.sessionState == .stopping)
            }

            Button(primaryTitle) {
                app.isRunning ? app.stop() : app.start()
            }
            .buttonStyle(PrimaryButtonStyle(danger: app.isRunning))
            .accessibilityIdentifier("session.primary")
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(app.sessionState == .preparing || app.sessionState == .stopping)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.canvas.opacity(0.94))
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }

    private var primaryTitle: String {
        if app.sessionState == .stopping { return "Salvando" }
        if app.isRunning { return "Parar" }
        return app.selectedSession == nil ? "Iniciar" : "Gravar"
    }
}

/// Só aparece quando há degradação. Poucas palavras + ação direta.
struct CaptureHealthAlert: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if app.isRunning, let issue {
            Button(action: issue.repair) {
                HStack(spacing: 7) {
                    Image(systemName: issue.icon)
                    Text(issue.label)
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    Spacer()
                    Image(systemName: "arrow.clockwise")
                }
                .foregroundStyle(issue.color)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(issue.color.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }
    }

    private var issue: (label: String, icon: String, color: Color, repair: () -> Void)? {
        if app.runtimeHealth.level == .critical,
           let reason = app.runtimeHealth.reason,
           app.micCaptureState != .silent,
           app.micCaptureState != .unavailable,
           app.systemCaptureState != .unavailable {
            return (reason.uppercased(), "exclamationmark.triangle.fill", Theme.rose, {})
        }
        switch app.micCaptureState {
        case .silent: return ("MIC SEM SINAL", "mic.slash.fill", Theme.rose, app.repairMicrophone)
        case .unavailable: return ("MIC DESCONECTADO", "mic.slash.fill", Theme.rose, app.repairMicrophone)
        case .recovering: return ("RECUPERANDO MIC", "arrow.clockwise", Theme.amber, {})
        default: break
        }
        switch app.systemCaptureState {
        case .unavailable: return ("ÁUDIO EXTERNO OFF", "headphones", Theme.amber, app.repairSystemCapture)
        case .recovering: return ("RECONECTANDO ÁUDIO", "arrow.clockwise", Theme.amber, {})
        default: return nil
        }
    }
}

private struct ChannelHealthButton: View {
    let icon: String
    let state: CaptureChannelState
    let level: Float
    let repair: () -> Void

    var body: some View {
        Button(action: { if state == .silent || state == .unavailable { repair() } }) {
            HStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 9, weight: .bold))
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(color.opacity(level > Float(index) / 3 ? 1 : 0.2))
                        .frame(width: 2.5, height: CGFloat(4 + index * 2))
                }
            }
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .frame(height: 24)
            .background(color.opacity(0.11), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var color: Color {
        switch state {
        case .active: return Theme.mint
        case .waiting, .recovering: return Theme.amber
        case .silent, .unavailable: return Theme.rose
        }
    }

    private var help: String {
        switch state {
        case .active: return "Canal ativo"
        case .waiting: return "Aguardando sinal"
        case .recovering: return "Reconectando"
        case .silent: return "Sem sinal — clique para reparar"
        case .unavailable: return "Indisponível — clique para reparar"
        }
    }
}

/// Campo de pergunta manual, colado na base.
struct InputBar: View {
    @Environment(AppModel.self) private var app
    @FocusState private var focused: Bool
    @State private var expanded = false

    var body: some View {
        @Bindable var app = app

        Group {
            if expanded {
                HStack(spacing: 8) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.cyan.opacity(0.8))
                    TextField("Pergunte ao coach", text: $app.manualInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($focused)
                        .onSubmit { app.ask(); expanded = false }
                    Button {
                        app.ask()
                        expanded = false
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.85))
                            .frame(width: 22, height: 22)
                            .background(Theme.brand, in: Circle())
                            .opacity(sendDisabled ? 0.3 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(sendDisabled)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.05), in: Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        focused ? Theme.cyan.opacity(0.5) : Theme.surfaceStroke,
                        lineWidth: 1
                    )
                )
            } else {
                Button {
                    expanded = true
                    focused = true
                } label: {
                    Label("Perguntar", systemImage: "sparkle")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.04), in: Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("k", modifiers: [.command])
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private var sendDisabled: Bool {
        app.manualInput.trimmingCharacters(in: .whitespaces).isEmpty || !app.isRunning
    }
}

/// Indicador discreto de que o áudio original está sendo gravado.
private struct RecDot: View {
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Theme.rose).frame(width: 6, height: 6)
            Text("REC").font(.system(size: 9.5, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(Theme.rose)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Theme.rose.opacity(0.13), in: Capsule())
        .help("Gravando o áudio original desta sessão.")
    }
}
