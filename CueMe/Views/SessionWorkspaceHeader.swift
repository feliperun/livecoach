import SwiftUI

struct SessionWorkspaceHeader: View {
    @Environment(AppModel.self) private var app
    let record: SessionRecord
    @State private var showParticipants = false
    @State private var selfName = ""
    @State private var otherName = ""
    @State private var showProject = false
    @State private var newProjectName = ""

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .lineLimit(1)
                HStack(spacing: 7) {
                    Label(record.origin.label, systemImage: record.origin == .live ? "dot.radiowaves.left.and.right" : "square.and.arrow.down")
                    Label(record.startedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    Label(SessionArchive.clock(record.duration), systemImage: "clock")
                    if record.hasAudio {
                        Label(audioFormatLabel, systemImage: "waveform")
                            .foregroundStyle(Theme.mint)
                    }
                }
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
            }
            Spacer()
            projectButton
            participantsButton
            Button(action: app.revealArchive) {
                Image(systemName: "folder")
            }
            .buttonStyle(IconButtonStyle())
            .help("Mostrar arquivos da sessão")
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
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
}
