import SwiftUI

struct SessionSidebar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 9) {
                if !app.sidebarCollapsed {
                    Image(systemName: "waveform.badge.mic")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.violet)
                        .frame(width: 28, height: 28)
                        .background(Theme.violet.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))
                    Text("CueMe")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                Spacer(minLength: 0)
                Button {
                    withAnimation(.snappy(duration: 0.24)) { app.sidebarCollapsed.toggle() }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .buttonStyle(IconButtonStyle())
                .help(app.sidebarCollapsed ? "Abrir histórico" : "Recolher histórico")
            }
            .padding(.horizontal, app.sidebarCollapsed ? 14 : 12)
            .padding(.top, 12)

            liveButton

            if !app.sidebarCollapsed {
                HStack {
                    Text("RECENTES")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(0.9)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("\(app.history.count)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 13).padding(.top, 5)
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(app.history) { record in
                            sessionButton(record)
                        }
                    }
                    .padding(.horizontal, 7)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(app.history.prefix(12)) { record in
                            compactButton(record)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            Button {
                app.revealArchive()
            } label: {
                Group {
                    if app.sidebarCollapsed {
                        Image(systemName: "folder")
                    } else {
                        Label("Arquivos", systemImage: "folder")
                    }
                }
                .font(.system(size: 10.5, weight: .semibold))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 11)
            .help(app.archivePath)
        }
        .frame(width: app.sidebarCollapsed ? 58 : 242)
        .background(Theme.sidebar)
        .animation(.snappy(duration: 0.24), value: app.sidebarCollapsed)
    }

    private var liveButton: some View {
        Button(action: app.showLiveSession) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(app.isRunning ? Theme.mint.opacity(0.15) : Theme.violet.opacity(0.16))
                    Image(systemName: app.isRunning ? "waveform" : "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(app.isRunning ? Theme.mint : Theme.violet)
                        .symbolEffect(.pulse.byLayer, options: .repeating, isActive: app.isRunning)
                }
                .frame(width: 32, height: 32)
                if !app.sidebarCollapsed {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(app.isRunning ? "Sessão ao vivo" : "Nova gravação")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                        Text(app.isRunning ? "gravando agora" : "começar uma conversa")
                            .font(.system(size: 9.5)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .padding(app.sidebarCollapsed ? 8 : 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(app.selectedSessionID == nil ? Theme.panelRaised : Theme.panel,
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(app.selectedSessionID == nil ? Theme.violet.opacity(0.32) : Theme.divider)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, app.sidebarCollapsed ? 5 : 8)
    }

    private func sessionButton(_ record: SessionRecord) -> some View {
        Button { app.selectSession(record.id) } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(app.selectedSessionID == record.id ? Theme.violet : .clear)
                    .frame(width: 3, height: 24)
                Image(systemName: record.hasAudio ? "waveform" : "doc.text")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(app.selectedSessionID == record.id ? Theme.violet : .secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.title).lineLimit(1)
                        .font(.system(size: 11.5, weight: .semibold))
                    Text(record.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 9.5)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(app.selectedSessionID == record.id ? Theme.panelRaised : .clear,
                        in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.18), value: app.selectedSessionID)
        .contextMenu {
            Button("Apagar", systemImage: "trash", role: .destructive) { app.deleteHistory(record.id) }
        }
    }

    private func compactButton(_ record: SessionRecord) -> some View {
        Button { app.selectSession(record.id) } label: {
            Image(systemName: record.hasAudio ? "waveform" : "doc.text")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(app.selectedSessionID == record.id ? Theme.violet : .secondary)
                .frame(width: 32, height: 32)
                .background(app.selectedSessionID == record.id ? Theme.violet.opacity(0.14) : .clear,
                            in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .help(record.title)
    }
}
