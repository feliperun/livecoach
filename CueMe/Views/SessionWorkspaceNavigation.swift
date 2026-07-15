import SwiftUI

struct SessionWorkspaceTabs: View {
    let record: SessionRecord
    @Binding var selection: SessionWorkspaceTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(availableTabs) { item in
                SessionTabButton(item: item, count: badge(for: item), selected: selection == item) {
                    withAnimation(.snappy(duration: 0.18)) { selection = item }
                }
            }
        }
        .padding(4)
        .background(Theme.interactive, in: RoundedRectangle(cornerRadius: 11))
        .padding(.horizontal, 16).padding(.bottom, 12)
    }

    private var availableTabs: [SessionWorkspaceTab] {
        record.origin.supportsLiveCoach
            ? SessionWorkspaceTab.allCases
            : SessionWorkspaceTab.allCases.filter { $0 != .coach }
    }

    private func badge(for tab: SessionWorkspaceTab) -> Int? {
        switch tab {
        case .review:
            return record.review.decisions.count + record.review.openQuestions.count
                + record.takeaways.filter { !$0.isDone }.count
        case .coach: return record.coachCards.count
        case .summary: return record.minutes.topics.count
        case .transcript: return record.transcript.filter(\.isFinal).count
        case .notes: return record.notes.count
        case .takeaways: return record.takeaways.filter { !$0.isDone }.count
        case .generated: return record.artifacts.count
        }
    }
}

struct SessionWorkspacePane: View {
    let record: SessionRecord
    let selection: SessionWorkspaceTab
    let player: MeetingPlayer

    @ViewBuilder
    var body: some View {
        switch selection {
        case .review: SessionReviewPane(record: record, player: player)
        case .coach: SessionCoachPane(record: record)
        case .summary: SessionSummaryPane(record: record)
        case .transcript: SessionTranscriptPane(record: record, player: player)
        case .notes: SessionNotesPane(record: record, player: player)
        case .takeaways: SessionTakeawaysPane(record: record)
        case .generated: SessionArtifactsPane(record: record)
        }
    }
}
