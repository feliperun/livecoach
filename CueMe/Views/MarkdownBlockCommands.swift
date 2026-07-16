import AppKit
import SwiftUI

struct MarkdownBlockCommand: Identifiable {
    enum Group: String, CaseIterable {
        case headings = "Títulos"
        case basic = "Blocos básicos"
    }

    let kind: MarkdownBlockKind
    let title: String
    let detail: String
    let icon: String
    let group: Group
    let keywords: String

    var id: String { kind.rawValue }

    static let all: [Self] = [
        .init(kind: .heading1, title: "Título 1", detail: "Título principal", icon: "textformat.size.larger", group: .headings, keywords: "h1 heading titulo cabeçalho"),
        .init(kind: .heading2, title: "Título 2", detail: "Seção", icon: "textformat.size", group: .headings, keywords: "h2 heading titulo seção"),
        .init(kind: .heading3, title: "Título 3", detail: "Subseção", icon: "textformat.size.smaller", group: .headings, keywords: "h3 heading titulo subseção"),
        .init(kind: .paragraph, title: "Texto", detail: "Parágrafo simples", icon: "paragraph", group: .basic, keywords: "texto paragraph normal"),
        .init(kind: .quote, title: "Citação", detail: "Destaque uma ideia", icon: "quote.opening", group: .basic, keywords: "quote citação destaque"),
        .init(kind: .bullet, title: "Lista", detail: "Lista com marcadores", icon: "list.bullet", group: .basic, keywords: "bullet lista marcador"),
        .init(kind: .numbered, title: "Lista numerada", detail: "Passos em ordem", icon: "list.number", group: .basic, keywords: "numbered lista numerada passos"),
        .init(kind: .checklistUnchecked, title: "Checklist", detail: "Item marcável", icon: "checklist", group: .basic, keywords: "todo tarefa checkbox checklist"),
        .init(kind: .code, title: "Código", detail: "Bloco monoespaçado", icon: "chevron.left.forwardslash.chevron.right", group: .basic, keywords: "code codigo bloco"),
        .init(kind: .divider, title: "Divisor", detail: "Separe assuntos", icon: "minus", group: .basic, keywords: "divider divisor linha separador")
    ]

    static func matching(_ query: String) -> [Self] {
        let normalized = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else { return all }
        return all.filter { command in
            "\(command.title) \(command.detail) \(command.keywords)"
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .contains(normalized)
        }
    }
}

struct MarkdownBlockCommandMenu: View {
    let query: String
    let onSelect: (MarkdownBlockKind) -> Void

    private var commands: [MarkdownBlockCommand] { MarkdownBlockCommand.matching(query) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 5) {
                if commands.isEmpty {
                    ContentUnavailableView(
                        "Nenhum bloco encontrado",
                        systemImage: "text.magnifyingglass",
                        description: Text("Tente outro nome.")
                    )
                    .frame(width: 280, height: 150)
                } else {
                    ForEach(MarkdownBlockCommand.Group.allCases, id: \.self) { group in
                        let grouped = commands.filter { $0.group == group }
                        if !grouped.isEmpty {
                            Text(group.rawValue.uppercased())
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 10)
                                .padding(.top, 8)
                            ForEach(grouped) { command in
                                commandButton(command)
                            }
                        }
                    }
                }
            }
            .padding(7)
        }
        .frame(width: 310)
        .frame(maxHeight: 420)
        .background(Theme.panelRaised)
        .accessibilityIdentifier("note.block.command-menu")
    }

    private func commandButton(_ command: MarkdownBlockCommand) -> some View {
        Button {
            onSelect(command.kind)
        } label: {
            HStack(spacing: 11) {
                Image(systemName: command.icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 25)
                    .foregroundStyle(Theme.violet)
                VStack(alignment: .leading, spacing: 2) {
                    Text(command.title)
                        .font(.system(size: 12.5, weight: .semibold))
                    Text(command.detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 10)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Theme.interactive.opacity(0.001), in: RoundedRectangle(cornerRadius: 7))
        .accessibilityIdentifier("note.block.command.\(command.kind.rawValue)")
    }
}

extension MarkdownBlockKind {
    var editorFont: NSFont {
        switch self {
        case .heading1: .systemFont(ofSize: 30, weight: .bold)
        case .heading2: .systemFont(ofSize: 24, weight: .bold)
        case .heading3: .systemFont(ofSize: 20, weight: .semibold)
        case .code: .monospacedSystemFont(ofSize: 14.5, weight: .regular)
        case .quote: NSFont(name: "New York", size: 17.5) ?? .systemFont(ofSize: 17.5)
        default: NSFont(name: "New York", size: 17.5) ?? .systemFont(ofSize: 17.5)
        }
    }

    var minimumEditorHeight: CGFloat {
        switch self {
        case .heading1: 48
        case .heading2: 41
        case .heading3: 36
        case .code: 68
        case .divider: 26
        default: 33
        }
    }

    var placeholder: String {
        switch self {
        case .heading1, .heading2, .heading3: "Título"
        case .quote: "Citação"
        case .code: "Digite ou cole código"
        default: "Digite / para inserir um bloco"
        }
    }
}
