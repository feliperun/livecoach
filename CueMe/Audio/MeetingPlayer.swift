import AVFoundation
import Observation

/// Reproduz os dois arquivos sincronizados (self/other) de uma sessão gravada,
/// como se fosse um único player. Usa `AVAudioPlayer.play(atTime:)` com o mesmo
/// `deviceCurrentTime` como âncora pros dois arquivos — tocam em sincronia.
@MainActor
@Observable
final class MeetingPlayer {
    private var selfPlayer: AVAudioPlayer?
    private var otherPlayer: AVAudioPlayer?
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var isReady = false

    func load(selfURL: URL?, otherURL: URL?) {
        selfPlayer = Self.makePlayer(selfURL)
        otherPlayer = Self.makePlayer(otherURL)
        duration = max(selfPlayer?.duration ?? 0, otherPlayer?.duration ?? 0)
        isReady = selfPlayer != nil || otherPlayer != nil
        selfPlayer?.prepareToPlay()
        otherPlayer?.prepareToPlay()
    }

    private static func makePlayer(_ url: URL?) -> AVAudioPlayer? {
        guard let url, FileManager.default.fileExists(atPath: url.path),
              let player = try? AVAudioPlayer(contentsOf: url), player.duration > 0.05
        else { return nil }
        return player
    }

    func togglePlay() { isPlaying ? pause() : play() }

    func play() {
        guard isReady else { return }
        if duration > 0, currentTime >= duration - 0.05 {
            seek(to: 0)
        }
        let anchor = (selfPlayer ?? otherPlayer)!.deviceCurrentTime + 0.08
        selfPlayer?.play(atTime: anchor)
        otherPlayer?.play(atTime: anchor)
        isPlaying = true
        startPolling()
    }

    func pause() {
        selfPlayer?.pause()
        otherPlayer?.pause()
        isPlaying = false
        pollTask?.cancel()
    }

    func seek(to time: TimeInterval) {
        let wasPlaying = isPlaying
        if wasPlaying { pause() }
        let t = min(max(0, time), max(duration, 0))
        selfPlayer?.currentTime = t
        otherPlayer?.currentTime = t
        currentTime = t
        if wasPlaying { play() }
    }

    /// Encerra a reprodução e libera os players (chamar ao sair da tela).
    func teardown() {
        pause()
        selfPlayer = nil
        otherPlayer = nil
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while let self, !Task.isCancelled, self.isPlaying {
                self.currentTime = self.selfPlayer?.currentTime ?? self.otherPlayer?.currentTime ?? self.currentTime
                if self.duration > 0, self.currentTime >= self.duration - 0.05 {
                    self.isPlaying = false
                    self.currentTime = self.duration
                    self.selfPlayer?.stop()
                    self.otherPlayer?.stop()
                    self.selfPlayer?.currentTime = 0
                    self.otherPlayer?.currentTime = 0
                    break
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
}
