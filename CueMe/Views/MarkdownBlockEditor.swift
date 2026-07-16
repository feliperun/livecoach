import SwiftUI
import UniformTypeIdentifiers

struct MarkdownBlockEditor: View {
    @Binding var document: MarkdownBlockDocument
    @Binding var focusedBlockID: UUID?
    let formatRequest: MarkdownBlockFormatRequest?

    @State private var focusRequest: MarkdownBlockFocusRequest?
    @State private var menuContext: BlockMenuContext?
    @State private var hoveredBlockID: UUID?
    @State private var draggingBlockID: UUID?
    @State private var heights: [UUID: CGFloat] = [:]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(Array(document.blocks.enumerated()), id: \.element.id) { index, block in
                    blockRow(block, index: index)
                }
                Color.clear
                    .frame(height: 100)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let last = document.blocks.last {
                            requestFocus(last.id, placement: .end)
                        }
                    }
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding(.horizontal, 54)
            .padding(.vertical, 42)
        }
        .background(Theme.canvas)
        .accessibilityIdentifier("note.editor.blocks")
    }

    private func blockRow(_ block: MarkdownBlock, index: Int) -> some View {
        HStack(alignment: .top, spacing: 3) {
            blockHandles(block)
            blockDecoration(block, index: index)
            blockSurface(block, index: index)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovering in hoveredBlockID = hovering ? block.id : nil }
        .onDrop(
            of: [UTType.text],
            delegate: MarkdownBlockDropDelegate(
                destinationID: block.id,
                document: $document,
                draggingID: $draggingBlockID
            )
        )
        .popover(isPresented: menuBinding(for: block.id), arrowEdge: .leading) {
            MarkdownBlockCommandMenu(query: menuContext?.query ?? "") { kind in
                applyCommand(kind, context: menuContext)
            }
        }
        .contextMenu {
            Button("Duplicar bloco", systemImage: "plus.square.on.square") { duplicate(block) }
            Button("Excluir bloco", systemImage: "trash", role: .destructive) { document.remove(block.id) }
        }
    }

    private func blockHandles(_ block: MarkdownBlock) -> some View {
        HStack(spacing: 1) {
            Button {
                menuContext = .init(blockID: block.id, query: "", mode: .insertAfter)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 18, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Adicionar bloco")
            .accessibilityIdentifier("note.block.add.\(block.id.uuidString)")

            Image(systemName: "circle.grid.2x3.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
                .frame(width: 15, height: 24)
                .contentShape(Rectangle())
                .onDrag {
                    draggingBlockID = block.id
                    return NSItemProvider(object: block.id.uuidString as NSString)
                }
                .accessibilityLabel("Reordenar bloco")
        }
        .foregroundStyle(.secondary)
        .opacity(hoveredBlockID == block.id || focusedBlockID == block.id ? 1 : 0.12)
        .padding(.top, 5)
        .frame(width: 36)
    }

    @ViewBuilder
    private func blockDecoration(_ block: MarkdownBlock, index: Int) -> some View {
        Group {
            switch block.kind {
            case .bullet:
                Circle().fill(Color.primary.opacity(0.72)).frame(width: 5.5, height: 5.5).padding(.top, 16)
            case .numbered:
                Text("\(numberedOrdinal(at: index)).")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            case .checklistUnchecked, .checklistChecked:
                Button { document.toggleChecklist(block.id) } label: {
                    Image(systemName: block.kind == .checklistChecked ? "checkmark.square.fill" : "square")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(block.kind == .checklistChecked ? Theme.violet : Color.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .accessibilityIdentifier("note.block.check.\(block.id.uuidString)")
            case .quote:
                RoundedRectangle(cornerRadius: 2).fill(Theme.violet).frame(width: 3).padding(.vertical, 5)
            default:
                Color.clear.frame(width: 1, height: 1)
            }
        }
        .frame(width: 22, alignment: .center)
    }

    @ViewBuilder
    private func blockSurface(_ block: MarkdownBlock, index: Int) -> some View {
        if block.kind == .divider {
            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)
                .padding(.vertical, 13)
                .onTapGesture { menuContext = .init(blockID: block.id, query: "", mode: .transform) }
                .accessibilityIdentifier("note.block.divider.\(index)")
        } else {
            ZStack(alignment: .topLeading) {
                if block.content.isEmpty {
                    Text(block.kind.placeholder)
                        .font(Font(block.kind.editorFont))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 4)
                        .padding(.top, 7)
                        .allowsHitTesting(false)
                }
                MarkdownBlockTextView(
                    block: block,
                    index: index,
                    focusRequest: focusRequest,
                    formatRequest: formatRequest,
                    onChange: { document.update(block.id, content: $0) },
                    onFocus: {
                        focusedBlockID = block.id
                        if menuContext?.blockID != block.id { menuContext = nil }
                    },
                    onSplit: { split(block, before: $0, after: $1) },
                    onBackspaceAtStart: { mergeOrTransform(block) },
                    onSlashQuery: { updateSlashMenu(for: block.id, query: $0) },
                    onTransform: { transform(block.id, to: $0) },
                    onHeightChange: { heights[block.id] = $0 }
                )
                .frame(height: heights[block.id] ?? block.kind.minimumEditorHeight)
            }
            .padding(.horizontal, block.kind == .code ? 12 : 0)
            .padding(.vertical, block.kind == .code ? 7 : 0)
            .background {
                if block.kind == .code {
                    RoundedRectangle(cornerRadius: 10).fill(Theme.panelRaised)
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.divider))
                }
            }
            .opacity(block.kind == .checklistChecked ? 0.58 : 1)
        }
    }

    private func split(_ block: MarkdownBlock, before: String, after: String) {
        menuContext = nil
        if before.isEmpty, after.isEmpty, block.kind != .paragraph {
            document.transform(block.id, to: .paragraph)
            requestFocus(block.id, placement: .start)
            return
        }
        let nextID = document.split(block.id, before: before, after: after)
        requestFocus(nextID, placement: .start)
    }

    private func mergeOrTransform(_ block: MarkdownBlock) {
        guard let index = document.blocks.firstIndex(where: { $0.id == block.id }) else { return }
        if index == 0 {
            if block.kind != .paragraph { transform(block.id, to: .paragraph) }
            return
        }
        let previous = document.blocks[index - 1]
        if previous.kind == .divider {
            document.remove(previous.id)
            requestFocus(block.id, placement: .start)
            return
        }
        let offset = visibleLength(of: previous)
        guard let previousID = document.mergeIntoPrevious(block.id) else { return }
        requestFocus(previousID, placement: .offset(offset))
    }

    private func transform(_ id: UUID, to kind: MarkdownBlockKind) {
        document.transform(id, to: kind)
        if kind == .divider {
            let next = MarkdownBlock()
            document.insert(next, after: id)
            requestFocus(next.id, placement: .start)
        } else {
            requestFocus(id, placement: .end)
        }
    }

    private func applyCommand(_ kind: MarkdownBlockKind, context: BlockMenuContext?) {
        guard let context else { return }
        menuContext = nil
        switch context.mode {
        case .transform:
            document.update(context.blockID, content: "")
            transform(context.blockID, to: kind)
        case .insertAfter:
            let inserted = MarkdownBlock(kind: kind)
            document.insert(inserted, after: context.blockID)
            if kind == .divider {
                let next = MarkdownBlock()
                document.insert(next, after: inserted.id)
                requestFocus(next.id, placement: .start)
            } else {
                requestFocus(inserted.id, placement: .start)
            }
        }
    }

    private func duplicate(_ block: MarkdownBlock) {
        let copy = MarkdownBlock(kind: block.kind, content: block.content, language: block.language)
        document.insert(copy, after: block.id)
        requestFocus(copy.id, placement: .end)
    }

    private func updateSlashMenu(for id: UUID, query: String?) {
        if let query {
            menuContext = .init(blockID: id, query: query, mode: .transform)
        } else if menuContext?.blockID == id, menuContext?.mode == .transform {
            menuContext = nil
        }
    }

    private func menuBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { menuContext?.blockID == id },
            set: { if !$0, menuContext?.blockID == id { menuContext = nil } }
        )
    }

    private func requestFocus(_ id: UUID, placement: MarkdownBlockFocusRequest.Placement) {
        focusedBlockID = id
        focusRequest = .init(blockID: id, placement: placement)
    }

    private func visibleLength(of block: MarkdownBlock) -> Int {
        if block.kind == .code { return block.content.utf16.count }
        return MarkdownInlineCodec.attributedString(from: block.content, baseFont: block.kind.editorFont).length
    }

    private func numberedOrdinal(at index: Int) -> Int {
        var result = 1
        var cursor = index - 1
        while cursor >= 0, document.blocks[cursor].kind == .numbered {
            result += 1
            cursor -= 1
        }
        return result
    }
}

private struct BlockMenuContext: Equatable {
    enum Mode: Equatable { case transform, insertAfter }
    let blockID: UUID
    let query: String
    let mode: Mode
}

private struct MarkdownBlockDropDelegate: DropDelegate {
    let destinationID: UUID
    @Binding var document: MarkdownBlockDocument
    @Binding var draggingID: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggingID, draggingID != destinationID else { return }
        document.move(draggingID, before: destinationID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }
}
