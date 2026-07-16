import AppKit
import SwiftUI

struct MarkdownBlockFocusRequest: Equatable {
    enum Placement: Equatable {
        case start
        case end
        case offset(Int)
    }

    let blockID: UUID
    let placement: Placement
    let token = UUID()
}

struct MarkdownBlockFormatRequest: Equatable {
    let blockID: UUID
    let style: MarkdownInlineStyle
    let token = UUID()
}

struct MarkdownBlockTextView: NSViewRepresentable {
    let block: MarkdownBlock
    let index: Int
    let focusRequest: MarkdownBlockFocusRequest?
    let formatRequest: MarkdownBlockFormatRequest?
    let onChange: (String) -> Void
    let onFocus: () -> Void
    let onSplit: (_ before: String, _ after: String) -> Void
    let onBackspaceAtStart: () -> Void
    let onSlashQuery: (String?) -> Void
    let onTransform: (MarkdownBlockKind) -> Void
    let onHeightChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder

        let textView = BlockNSTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 2, height: 5)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.insertionPointColor = .controlAccentColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.setAccessibilityIdentifier("note.block.editor.\(index)")
        scrollView.documentView = textView
        scrollView.setAccessibilityIdentifier("note.block.editor.\(index)")

        context.coordinator.textView = textView
        context.coordinator.installKeyboardHandlers(on: textView)
        context.coordinator.applyExternalContent()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? BlockNSTextView else { return }
        textView.setAccessibilityIdentifier("note.block.editor.\(index)")
        scrollView.setAccessibilityIdentifier("note.block.editor.\(index)")
        context.coordinator.installKeyboardHandlers(on: textView)
        context.coordinator.applyExternalContent()
        context.coordinator.applyPendingCommands()
        context.coordinator.measureHeight()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownBlockTextView
        weak var textView: BlockNSTextView?
        private var applyingExternalContent = false
        private var lastContent: String?
        private var lastKind: MarkdownBlockKind?
        private var lastFocusToken: UUID?
        private var lastFormatToken: UUID?
        private var lastHeight: CGFloat = 0

        init(parent: MarkdownBlockTextView) {
            self.parent = parent
        }

        func installKeyboardHandlers(on textView: BlockNSTextView) {
            textView.onInlineStyle = { [weak self, weak textView] style in
                guard let self, let textView else { return }
                MarkdownInlineCodec.toggle(style, in: textView)
                self.measureHeight()
            }
            textView.onBlockShortcut = { [weak self] kind in self?.parent.onTransform(kind) }
        }

        func applyExternalContent() {
            guard let textView,
                  lastContent != parent.block.content || lastKind != parent.block.kind else { return }
            applyingExternalContent = true
            let selection = textView.selectedRange()
            textView.textStorage?.setAttributedString(Self.attributedContent(for: parent.block))
            textView.typingAttributes = Self.typingAttributes(for: parent.block.kind)
            textView.setSelectedRange(NSRange(location: min(selection.location, textView.string.utf16.count), length: 0))
            lastContent = parent.block.content
            lastKind = parent.block.kind
            applyingExternalContent = false
        }

        func applyPendingCommands() {
            if let request = parent.focusRequest,
               request.blockID == parent.block.id,
               request.token != lastFocusToken,
               let textView {
                lastFocusToken = request.token
                Task { @MainActor [weak textView] in
                    guard let textView else { return }
                    textView.window?.makeFirstResponder(textView)
                    let length = textView.string.utf16.count
                    let location: Int
                    switch request.placement {
                    case .start: location = 0
                    case .end: location = length
                    case .offset(let offset): location = min(max(0, offset), length)
                    }
                    textView.setSelectedRange(NSRange(location: location, length: 0))
                }
            }

            if let request = parent.formatRequest,
               request.blockID == parent.block.id,
               request.token != lastFormatToken,
               parent.block.kind != .code,
               let textView {
                lastFormatToken = request.token
                MarkdownInlineCodec.toggle(request.style, in: textView)
            }
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.onFocus()
        }

        func textDidChange(_ notification: Notification) {
            guard !applyingExternalContent, let textView else { return }
            let content = serializedContent(textView.attributedString())
            lastContent = content
            parent.onChange(content)
            let plain = textView.string
            if plain.hasPrefix("/"), !plain.contains("\n") {
                parent.onSlashQuery(String(plain.dropFirst()))
            } else {
                parent.onSlashQuery(nil)
            }
            measureHeight()
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                split(textView)
                return true
            }
            if commandSelector == #selector(NSResponder.deleteBackward(_:)),
               textView.selectedRange().location == 0,
               textView.selectedRange().length == 0 {
                parent.onBackspaceAtStart()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onSlashQuery(nil)
                return true
            }
            return false
        }

        func measureHeight() {
            guard let textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }
            layoutManager.ensureLayout(for: textContainer)
            let measured = ceil(layoutManager.usedRect(for: textContainer).height + textView.textContainerInset.height * 2)
            let height = max(parent.block.kind.minimumEditorHeight, measured)
            guard abs(height - lastHeight) > 0.5 else { return }
            lastHeight = height
            Task { @MainActor [parent] in parent.onHeightChange(height) }
        }

        private func split(_ textView: NSTextView) {
            let selection = textView.selectedRange()
            let attributed = textView.attributedString()
            let before = attributed.attributedSubstring(from: NSRange(location: 0, length: selection.location))
            let afterStart = selection.location + selection.length
            let after = attributed.attributedSubstring(
                from: NSRange(location: afterStart, length: max(0, attributed.length - afterStart))
            )
            parent.onSplit(serializedContent(before), serializedContent(after))
        }

        private func serializedContent(_ attributed: NSAttributedString) -> String {
            parent.block.kind == .code ? attributed.string : MarkdownInlineCodec.markdown(from: attributed)
        }

        private static func attributedContent(for block: MarkdownBlock) -> NSAttributedString {
            let attributed: NSMutableAttributedString
            if block.kind == .code {
                attributed = NSMutableAttributedString(
                    string: block.content,
                    attributes: [.font: block.kind.editorFont, .foregroundColor: NSColor.labelColor]
                )
            } else {
                attributed = MarkdownInlineCodec.attributedString(from: block.content, baseFont: block.kind.editorFont)
                    .mutableCopy() as! NSMutableAttributedString
            }
            let style = NSMutableParagraphStyle()
            style.lineSpacing = block.kind == .code ? 3 : 5
            style.paragraphSpacing = 0
            if block.kind == .quote {
                style.headIndent = 5
                style.firstLineHeadIndent = 5
            }
            if attributed.length > 0 {
                attributed.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: attributed.length))
            }
            return attributed
        }

        private static func typingAttributes(for kind: MarkdownBlockKind) -> [NSAttributedString.Key: Any] {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = kind == .code ? 3 : 5
            return [.font: kind.editorFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: style]
        }
    }
}

@MainActor
final class BlockNSTextView: NSTextView {
    var onInlineStyle: ((MarkdownInlineStyle) -> Void)?
    var onBlockShortcut: ((MarkdownBlockKind) -> Void)?

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased()
        if modifiers == .command, key == "b" { onInlineStyle?(.bold); return }
        if modifiers == .command, key == "i" { onInlineStyle?(.italic); return }
        if modifiers == [.command, .shift], key == "x" { onInlineStyle?(.strikethrough); return }
        if modifiers == [.command, .shift], key == "c" { onInlineStyle?(.code); return }
        if modifiers == [.command, .option] {
            let kind: MarkdownBlockKind?
            switch key {
            case "0": kind = .paragraph
            case "1": kind = .heading1
            case "2": kind = .heading2
            case "3": kind = .heading3
            default: kind = nil
            }
            if let kind { onBlockShortcut?(kind); return }
        }
        super.keyDown(with: event)
    }

    override func paste(_ sender: Any?) {
        guard let plain = NSPasteboard.general.string(forType: .string) else {
            super.paste(sender)
            return
        }
        insertText(plain, replacementRange: selectedRange())
    }
}
