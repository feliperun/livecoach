import Foundation

enum RuntimeHealthLevel: String, Codable, Sendable, Comparable {
    case healthy, degraded, critical

    static func < (lhs: Self, rhs: Self) -> Bool {
        let order: [Self] = [.healthy, .degraded, .critical]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

struct RuntimeHealth: Sendable, Equatable {
    var level: RuntimeHealthLevel = .healthy
    var reason: String?

    static let healthy = RuntimeHealth()
}

enum WatchdogAction: Sendable, Equatable {
    case restartMicrophone
    case restartSystemCapture
    case restartSTT(Speaker)
    case recordingStalled
}

/// Pure state machine used by the live watchdog and by the long-running soak
/// harness. It only reasons about metadata/timestamps; no conversation content
/// is retained.
struct RuntimeWatchdog: Sendable {
    private let startedAt: Date
    private(set) var lastChunkAt: [Speaker: Date] = [:]
    private(set) var lastVoiceAt: [Speaker: Date] = [:]
    private(set) var lastTranscriptAt: [Speaker: Date] = [:]
    private var lastRecoveryAt: [String: Date] = [:]
    private var previousRecordingFrames: Int64?
    private var recordingUnchangedSince: Date?

    init(startedAt: Date = Date()) {
        self.startedAt = startedAt
    }

    mutating func observeChunk(_ speaker: Speaker, at: Date = Date()) {
        lastChunkAt[speaker] = at
    }

    mutating func observeLevel(_ speaker: Speaker, level: Float, at: Date = Date()) {
        guard level >= 0.025 else { return }
        lastVoiceAt[speaker] = at
    }

    mutating func observeTranscript(_ speaker: Speaker, at: Date = Date()) {
        lastTranscriptAt[speaker] = at
    }

    mutating func evaluate(
        now: Date = Date(),
        micState: CaptureChannelState,
        systemState: CaptureChannelState,
        recordingFrames: Int64?
    ) -> [WatchdogAction] {
        var actions: [WatchdogAction] = []
        if let action = captureRecovery(for: .self, state: micState, now: now) { actions.append(action) }
        if let action = captureRecovery(for: .other, state: systemState, now: now) { actions.append(action) }
        actions.append(contentsOf: sttRecoveries(now: now))
        if let frames = recordingFrames, let action = recordingRecovery(frames: frames, now: now) {
            actions.append(action)
        }
        return actions
    }

    private mutating func captureRecovery(
        for speaker: Speaker,
        state: CaptureChannelState,
        now: Date
    ) -> WatchdogAction? {
        guard shouldRecoverChannel(speaker, state: state, now: now) else { return nil }
        markRecovery("capture-\(speaker.rawValue)", now: now)
        return speaker == .self ? .restartMicrophone : .restartSystemCapture
    }

    private mutating func sttRecoveries(now: Date) -> [WatchdogAction] {
        var actions: [WatchdogAction] = []
        for speaker in [Speaker.`self`, Speaker.other] {
            guard let voice = lastVoiceAt[speaker], now.timeIntervalSince(voice) <= 12 else { continue }
            let transcript = lastTranscriptAt[speaker] ?? .distantPast
            guard voice > transcript,
                  now.timeIntervalSince(voice) >= 6,
                  recoveryAllowed("stt-\(speaker.rawValue)", now: now, cooldown: 20) else { continue }
            actions.append(.restartSTT(speaker))
            markRecovery("stt-\(speaker.rawValue)", now: now)
        }
        return actions
    }

    private mutating func recordingRecovery(frames: Int64, now: Date) -> WatchdogAction? {
        defer { previousRecordingFrames = frames }
        guard previousRecordingFrames == frames else {
            recordingUnchangedSince = nil
            return nil
        }
        recordingUnchangedSince = recordingUnchangedSince ?? now
        guard let since = recordingUnchangedSince,
              now.timeIntervalSince(since) >= 8,
              recentChunks(now: now),
              recoveryAllowed("recorder", now: now, cooldown: 30) else { return nil }
        markRecovery("recorder", now: now)
        return .recordingStalled
    }

    private func shouldRecoverChannel(_ speaker: Speaker, state: CaptureChannelState, now: Date) -> Bool {
        guard state == .active || state == .silent else { return false }
        let key = "capture-\(speaker.rawValue)"
        guard recoveryAllowed(key, now: now, cooldown: 20) else { return false }
        let last = lastChunkAt[speaker] ?? startedAt
        return now.timeIntervalSince(last) >= 6
    }

    private func recentChunks(now: Date) -> Bool {
        lastChunkAt.values.contains { now.timeIntervalSince($0) <= 4 }
    }

    private func recoveryAllowed(_ key: String, now: Date, cooldown: TimeInterval) -> Bool {
        guard let last = lastRecoveryAt[key] else { return true }
        return now.timeIntervalSince(last) >= cooldown
    }

    private mutating func markRecovery(_ key: String, now: Date) {
        lastRecoveryAt[key] = now
    }
}
