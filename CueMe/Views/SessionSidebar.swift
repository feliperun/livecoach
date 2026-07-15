import SwiftUI

struct SessionSidebar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        let results = app.historySearchResults
        let records = Dictionary(uniqueKeysWithValues: app.history.map { ($0.id, $0) })
        let visibleRecords = results.compactMap { records[$0.recordID] }
        let snippets = Dictionary(uniqueKeysWithValues: results.compactMap { result in
            result.snippet.map { (result.recordID, $0) }
        })

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
            importButton

            if !app.sidebarCollapsed {
                historyControls
                HStack {
                    Text(app.historySearch.isEmpty ? "RECENTES" : "RESULTADOS")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(0.9)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("\(visibleRecords.count)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 13).padding(.top, 5)
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(visibleRecords) { record in
                            sessionButton(record, snippet: snippets[record.id])
                        }
                    }
                    .padding(.horizontal, 7)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(visibleRecords.prefix(12)) { record in
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
        .frame(width: app.sidebarCollapsed ? 58 : 268)
        .background(Theme.sidebar)
        .animation(.snappy(duration: 0.24), value: app.sidebarCollapsed)
    }

    private var importButton: some View {
        Button {
            app.chooseAudioFiles()
        } label: {
            Group {
                if app.sidebarCollapsed {
                    Image(systemName: "square.and.arrow.down")
                        .frame(width: 32, height: 28)
                } else {
                    Label("Importar áudio", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).frame(height: 30)
                }
            }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .background(Theme.interactive, in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .help("Escolha um arquivo ou, no Voice Memos, use Compartilhar → CueMe.")
        .disabled(app.isSessionBusy || app.audioImportStatus?.isActive == true)
        .padding(.horizontal, app.sidebarCollapsed ? 8 : 10)
        .overlay(alignment: .bottom) {
            if !app.sidebarCollapsed, let status = app.audioImportStatus {
                ImportStatusRow(status: status)
                    .offset(y: 49)
            }
        }
        .padding(.bottom, !app.sidebarCollapsed && app.audioImportStatus != nil ? 50 : 0)
    }

    private var historyControls: some View {
        VStack(spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(.tertiary)
                TextField("Buscar assuntos e decisões", text: Binding(
                    get: { app.historySearch }, set: { app.historySearch = $0 }
                ))
                .accessibilityIdentifier("memory.search")
                .textFieldStyle(.plain).font(.system(size: 10.5))
                if !app.historySearch.isEmpty {
                    Button { app.historySearch = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 9).frame(height: 30)
            .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.divider))
            if !app.historySearch.isEmpty {
                Button {
                    app.askGlobalMemory()
                } label: {
                    Label(app.globalMemoryAnswering ? "Consultando…" : "Perguntar à memória", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).controlSize(.small)
                .accessibilityIdentifier("memory.ask")
                .disabled(app.globalMemoryAnswering)
                if let answer = app.globalMemoryAnswer {
                    ScrollView {
                        Text(.init(answer)).font(.system(size: 10.5)).textSelection(.enabled)
                            .accessibilityIdentifier("memory.answer")
                            .accessibilityValue(answer)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 150).padding(8)
                    .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 9))
                }
            }
            HStack(spacing: 6) {
                filterMenu(
                    title: app.historyDateFilter.label,
                    icon: "calendar",
                    values: HistoryDateFilter.allCases,
                    selection: app.historyDateFilter
                ) { app.historyDateFilter = $0 }
                filterMenu(
                    title: app.historyTypeFilter.label,
                    icon: "line.3.horizontal.decrease.circle",
                    values: HistoryTypeFilter.allCases,
                    selection: app.historyTypeFilter
                ) { app.historyTypeFilter = $0 }
            }
        }
        .padding(.horizontal, 10)
    }

    private func filterMenu<Value: Identifiable & Equatable>(
        title: String,
        icon: String,
        values: [Value],
        selection: Value,
        onSelect: @escaping (Value) -> Void
    ) -> some View where Value.ID == String {
        Menu {
            ForEach(values) { value in
                Button {
                    onSelect(value)
                } label: {
                    HStack {
                        Text(filterLabel(value))
                        if value == selection { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 9.5, weight: .semibold)).lineLimit(1)
                .frame(maxWidth: .infinity).padding(.horizontal, 7).frame(height: 25)
                .background(Theme.interactive, in: RoundedRectangle(cornerRadius: 7))
        }
        .menuStyle(.borderlessButton)
    }

    private func filterLabel<Value>(_ value: Value) -> String {
        if let date = value as? HistoryDateFilter { return date.label }
        if let type = value as? HistoryTypeFilter { return type.label }
        return "Filtro"
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

    private func sessionButton(_ record: SessionRecord, snippet: String?) -> some View {
        Button { app.selectSession(record.id) } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(app.selectedSessionID == record.id ? Theme.violet : .clear)
                    .frame(width: 3, height: 24)
                Image(systemName: sessionIcon(record))
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(app.selectedSessionID == record.id ? Theme.violet : .secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.title).lineLimit(1)
                        .font(.system(size: 11.5, weight: .semibold))
                    Text(snippet ?? record.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .lineLimit(1)
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
        .accessibilityIdentifier("session.\(record.id.uuidString)")
        .animation(.snappy(duration: 0.18), value: app.selectedSessionID)
        .contextMenu {
            Button("Apagar", systemImage: "trash", role: .destructive) { app.deleteHistory(record.id) }
        }
    }

    private func compactButton(_ record: SessionRecord) -> some View {
        Button { app.selectSession(record.id) } label: {
            Image(systemName: sessionIcon(record))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(app.selectedSessionID == record.id ? Theme.violet : .secondary)
                .frame(width: 32, height: 32)
                .background(app.selectedSessionID == record.id ? Theme.violet.opacity(0.14) : .clear,
                            in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .help(record.title)
    }

    private func sessionIcon(_ record: SessionRecord) -> String {
        switch record.origin {
        case .audioFile: return "waveform.badge.plus"
        case .voiceMemo: return "mic.fill"
        case .live: return record.hasAudio ? "waveform" : "doc.text"
        }
    }
}

private struct ImportStatusRow: View {
    @Environment(AppModel.self) private var app
    let status: AudioImportStatus

    var body: some View {
        HStack(spacing: 7) {
            if status.isActive {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: status.phase == .completed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(status.phase == .completed ? Theme.mint : Theme.rose)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(status.title).font(.system(size: 9.5, weight: .semibold)).lineLimit(1)
                Text(status.detail).font(.system(size: 8.5)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            if status.phase == .failed, let sessionID = status.sessionID {
                Button { Task { await app.retryImportedProcessing(sessionID: sessionID) } } label: {
                    Image(systemName: "arrow.clockwise")
                }.help("Tentar novamente")
            } else if !status.isActive {
                Button(action: app.dismissAudioImportStatus) { Image(systemName: "xmark") }
            }
        }
        .buttonStyle(.plain)
        .padding(8).frame(width: 248)
        .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.divider))
    }
}
