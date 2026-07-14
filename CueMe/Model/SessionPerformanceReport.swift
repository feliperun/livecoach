import Foundation

enum CoachFeedback: String, Codable, Sendable, CaseIterable {
    case helpful, notHelpful
}

struct SessionPerformanceReport: Sendable, Equatable {
    let sttTurns: Int
    let coachRequests: Int
    let coachCompleted: Int
    let coveragePercent: Int
    let firstPhraseP50Ms: Int64?
    let firstPhraseP95Ms: Int64?
    let recoveries: Int
    let errors: Int

    init(diagnostics: SessionDiagnostics) {
        sttTurns = diagnostics.count("stt_final")
        coachRequests = diagnostics.count("requested")
        coachCompleted = diagnostics.count("completed")
        coveragePercent = coachRequests == 0 ? 0 : Int((Double(coachCompleted) / Double(coachRequests) * 100).rounded())
        let latencies = diagnostics.durationValues("first_phrase").sorted()
        firstPhraseP50Ms = Self.percentile(latencies, 0.50)
        firstPhraseP95Ms = Self.percentile(latencies, 0.95)
        recoveries = diagnostics.count(kind: .recovery)
        errors = diagnostics.count(kind: .error)
    }

    private static func percentile(_ values: [Int64], _ p: Double) -> Int64? {
        guard !values.isEmpty else { return nil }
        let index = Int(ceil(Double(values.count) * p)) - 1
        return values[max(0, min(values.count - 1, index))]
    }
}
