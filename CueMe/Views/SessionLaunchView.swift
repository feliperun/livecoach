import SwiftUI

struct SessionLaunchView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("didDismissVoiceMemoImportHint") private var didDismissVoiceMemoImportHint = false

    var body: some View {
        @Bindable var app = app
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sua memória, viva e organizada.")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Escreva, grave e conecte o que você vive. O CueMe devolve esse contexto quando ele mais importa.")
                        .font(.system(size: 15, design: .serif))
                        .lineSpacing(4)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 680, alignment: .leading)
                }

                HStack(spacing: 12) {
                    homeAction(
                        title: "Nova nota",
                        detail: "Comece por uma ideia",
                        icon: "square.and.pencil",
                        identifier: "home.new-note",
                        tint: Theme.violet
                    ) { _ = app.createMemoryNote(kind: .note) }
                    homeAction(
                        title: "Diário",
                        detail: "Registre o que está vivendo",
                        icon: "book.closed.fill",
                        identifier: "home.journal",
                        tint: Theme.amber
                    ) { _ = app.createMemoryNote(kind: .journal) }
                    homeAction(
                        title: "Gravar",
                        detail: "Conversa ou pensamento",
                        icon: "waveform.badge.mic",
                        identifier: "home.record",
                        tint: Theme.rose
                    ) {
                        app.brief.mode = .meeting
                        app.start()
                    }
                }

                VStack(alignment: .leading, spacing: 11) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ENTRAR PREPARADO").font(.system(size: 10, weight: .bold)).tracking(1)
                            Text("Perfis tornam o Coach específico para o momento.")
                                .font(.system(size: 12.5)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("Memória no Coach", isOn: $app.usePersonalMemoryInCoach)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .help("Usa notas relacionadas como contexto factual durante a sessão.")
                        Button("Configurar sessão") { app.showSettings = true }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                    HStack(spacing: 10) {
                        profileCard(
                            title: "Entrevista",
                            detail: "Acesse sua bagagem sob pressão",
                            icon: "person.crop.rectangle.stack.fill",
                            identifier: "home.profile.interview"
                        ) { app.brief.mode = .interview; app.showSettings = true }
                        profileCard(
                            title: "Vendas",
                            detail: "Ouça objeções e conduza próximos passos",
                            icon: "chart.line.uptrend.xyaxis.circle.fill",
                            identifier: "home.profile.sales"
                        ) { app.brief.mode = .sales; app.showSettings = true }
                        ForEach(app.profiles.prefix(2)) { profile in
                            Button {
                                app.applyProfile(profile.id)
                            } label: {
                                profileCardLabel(
                                    title: profile.name,
                                    detail: profile.brief.goal.isEmpty ? profile.brief.mode.label : profile.brief.goal,
                                    icon: profile.brief.mode.icon
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("home.profile.\(profile.id.uuidString)")
                        }
                    }
                }
                .padding(16)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(Theme.divider))

                HStack(spacing: 10) {
                    capability("waveform", "Áudio soberano")
                    capability("captions.bubble", "Transcrição")
                    capability("brain.head.profile", "Memória conectada")
                    Spacer()
                    Button {
                        app.chooseAudioFiles()
                    } label: {
                        Label("Importar áudio", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Text("ou arraste aqui")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: 920, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.top, 48)
            .padding(.bottom, 32)

            if !didDismissVoiceMemoImportHint {
                HStack(spacing: 7) {
                    Image(systemName: "mic.badge.plus")
                        .foregroundStyle(Theme.violet)
                    Text("Voice Memos: Compartilhar → CueMe")
                        .font(.system(size: 10.5, weight: .semibold))
                    Button {
                        didDismissVoiceMemoImportHint = true
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Theme.violet.opacity(0.08), in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.violet.opacity(0.2)))
            }

        }
        .frame(maxWidth: .infinity)
    }

    private func homeAction(
        title: String,
        detail: String,
        icon: String,
        identifier: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 14, weight: .bold, design: .rounded))
                    Text(detail).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
            .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(tint.opacity(0.25)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func profileCard(
        title: String,
        detail: String,
        icon: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            profileCardLabel(title: title, detail: detail, icon: icon)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func profileCardLabel(title: String, detail: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.cyan)
                .frame(width: 28, height: 28).background(Theme.cyan.opacity(0.11), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .bold))
                Text(detail).font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(10).frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .background(Theme.interactive, in: RoundedRectangle(cornerRadius: 11))
    }

    private func capability(_ icon: String, _ label: String) -> some View {
        Label(label, systemImage: icon)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(Theme.interactive, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.divider))
    }
}


