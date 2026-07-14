import SwiftUI

struct SessionSidebar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                if !app.sidebarCollapsed {
                    Text("SESSÕES")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button {
                    withAnimation(.spring(duration: 0.28)) { app.sidebarCollapsed.toggle() }
                } label: {
                    Image(systemName: app.sidebarCollapsed ? "sidebar.left" : "sidebar.left")
                }
                .buttonStyle(IconButtonStyle())
                .help(app.sidebarCollapsed ? "Abrir histórico" : "Recolher histórico")
            }
            .padding(.horizontal, app.sidebarCollapsed ? 8 : 12)
            .padding(.top, 10)

            liveButton

            if !app.sidebarCollapsed {
                Divider().opacity(0.4).padding(.horizontal, 10)
                ScrollView {
                    LazyVStack(spacing: 4) {
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
            .padding(10)
            .help(app.archivePath)
        }
        .frame(width: app.sidebarCollapsed ? 52 : 226)
        .background(Theme.surface.opacity(0.72))
    }

    private var liveButton: some View {
        Button(action: app.showLiveSession) {
            HStack(spacing: 9) {
                ZStack {
                    Circle().fill(app.isRunning ? Theme.mint.opacity(0.22) : Color.white.opacity(0.06))
                    Image(systemName: app.isRunning ? "waveform" : "record.circle")
                        .foregroundStyle(app.isRunning ? Theme.mint : .secondary)
                }
                .frame(width: 30, height: 30)
                if !app.sidebarCollapsed {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(app.isRunning ? "Agora · ao vivo" : "Nova sessão")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                        Text(app.isRunning ? "gravando e transcrevendo" : "gravar reunião")
                            .font(.system(size: 9.5)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .padding(app.sidebarCollapsed ? 7 : 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(app.selectedSessionID == nil ? Theme.cyan.opacity(0.10) : .clear,
                        in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, app.sidebarCollapsed ? 4 : 7)
    }

    private func sessionButton(_ record: SessionRecord) -> some View {
        Button { app.selectSession(record.id) } label: {
            HStack(spacing: 8) {
                Image(systemName: record.hasAudio ? "waveform" : "text.bubble")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(record.hasAudio ? Theme.cyan : .secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.title).lineLimit(1)
                        .font(.system(size: 11.5, weight: .semibold))
                    Text(record.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 9.5)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(app.selectedSessionID == record.id ? Theme.violet.opacity(0.14) : .clear,
                        in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
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
