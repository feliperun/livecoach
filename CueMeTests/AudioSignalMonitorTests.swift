import AVFoundation
import XCTest
@testable import CueMe

final class AudioSignalMonitorTests: XCTestCase {
    func testDigitalZeroMicBecomesSilent() throws {
        let monitor = AudioSignalMonitor()
        let buffer = try makeBuffer(sample: 0)

        _ = monitor.observe(buffer, source: .self, now: 10)
        let events = monitor.observe(buffer, source: .self, now: 12.1)

        XCTAssertTrue(events.contains { event in
            if case .state(.self, .silent) = event { return true }
            return false
        })
    }

    func testZeroSystemBufferDoesNotMarkStreamSilent() throws {
        let monitor = AudioSignalMonitor()
        let events = monitor.observe(try makeBuffer(sample: 0), source: .other, now: 10)
        XCTAssertTrue(events.contains { event in
            if case .state(.other, .active) = event { return true }
            return false
        })
    }

    func testMicSignalBecomesActive() throws {
        let monitor = AudioSignalMonitor()
        let events = monitor.observe(try makeBuffer(sample: 0.25), source: .self, now: 10)
        XCTAssertTrue(events.contains { event in
            if case .state(.self, .active) = event { return true }
            return false
        })
    }

    private func makeBuffer(sample: Float) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 64))
        buffer.frameLength = 64
        guard let data = buffer.floatChannelData?[0] else {
            throw XCTSkip("Float buffer unavailable")
        }
        for index in 0..<64 { data[index] = sample }
        return buffer
    }
}
