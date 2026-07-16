import AppKit
import XCTest
@testable import CueMe

final class MarkdownBlockDocumentTests: XCTestCase {
    func testParsesMarkdownIntoDurableVisualBlocks() {
        let markdown = """
        # Memória disponível

        Um parágrafo com **coragem** e *calma*.

        > Uma lembrança importante

        - Primeiro passo
        - [x] Decisão tomada
        1. Próxima ação

        ```swift
        let answer = 42
        ```

        ---
        """

        let document = MarkdownBlockDocument(markdown: markdown)

        XCTAssertEqual(
            document.blocks.map(\.kind),
            [.heading1, .paragraph, .quote, .bullet, .checklistChecked, .numbered, .code, .divider]
        )
        XCTAssertEqual(document.blocks[0].content, "Memória disponível")
        XCTAssertEqual(document.blocks[4].content, "Decisão tomada")
        XCTAssertEqual(document.blocks[6].content, "let answer = 42")
        XCTAssertEqual(document.blocks[6].language, "swift")
        XCTAssertEqual(document.markdown, markdown)
    }

    func testBlockOperationsKeepMarkdownAsTheCanonicalResult() {
        var document = MarkdownBlockDocument(markdown: "Primeiro bloco")
        let firstID = try! XCTUnwrap(document.blocks.first?.id)

        let secondID = document.split(firstID, before: "Primeiro", after: "bloco")
        document.transform(secondID, to: .heading2)
        document.insert(.init(kind: .checklistUnchecked, content: "Revisar"), after: secondID)
        document.toggleChecklist(document.blocks[2].id)

        XCTAssertEqual(document.markdown, "Primeiro\n\n## bloco\n\n- [x] Revisar")

        document.move(document.blocks[2].id, before: firstID)
        XCTAssertEqual(document.markdown, "- [x] Revisar\n\nPrimeiro\n\n## bloco")
    }

    func testInlineFormattingRoundTripsWithoutShowingMarkdownTokens() {
        let source = "Texto **forte**, *humano*, ~~antigo~~, `código` e [fonte](https://example.com)."

        let attributed = MarkdownInlineCodec.attributedString(
            from: source,
            baseFont: .systemFont(ofSize: 17)
        )

        XCTAssertEqual(attributed.string, "Texto forte, humano, antigo, código e fonte.")
        XCTAssertEqual(MarkdownInlineCodec.markdown(from: attributed), source)
    }

    func testLiteralMarkdownCharactersAreEscapedWhenTypedVisually() {
        let attributed = NSAttributedString(
            string: "2 * 3 e [rascunho]",
            attributes: [.font: NSFont.systemFont(ofSize: 17)]
        )

        let markdown = MarkdownInlineCodec.markdown(from: attributed)

        XCTAssertEqual(markdown, "2 \\* 3 e \\[rascunho\\]")
        XCTAssertEqual(
            MarkdownInlineCodec.attributedString(from: markdown, baseFont: .systemFont(ofSize: 17)).string,
            attributed.string
        )
    }

    @MainActor
    func testInlineToolbarToggleProducesMarkdownWithoutMutatingDuringEnumeration() {
        let textView = NSTextView()
        textView.textStorage?.setAttributedString(
            NSAttributedString(
                string: "Memória forte",
                attributes: [.font: NSFont.systemFont(ofSize: 17)]
            )
        )
        textView.setSelectedRange(NSRange(location: 0, length: 7))

        MarkdownInlineCodec.toggle(.bold, in: textView)

        XCTAssertEqual(
            MarkdownInlineCodec.markdown(from: try! XCTUnwrap(textView.textStorage)),
            "**Memória** forte"
        )
    }
}
