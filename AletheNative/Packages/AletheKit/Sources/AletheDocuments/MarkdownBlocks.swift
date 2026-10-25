import Foundation
import Markdown

public indirect enum MarkdownBlock: Hashable, Sendable {
    case heading(level: Int, text: AttributedString)
    case paragraph(AttributedString)
    case image(source: URL?, alt: String)
    case code(language: String?, code: String)
    case quote([MarkdownBlock])
    case list(ordered: Bool, start: Int, items: [MarkdownListItem])
    case table(header: [AttributedString], alignments: [MarkdownColumnAlignment], rows: [[AttributedString]])
    case rule
    case html(String)
}

public struct MarkdownListItem: Hashable, Sendable {
    public var checkbox: Bool?
    public var blocks: [MarkdownBlock]
}

public enum MarkdownColumnAlignment: Hashable, Sendable {
    case leading, center, trailing
}

public enum MarkdownBlocks {
    public static func parse(_ text: String, base: URL? = nil) -> [MarkdownBlock] {
        let document = Document(parsing: text)
        let converter = Converter(base: base)
        return document.children.compactMap { converter.block($0) }
    }

    static func resolve(_ destination: String?, base: URL?) -> URL? {
        guard let destination = destination?.trimmingCharacters(in: .whitespaces), !destination.isEmpty,
              !destination.hasPrefix("#") else { return nil }
        if let url = URL(string: destination), url.scheme != nil { return url }
        let path = destination.removingPercentEncoding ?? destination
        if path.hasPrefix("/") { return URL(filePath: path) }
        guard let base else { return URL(string: destination) }
        let withoutFragment = path.split(separator: "#", maxSplits: 1).first.map(String.init) ?? path
        return base.appending(path: withoutFragment).standardizedFileURL
    }
}

private struct Converter {
    let base: URL?

    func block(_ markup: Markup) -> MarkdownBlock? {
        if let heading = markup as? Heading { return .heading(level: heading.level, text: inlines(heading.children)) }
        else if let paragraph = markup as? Paragraph {
            let children = Array(paragraph.children)
            if children.count == 1,
                let image = children.first as? Markdown.Image { return .image(source: MarkdownBlocks.resolve(image.source, base: base),
                alt: image.plainText) }
            return .paragraph(inlines(children))
        } else if let code = markup as? CodeBlock {
            let language = code.language.flatMap { $0.isEmpty ? nil : $0 }
            return .code(language: language, code: code.code.hasSuffix("\n") ? String(code.code.dropLast()) : code.code)
        } else if let quote = markup as? BlockQuote {
            return .quote(quote.children.compactMap { block($0) })
        }
        else if let list = markup as? OrderedList { return .list(ordered: true, start: Int(list.startIndex), items: items(list.children)) }
        else if let list = markup as? UnorderedList { return .list(ordered: false, start: 1, items: items(list.children)) }
        else if let table = markup as? Markdown.Table {
            let alignments = table.columnAlignments.map { alignment -> MarkdownColumnAlignment in
                if case .center = alignment { return .center } else if case .right = alignment { return .trailing } else { return .leading }
            }
            let header = Array(table.head.cells.map { inlines($0.children) })
            let rows = Array(table.body.rows.map { row in Array(row.cells.map { inlines($0.children) }) })
            let width = max(header.count, rows.map(\.count).max() ?? 0)
            return .table(header: pad(header, to: width),
                          alignments: alignments + Array(repeating: .leading, count: max(0, width - alignments.count)),
                          rows: rows.map { pad($0, to: width) })
        }
        else if markup is ThematicBreak { return .rule }
        else if let html = markup as? HTMLBlock { return .html(html.rawHTML.trimmingCharacters(in: .newlines)) }
        else { return nil }
    }

    private func pad(_ cells: [AttributedString], to width: Int) -> [AttributedString] {
        cells + Array(repeating: AttributedString(), count: max(0, width - cells.count))
    }

    private func items(_ children: some Sequence<Markup>) -> [MarkdownListItem] {
        children.compactMap { child -> MarkdownListItem? in
            guard let item = child as? ListItem else { return nil }
            let checkbox: Bool? = item.checkbox.map { $0 == .checked }
            return MarkdownListItem(checkbox: checkbox, blocks: item.children.compactMap { block($0) })
        }
    }

    func inlines(_ children: some Sequence<Markup>) -> AttributedString {
        var result = AttributedString()
        for child in children { result += inline(child, intent: []) }
        return result
    }

    private func inline(_ markup: Markup, intent: InlinePresentationIntent) -> AttributedString {
        func styled(_ string: String, _ extra: InlinePresentationIntent = []) -> AttributedString {
            var text = AttributedString(string)
            let combined = intent.union(extra)
            if !combined.isEmpty { text.inlinePresentationIntent = combined }
            return text
        }
        func nested(_ children: some Sequence<Markup>, _ extra: InlinePresentationIntent) -> AttributedString {
            var result = AttributedString()
            for child in children { result += inline(child, intent: intent.union(extra)) }
            return result
        }
        if let text = markup as? Markdown.Text { return styled(text.string) }
        else if let emphasis = markup as? Emphasis { return nested(emphasis.children, .emphasized) }
        else if let strong = markup as? Strong { return nested(strong.children, .stronglyEmphasized) }
        else if let strike = markup as? Strikethrough { return nested(strike.children, .strikethrough) }
        else if let code = markup as? InlineCode { return styled(code.code, .code) }
        else if let link = markup as? Markdown.Link {
            var text = nested(link.children, [])
            if let url = MarkdownBlocks.resolve(link.destination, base: base) { text.link = url }
            return text
        } else if let image = markup as? Markdown.Image {
            var text = styled(image.plainText.isEmpty ? (image.source ?? "") : image.plainText)
            if let url = MarkdownBlocks.resolve(image.source, base: base) { text.link = url }
            return text
        }
        else if markup is SoftBreak { return styled(" ") }
        else if markup is LineBreak { return styled("\n") }
        else if let html = markup as? InlineHTML { return styled(html.rawHTML, .code) }
        else if let symbol = markup as? SymbolLink { return styled(symbol.destination ?? "", .code) }
        else {
            if let container = markup as? InlineContainer { return nested(container.children, []) }
            return styled(markup.format())
        }
    }
}
