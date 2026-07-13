import AVFoundation

/// Gera o envelope de amplitude (picos por bucket) de uma gravação, combinando
/// os dois arquivos (self/other) num único traçado — pro player visual.
enum WaveformGenerator {
    /// Lê os arquivos em background e devolve até `buckets` valores em [0, 1].
    static func envelope(selfURL: URL?, otherURL: URL?, buckets: Int) -> [Float] {
        let a = readEnvelope(selfURL, buckets: buckets)
        let b = readEnvelope(otherURL, buckets: buckets)
        guard !a.isEmpty || !b.isEmpty else { return [] }
        let n = max(a.count, b.count)
        var merged = (0..<n).map { i -> Float in
            max(i < a.count ? a[i] : 0, i < b.count ? b[i] : 0)
        }
        // Normaliza pelo pico global pra usar bem a altura disponível.
        if let peak = merged.max(), peak > 0.001 {
            for i in merged.indices { merged[i] = min(1, merged[i] / peak) }
        }
        return merged
    }

    private static func readEnvelope(_ url: URL?, buckets: Int) -> [Float] {
        guard let url, let file = try? AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        else { return [] }
        let total = file.length
        guard total > 0, buckets > 0 else { return [] }
        let framesPerBucket = max(1, Int(total) / buckets)

        guard let readBuf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096) else { return [] }

        var result: [Float] = []
        result.reserveCapacity(buckets)
        var bucketPeak: Float = 0
        var framesInBucket = 0

        while result.count < buckets {
            readBuf.frameLength = 0
            guard (try? file.read(into: readBuf, frameCount: 4096)) != nil, readBuf.frameLength > 0,
                  let channel = readBuf.floatChannelData?[0]
            else { break }

            for i in 0..<Int(readBuf.frameLength) {
                let v = abs(channel[i])
                if v > bucketPeak { bucketPeak = v }
                framesInBucket += 1
                if framesInBucket >= framesPerBucket {
                    result.append(bucketPeak)
                    bucketPeak = 0
                    framesInBucket = 0
                    if result.count >= buckets { break }
                }
            }
        }
        if framesInBucket > 0, result.count < buckets { result.append(bucketPeak) }
        return result
    }
}
