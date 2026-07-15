import SwiftUI

struct RootWorkspaceShell: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 0) {
            SessionSidebar()
            Divider().opacity(0.45)

            VStack(spacing: 0) {
                HeaderBar()
                if let record = app.selectedSession {
                    SessionWorkspaceView(record: record)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    LiveWorkspace()
                }
            }
        }
    }
}

private struct LiveWorkspace: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            CaptureHealthAlert()

            if isPristineIdle {
                SessionLaunchView()
                    .frame(maxHeight: .infinity)
            } else if app.brief.mode.isPassive {
                MeetingPanel()
                    .frame(maxHeight: .infinity)
            } else {
                QuestionBanner()
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                CoachingPane()
                    .frame(maxHeight: .infinity)
            }

            if !isPristineIdle, !app.isRunning {
                CollapsiblePanels()
            }
            if app.sessionStartTime != nil {
                LiveTransportBar()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.snappy(duration: 0.24), value: app.sessionStartTime != nil)
    }

    private var isPristineIdle: Bool {
        app.sessionState == .idle && app.transcript.isEmpty && app.coachCards.isEmpty
    }
}


