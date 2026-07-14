import Foundation

/// Races the preferred provider against a delayed backup. The backup starts
/// only when the primary has not produced a first token within the latency
/// budget, or when it fails before producing output.
final class FailoverCoachSession: CoachSession, @unchecked Sendable {
    private let primary: any CoachSession
    private let secondary: any CoachSession
    private let delay: Duration
    private let onFailover: @Sendable () -> Void

    init(
        primary: any CoachSession,
        secondary: any CoachSession,
        delay: Duration = .seconds(4),
        onFailover: @escaping @Sendable () -> Void = {}
    ) {
        self.primary = primary
        self.secondary = secondary
        self.delay = delay
        self.onFailover = onFailover
    }

    func send(_ user: String) async -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let state = RelayState()
            let orchestration = Task {
                await self.runRace(user: user, state: state, continuation: continuation)
            }
            continuation.onTermination = { _ in orchestration.cancel() }
        }
    }

    private func runRace(
        user: String,
        state: RelayState,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.relayPrimary(user: user, state: state, continuation: continuation)
            }
            group.addTask {
                await self.startDelayedBackup(user: user, state: state, continuation: continuation)
            }
            await group.waitForAll()
        }
    }

    private func relayPrimary(
        user: String,
        state: RelayState,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async {
        do {
            let stream = await primary.send(user)
            var emitted = false
            for try await delta in stream {
                guard !Task.isCancelled else { return }
                if !emitted {
                    emitted = true
                    guard state.claim(.primary) else { return }
                }
                guard state.isWinner(.primary) else { return }
                continuation.yield(delta)
            }
            await finishPrimary(emitted: emitted, user: user, state: state, continuation: continuation)
        } catch {
            await recoverPrimary(error: error, user: user, state: state, continuation: continuation)
        }
    }

    private func finishPrimary(
        emitted: Bool,
        user: String,
        state: RelayState,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async {
        if emitted {
            if state.finish(.primary) { continuation.finish() }
        } else if state.claim(.secondary) {
            onFailover()
            await Self.relaySecondary(secondary, user: user, state: state, continuation: continuation)
        }
    }

    private func recoverPrimary(
        error: Error,
        user: String,
        state: RelayState,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async {
        if state.claim(.secondary) {
            onFailover()
            await Self.relaySecondary(secondary, user: user, state: state, continuation: continuation)
        } else if state.finish(.primary) {
            continuation.finish(throwing: error)
        }
    }

    private func startDelayedBackup(
        user: String,
        state: RelayState,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async {
        do { try await Task.sleep(for: delay) }
        catch { return }
        guard state.claim(.secondary) else { return }
        onFailover()
        await Self.relaySecondary(secondary, user: user, state: state, continuation: continuation)
    }

    private static func relaySecondary(
        _ secondary: any CoachSession,
        user: String,
        state: RelayState,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async {
        do {
            let stream = await secondary.send(user)
            for try await delta in stream {
                if Task.isCancelled || !state.isWinner(.secondary) { return }
                continuation.yield(delta)
            }
            if state.finish(.secondary) { continuation.finish() }
        } catch {
            if state.finish(.secondary) { continuation.finish(throwing: error) }
        }
    }

    func complete(_ user: String) async throws -> String {
        var result = ""
        let stream = await send(user)
        for try await delta in stream { result += delta }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func prewarm() async throws {
        do { try await primary.prewarm() }
        catch {
            onFailover()
            try await secondary.prewarm()
        }
    }

    func shutdown() async {
        await primary.shutdown()
        await secondary.shutdown()
    }
}

private final class RelayState: @unchecked Sendable {
    enum Winner { case primary, secondary }
    private let lock = NSLock()
    private var winner: Winner?
    private var completed = false

    func claim(_ candidate: Winner) -> Bool {
        lock.withLock {
            guard winner == nil, !completed else { return false }
            winner = candidate
            return true
        }
    }

    func isWinner(_ candidate: Winner) -> Bool {
        lock.withLock { winner == candidate && !completed }
    }

    func finish(_ candidate: Winner) -> Bool {
        lock.withLock {
            guard winner == candidate, !completed else { return false }
            completed = true
            return true
        }
    }
}
