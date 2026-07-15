@preconcurrency import Foundation
import UniformTypeIdentifiers

@MainActor
enum ExternalAudioDropReceiver {
    static func enqueue(_ providers: [NSItemProvider]) async -> Int {
        var imported = 0
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.audio.identifier) {
            if await enqueue(provider) { imported += 1 }
        }
        return imported
    }

    private static func enqueue(_ provider: NSItemProvider) async -> Bool {
        let suggestedName = provider.suggestedName
        return await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.audio.identifier) { url, _ in
                guard let url else {
                    continuation.resume(returning: false)
                    return
                }
                do {
                    try ExternalAudioInbox.enqueueCopy(from: url, filename: suggestedName)
                    continuation.resume(returning: true)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }
}
