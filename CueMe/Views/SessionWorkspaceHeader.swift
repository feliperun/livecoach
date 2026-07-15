import SwiftUI

struct SessionWorkspaceHeader: View {
    @Environment(AppModel.self) private var app
    let record: SessionRecord
    @State private var showParticipants = false
    @State private var selfName = ""
    @State private var otherName = ""
    @State private var showProject = false
    @State private var newProjectName = ""
    @State private var showRename = false
    @State private var titleDraft = ""
    @State private var showLabels = false
    @State private var labelDraft = ""

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    titleDraft = record.title
                    showRename = true
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: record.noteKind.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.violet)
                        Text(record.title)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .lineLimit(1)
                        Image(systemName: "pencil")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("note.rename")
                .popover(isPresented: $showRename) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Nome da nota").font(.headline)
                        TextField("Um nome que valha reencontrar", text: $titleDraft)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("note.title.input")
                            .onSubmit(saveTitle)
                        Button("Salvar", action: saveTitle)
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("note.title.save")
                    }
                    .padding(14).frame(width: 310)
                }
                HStack(spacing: 7) {
                    Text(record.noteKind.label)
                    Label(record.startedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    if record.origin != .written {
                        Label(SessionArchive.clock(record.duration), systemImage: "clock")
                    }
                    if record.hasAudio {
                        Label(audioFormatLabel, systemImage: "waveform")
                            .foregroundStyle(Theme.mint)
                    }
                }
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
            }
            Spacer()
            labelsButton
            projectButton
            if record.origin != .written { participantsButton }
            Button { app.revealMemoryNote(record.id) } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(IconButtonStyle())
            .help("Mostrar arquivos da sessão")
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
    }

    private var labelsButton: some View {
        Button { showLabels.toggle() } label: {
            Label(record.labels.isEmpty ? "Labels" : "\(record.labels.count)", systemImage: "tag")
                .font(.system(size: 10, weight: .semibold))
        }
        .buttonStyle(.bordered).controlSize(.small)
        .accessibilityIdentifier("note.labels")
        .popover(isPresented: $showLabels) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Labels").font(.headline)
                if record.labels.isEmpty {
                    Text("Agrupe ideias que atravessam projetos.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(record.labels, id: \.self) { label in
                            Button {
                                app.removeLabel(label, from: record.id)
                            } label: {
                                HStack(spacing: 4) {
                                    Text(label)
                                    Image(systemName: "xmark")
                                }
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                            .accessibilityIdentifier("note.label.\(label)")
                        }
                    }
                }
                HStack {
                    TextField("ex.: crescimento", text: $labelDraft)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("note.label.input")
                        .onSubmit(addLabel)
                    Button("Adicionar", action: addLabel)
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("note.label.add")
                }
                if !app.allLabels.isEmpty {
                    Divider()
                    Text("JÁ USADAS").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                    FlowLayout(spacing: 5) {
                        ForEach(app.allLabels.filter { !record.labels.contains($0) }, id: \.self) { label in
                            Button(label) { app.addLabel(label, to: record.id) }
                                .buttonStyle(.plain).font(.caption).foregroundStyle(Theme.violet)
                        }
                    }
                }
            }
            .padding(14).frame(width: 300)
        }
    }

    private var projectButton: some View {
        Button { showProject.toggle() } label: {
            Label(app.project(for: record)?.name ?? "Projeto", systemImage: "folder.badge.gearshape")
                .font(.system(size: 10, weight: .semibold))
        }
        .buttonStyle(.bordered).controlSize(.small)
        .accessibilityIdentifier("session.project")
        .popover(isPresented: $showProject) {
            VStack(alignment: .leading, spacing: 9) {
                Text("Projeto").font(.headline)
                Button("Sem projeto") { app.assignProject(nil, to: record.id); showProject = false }
                    .buttonStyle(.plain)
                ForEach(app.projects.filter { !$0.archived }) { project in
                    Button(project.name) { app.assignProject(project.id, to: record.id); showProject = false }
                        .buttonStyle(.plain)
                }
                if let projectID = record.projectID {
                    Divider()
                    Text("TIMELINE").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                    ForEach(app.timeline(for: projectID).prefix(6)) { entry in
                        Button {
                            app.selectSession(entry.sessionID)
                            showProject = false
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.title).font(.system(size: 10, weight: .semibold))
                                Text(entry.detail).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(2)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                            .accessibilityIdentifier("timeline.\(entry.id)")
                    }
                }
                Divider()
                TextField("Novo projeto", text: $newProjectName).textFieldStyle(.roundedBorder)
                Button("Criar e vincular") {
                    if let id = app.createProject(named: newProjectName) { app.assignProject(id, to: record.id) }
                    newProjectName = ""; showProject = false
                }.buttonStyle(.borderedProminent)
            }.padding(14).frame(width: 260)
        }
    }

    private var participantsButton: some View {
        Button {
            selfName = record.participantName(for: .self)
            otherName = record.participantName(for: .other)
            showParticipants.toggle()
        } label: {
            Image(systemName: "person.2")
        }
        .buttonStyle(IconButtonStyle())
        .help("Nomear participantes")
        .popover(isPresented: $showParticipants) {
            VStack(alignment: .leading, spacing: 9) {
                TextField("Você", text: $selfName)
                TextField("Interlocutor", text: $otherName)
                Button("Salvar") {
                    app.setParticipantName(selfName, for: .self, sessionID: record.id)
                    app.setParticipantName(otherName, for: .other, sessionID: record.id)
                    app.linkPerson(named: otherName, to: record.id)
                    showParticipants = false
                }
                .buttonStyle(.borderedProminent)
            }
            .textFieldStyle(.roundedBorder)
            .padding(14).frame(width: 240)
        }
    }

    private var audioFormatLabel: String {
        let urls = [MeetingRecording.selfURL(for: record), MeetingRecording.otherURL(for: record)]
        let existing = urls.first { FileManager.default.fileExists(atPath: $0.path) }
        switch existing?.pathExtension.lowercased() {
        case "m4a": return "M4A · AAC"
        case "caf": return "CAF · legado"
        default: return "Áudio local"
        }
    }

    private func saveTitle() {
        app.renameMemoryNote(record.id, to: titleDraft)
        showRename = false
    }

    private func addLabel() {
        app.addLabel(labelDraft, to: record.id)
        labelDraft = ""
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let width = proposal.width ?? 300
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var points: [CGPoint] = []
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), points)
    }
}
