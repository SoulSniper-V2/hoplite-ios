import SwiftUI

/// Renders the subset of Markdown agents actually write: headings, paragraphs, lists,
/// fenced code, quotes and pipe tables, with inline code, emphasis and links.
struct MarkdownView: View {
    let text: String
    var baseFont: Font = .hpBody
    var color: Color = HP.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(MarkdownBlock.parse(text).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let content):
            Text(Self.inline(content))
                .font(level <= 1 ? .display(22, weight: .medium) : level == 2 ? .display(19, weight: .medium) : .ui(16.5, weight: .semibold))
                .foregroundStyle(color)
                .padding(.top, 4)
        case .paragraph(let content):
            Text(Self.inline(content))
                .font(baseFont)
                .foregroundStyle(color)
                .lineSpacing(4)
                .textSelection(.enabled)
        case .list(let items, let ordered):
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(ordered ? "\(index + 1)." : "•")
                            .font(ordered ? .mono(13.5, weight: .medium) : baseFont)
                            .foregroundStyle(HP.ink3)
                            .frame(minWidth: 14, alignment: .trailing)
                        Text(Self.inline(item)).font(baseFont).foregroundStyle(color).lineSpacing(4)
                    }
                }
            }
        case .code(let language, let code):
            CodeBlock(language: language, code: code)
        case .quote(let content):
            HStack(spacing: 12) {
                Capsule().fill(HP.action.opacity(0.7)).frame(width: 3)
                Text(Self.inline(content)).font(baseFont).foregroundStyle(HP.ink2)
            }
        case .table(let rows):
            TableBlock(rows: rows)
        }
    }

    static func inline(_ source: String) -> AttributedString {
        var attributed = (try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(source)
        for run in attributed.runs {
            guard let intent = run.inlinePresentationIntent else { continue }
            if intent.contains(.code) {
                attributed[run.range].font = .mono(13.5, relativeTo: .body)
                attributed[run.range].foregroundColor = HP.codeInk
                attributed[run.range].backgroundColor = HP.control.opacity(0.55)
            }
        }
        for run in attributed.runs where run.link != nil {
            attributed[run.range].foregroundColor = HP.actionBright
            attributed[run.range].underlineStyle = .single
        }
        return attributed
    }
}

struct CodeBlock: View {
    let language: String?
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Eyebrow(text: language?.isEmpty == false ? language! : "code")
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(HP.ink2)
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel("Copy code")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            Divider().overlay(HP.hairline)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.mono(13))
                    .foregroundStyle(HP.ink)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .padding(14)
            }
        }
        .background(HP.inset, in: .rect(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(HP.hairline))
    }
}

private struct TableBlock: View {
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 9) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(MarkdownView.inline(cell))
                                .font(index == 0 ? .ui(13, weight: .semibold) : .hpSubhead)
                                .foregroundStyle(index == 0 ? HP.ink2 : HP.ink)
                        }
                    }
                    if index == 0 { Divider().overlay(HP.hairlineStrong).gridCellUnsizedAxes(.horizontal) }
                }
            }
            .padding(14)
        }
        .hpCard(radius: 16, fill: HP.inset)
    }
}

enum MarkdownBlock: Equatable {
    case heading(Int, String)
    case paragraph(String)
    case list([String], ordered: Bool)
    case code(String?, String)
    case quote(String)
    case table([[String]])

    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var list: [String] = []
        var ordered = false
        var lines = text.components(separatedBy: "\n")[...]

        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))); paragraph = [] }
        }
        func flushList() {
            if !list.isEmpty { blocks.append(.list(list, ordered: ordered)); list = [] }
        }

        while let line = lines.popFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                flushParagraph(); flushList()
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                while let next = lines.popFirst(), !next.trimmingCharacters(in: .whitespaces).hasPrefix("```") { code.append(next) }
                blocks.append(.code(language.isEmpty ? nil : language, code.joined(separator: "\n")))
            } else if trimmed.isEmpty {
                flushParagraph(); flushList()
            } else if let level = trimmed.headingLevel {
                flushParagraph(); flushList()
                blocks.append(.heading(level, String(trimmed.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces)))
            } else if trimmed.hasPrefix("|") {
                flushParagraph(); flushList()
                var rows = [trimmed.tableCells]
                while let next = lines.first?.trimmingCharacters(in: .whitespaces), next.hasPrefix("|") {
                    lines.removeFirst()
                    if next.replacingOccurrences(of: "[|:\\- ]", with: "", options: .regularExpression).isEmpty { continue }
                    rows.append(next.tableCells)
                }
                blocks.append(.table(rows))
            } else if trimmed.hasPrefix("> ") {
                flushParagraph(); flushList()
                blocks.append(.quote(String(trimmed.dropFirst(2))))
            } else if let item = trimmed.bulletItem {
                flushParagraph()
                if !list.isEmpty && ordered { flushList() }
                ordered = false
                list.append(item)
            } else if let item = trimmed.orderedItem {
                flushParagraph()
                if !list.isEmpty && !ordered { flushList() }
                ordered = true
                list.append(item)
            } else if !list.isEmpty && line.hasPrefix("  ") {
                list[list.count - 1] += " " + trimmed
            } else {
                flushList()
                paragraph.append(line)
            }
        }
        flushParagraph(); flushList()
        return blocks
    }
}

private extension String {
    var headingLevel: Int? {
        let hashes = prefix { $0 == "#" }.count
        return (1...4).contains(hashes) && dropFirst(hashes).first == " " ? hashes : nil
    }

    var bulletItem: String? {
        for marker in ["- ", "* ", "• "] where hasPrefix(marker) { return String(dropFirst(2)) }
        return nil
    }

    var orderedItem: String? {
        guard let dot = firstIndex(of: "."), dot != startIndex, self[..<dot].allSatisfy(\.isNumber), index(after: dot) < endIndex, self[index(after: dot)] == " " else { return nil }
        return String(self[index(dot, offsetBy: 2)...])
    }

    var tableCells: [String] {
        split(separator: "|", omittingEmptySubsequences: false).dropFirst().dropLast().map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
