@preconcurrency import AppKit
@preconcurrency import Foundation
import UniformTypeIdentifiers

@MainActor
final class ShareViewController: NSViewController {
    private let iconView = NSImageView()
    private let statusLabel = NSTextField(labelWithString: "Enviando para o CueMe…")
    private let progress = NSProgressIndicator()
    private var started = false

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 150))
        iconView.image = NSImage(systemSymbolName: "waveform.badge.plus", accessibilityDescription: nil)
        iconView.contentTintColor = .systemPurple
        iconView.symbolConfiguration = .init(pointSize: 26, weight: .semibold)
        statusLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        statusLabel.alignment = .center
        progress.style = .spinning
        progress.controlSize = .small
        progress.startAnimation(nil)

        let stack = NSStackView(views: [iconView, statusLabel, progress])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20)
        ])
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard !started else { return }
        started = true
        Task { await importAttachments() }
    }

    private func importAttachments() async {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.audio.identifier) }
        guard !providers.isEmpty else {
            await fail(ExternalAudioInboxError.unsupportedAudio)
            return
        }

        do {
            for provider in providers { try await enqueue(provider) }
            statusLabel.stringValue = providers.count == 1 ? "Áudio enviado" : "Áudios enviados"
            progress.stopAnimation(nil)
            progress.isHidden = true
            DistributedNotificationCenter.default().postNotificationName(
                .cueMeExternalAudioReady,
                object: nil
            )
            try? await Task.sleep(for: .milliseconds(250))
            if let context = extensionContext {
                _ = await context.open(ExternalAudioInbox.wakeURL)
                context.completeRequest(returningItems: nil)
            }
        } catch {
            await fail(error)
        }
    }

    private func enqueue(_ provider: NSItemProvider) async throws {
        let suggestedName = provider.suggestedName
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.audio.identifier) { url, error in
                do {
                    if let error { throw error }
                    guard let url else { throw ExternalAudioInboxError.unsupportedAudio }
                    try ExternalAudioInbox.enqueueCopy(from: url, filename: suggestedName)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func fail(_ error: Error) async {
        progress.stopAnimation(nil)
        progress.isHidden = true
        iconView.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
        iconView.contentTintColor = .systemRed
        statusLabel.stringValue = error.localizedDescription
        try? await Task.sleep(for: .seconds(1))
        extensionContext?.cancelRequest(withError: error)
    }
}
