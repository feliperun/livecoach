import AppKit

extension NSAttributedString.Key {
    static let cueMeBold = NSAttributedString.Key("run.cueme.markdown.bold")
    static let cueMeItalic = NSAttributedString.Key("run.cueme.markdown.italic")
    static let cueMeStrikethrough = NSAttributedString.Key("run.cueme.markdown.strikethrough")
    static let cueMeInlineCode = NSAttributedString.Key("run.cueme.markdown.inline-code")
}

enum MarkdownInlineStyle: Hashable {
    case bold
    case italic
    case strikethrough
    case code
}

enum MarkdownInlineCodec {
    static func attributedString(from markdown: String, baseFont: NSFont) -> NSAttributedString {
        Parser(markdown: markdown, baseFont: baseFont).parse()
    }

    static func markdown(from attributed: NSAttributedString) -> String {
        guard attributed.length > 0 else { return "" }
        var runs: [(signature: Signature, text: String)] = []
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, range, _ in
            let signature = Signature(attributes: attributes)
            let text = (attributed.string as NSString).substring(with: range)
            if runs.last?.signature == signature {
                runs[runs.count - 1].text += text
            } else {
                runs.append((signature, text))
            }
        }
        return runs.map { serialize($0.text, signature: $0.signature) }.joined()
    }

    @MainActor
    static func toggle(_ style: MarkdownInlineStyle, in textView: NSTextView) {
        let range = textView.selectedRange()
        let key = key(for: style)
        if range.length == 0 {
            var attributes = textView.typingAttributes
            if (attributes[key] as? Bool) == true {
                attributes.removeValue(forKey: key)
            } else {
                attributes[key] = true
            }
            attributes[.font] = styledFont(from: attributes, fallback: textView.font ?? .systemFont(ofSize: 17))
            applyDecorationAttributes(&attributes)
            textView.typingAttributes = attributes
            return
        }

        let storage = textView.textStorage!
        var shouldEnable = false
        storage.enumerateAttribute(key, in: range) { value, _, stop in
            if (value as? Bool) != true {
                shouldEnable = true
                stop.pointee = true
            }
        }
        storage.beginEditing()
        if shouldEnable {
            storage.addAttribute(key, value: true, range: range)
        } else {
            storage.removeAttribute(key, range: range)
        }
        var runs: [([NSAttributedString.Key: Any], NSRange)] = []
        storage.enumerateAttributes(in: range) { attributes, runRange, _ in
            runs.append((attributes, runRange))
        }
        for (attributes, runRange) in runs {
            var updated = attributes
            updated[.font] = styledFont(from: updated, fallback: textView.font ?? .systemFont(ofSize: 17))
            applyDecorationAttributes(&updated)
            storage.setAttributes(updated, range: runRange)
        }
        storage.endEditing()
        textView.didChangeText()
    }

    private struct Signature: Equatable {
        let bold: Bool
        let italic: Bool
        let strikethrough: Bool
        let code: Bool
        let link: String?

        init(attributes: [NSAttributedString.Key: Any]) {
            bold = attributes[.cueMeBold] as? Bool == true
            italic = attributes[.cueMeItalic] as? Bool == true
            strikethrough = attributes[.cueMeStrikethrough] as? Bool == true
            code = attributes[.cueMeInlineCode] as? Bool == true
            if let url = attributes[.link] as? URL { link = url.absoluteString }
            else { link = attributes[.link] as? String }
        }
    }

    private static func serialize(_ raw: String, signature: Signature) -> String {
        if signature.code {
            let fence = raw.contains("`") ? "``" : "`"
            return "\(fence)\(raw)\(fence)"
        }
        var value = escape(raw)
        if signature.bold { value = "**\(value)**" }
        if signature.italic { value = "*\(value)*" }
        if signature.strikethrough { value = "~~\(value)~~" }
        if let link = signature.link { value = "[\(value)](\(link))" }
        return value
    }

    private static func escape(_ value: String) -> String {
        var result = ""
        for character in value {
            if "\\*_~`[]".contains(character) { result.append("\\") }
            result.append(character)
        }
        return result
    }

    private static func key(for style: MarkdownInlineStyle) -> NSAttributedString.Key {
        switch style {
        case .bold: .cueMeBold
        case .italic: .cueMeItalic
        case .strikethrough: .cueMeStrikethrough
        case .code: .cueMeInlineCode
        }
    }

    private static func styledFont(from attributes: [NSAttributedString.Key: Any], fallback: NSFont) -> NSFont {
        if attributes[.cueMeInlineCode] as? Bool == true {
            return .monospacedSystemFont(ofSize: max(12, fallback.pointSize * 0.9), weight: .regular)
        }
        var font = fallback
        let manager = NSFontManager.shared
        if attributes[.cueMeBold] as? Bool == true { font = manager.convert(font, toHaveTrait: .boldFontMask) }
        if attributes[.cueMeItalic] as? Bool == true { font = manager.convert(font, toHaveTrait: .italicFontMask) }
        return font
    }

    private static func applyDecorationAttributes(_ attributes: inout [NSAttributedString.Key: Any]) {
        if attributes[.cueMeStrikethrough] as? Bool == true {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        } else {
            attributes.removeValue(forKey: .strikethroughStyle)
        }
        if attributes[.cueMeInlineCode] as? Bool == true {
            attributes[.backgroundColor] = NSColor.secondaryLabelColor.withAlphaComponent(0.12)
        } else {
            attributes.removeValue(forKey: .backgroundColor)
        }
    }

    private final class Parser {
        private struct Style {
            var bold = false
            var italic = false
            var strikethrough = false
            var code = false
            var link: String?
        }

        let markdown: String
        let baseFont: NSFont

        init(markdown: String, baseFont: NSFont) {
            self.markdown = markdown
            self.baseFont = baseFont
        }

        func parse() -> NSAttributedString {
            parse(markdown[markdown.startIndex..<markdown.endIndex], style: .init())
        }

        private func parse(_ source: Substring, style: Style) -> NSMutableAttributedString {
            let output = NSMutableAttributedString(string: "")
            var index = source.startIndex
            var literal = ""

            func flush() {
                guard !literal.isEmpty else { return }
                output.append(NSAttributedString(string: literal, attributes: attributes(for: style)))
                literal = ""
            }

            while index < source.endIndex {
                if source[index] == "\\" {
                    let next = source.index(after: index)
                    if next < source.endIndex {
                        literal.append(source[next])
                        index = source.index(after: next)
                        continue
                    }
                }

                if let token = delimitedToken(in: source, at: index, delimiter: "**") {
                    flush()
                    var nested = style
                    nested.bold = true
                    output.append(parse(token.content, style: nested))
                    index = token.end
                    continue
                }

                if let token = delimitedToken(in: source, at: index, delimiter: "~~") {
                    flush()
                    var nested = style
                    nested.strikethrough = true
                    output.append(parse(token.content, style: nested))
                    index = token.end
                    continue
                }

                if let token = delimitedToken(in: source, at: index, delimiter: "`") {
                    flush()
                    var nested = style
                    nested.code = true
                    output.append(NSAttributedString(string: String(token.content), attributes: attributes(for: nested)))
                    index = token.end
                    continue
                }

                if let link = linkToken(in: source, at: index) {
                    flush()
                    var nested = style
                    nested.link = String(link.url)
                    output.append(parse(link.label, style: nested))
                    index = link.end
                    continue
                }

                if let token = delimitedToken(in: source, at: index, delimiter: "*") {
                    flush()
                    var nested = style
                    nested.italic = true
                    output.append(parse(token.content, style: nested))
                    index = token.end
                    continue
                }

                literal.append(source[index])
                index = source.index(after: index)
            }
            flush()
            return output
        }

        private func attributes(for style: Style) -> [NSAttributedString.Key: Any] {
            var attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.labelColor,
                .font: baseFont
            ]
            if style.bold { attributes[.cueMeBold] = true }
            if style.italic { attributes[.cueMeItalic] = true }
            if style.strikethrough { attributes[.cueMeStrikethrough] = true }
            if style.code { attributes[.cueMeInlineCode] = true }
            if let link = style.link {
                attributes[.link] = link
                attributes[.foregroundColor] = NSColor.linkColor
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            attributes[.font] = MarkdownInlineCodec.styledFont(from: attributes, fallback: baseFont)
            MarkdownInlineCodec.applyDecorationAttributes(&attributes)
            return attributes
        }

        private func delimitedToken(
            in source: Substring,
            at index: String.Index,
            delimiter: String
        ) -> (content: Substring, end: String.Index)? {
            guard source[index...].hasPrefix(delimiter) else { return nil }
            let contentStart = source.index(index, offsetBy: delimiter.count)
            guard contentStart < source.endIndex,
                  let closing = source[contentStart...].range(of: delimiter) else { return nil }
            return (source[contentStart..<closing.lowerBound], closing.upperBound)
        }

        private func linkToken(
            in source: Substring,
            at index: String.Index
        ) -> (label: Substring, url: Substring, end: String.Index)? {
            guard source[index] == "[",
                  let labelEnd = source[index...].firstIndex(of: "]") else { return nil }
            let openParenthesis = source.index(after: labelEnd)
            guard openParenthesis < source.endIndex, source[openParenthesis] == "(" else { return nil }
            let urlStart = source.index(after: openParenthesis)
            guard let urlEnd = source[urlStart...].firstIndex(of: ")") else { return nil }
            return (
                source[source.index(after: index)..<labelEnd],
                source[urlStart..<urlEnd],
                source.index(after: urlEnd)
            )
        }
    }
}
