import AVFoundation
import XCTest
@testable import CueMe

final class MeetingRecorderTests: XCTestCase {
    func testRecorderWritesPortableHighQualityAAC() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CueMeRecorderTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = MeetingRecorder()
        let startedAt = try await recorder.start(directory: directory)
        let buffer = try XCTUnwrap(makeToneBuffer(duration: 0.25))

        await recorder.ingest(.init(source: .self, buffer: buffer, ts: startedAt))
        let duration = await recorder.stop()

        let url = directory.appendingPathComponent(MeetingRecording.selfFilename)
        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(url.pathExtension, "m4a")
        XCTAssertEqual(file.fileFormat.streamDescription.pointee.mFormatID, kAudioFormatMPEG4AAC)
        XCTAssertEqual(file.processingFormat.sampleRate, 48_000, accuracy: 1)
        XCTAssertEqual(file.processingFormat.channelCount, 1)
        XCTAssertEqual(try XCTUnwrap(duration), 0.25, accuracy: 0.02)
    }

    func testRecordingFilenamesArePortableM4A() {
        XCTAssertEqual(MeetingRecording.selfFilename, "self.m4a")
        XCTAssertEqual(MeetingRecording.otherFilename, "other.m4a")
    }

    private func makeToneBuffer(duration: TimeInterval) -> AVAudioPCMBuffer? {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        )!
        let frames = AVAudioFrameCount(duration * format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for frame in 0..<Int(frames) {
            samples[frame] = sin(Float(frame) * 2 * .pi * 440 / Float(format.sampleRate)) * 0.2
        }
        return buffer
    }
}
