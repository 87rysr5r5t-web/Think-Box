import AppKit
import PDFKit
import WritingLibrary

struct PageMetadata: Equatable, Sendable {
    let title: String
    let date: Date
    let library: String
    let group: String
    let author: String

    func expand(_ template: String, number: Int, total: Int) -> String {
        let fields = ["titulo": title, "pagina": String(number), "paginas": String(total),
                      "fecha": date.formatted(date: .abbreviated, time: .omitted),
                      "base": library, "grupo": group, "autor": author]
        return template.replacing(/\{[a-z]+\}/) { match in
            fields[String(match.output.dropFirst().dropLast())] ?? String(match.output)
        }
    }
}

struct MarkdownPageInput: Equatable, Sendable {
    let source: String
    let plain: Bool
    let layout: WritingPageLayout
    let metadata: PageMetadata
    let dark: Bool
    var richTextData: Data? = nil
    var imageRoots: [URL] = []
    var continuousWidth: CGFloat? = nil
}

struct MarkdownPages: Sendable {
    let data: Data
    let starts: [Int]

    func page(at offset: Int) -> Int {
        var lower = 0
        var upper = starts.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if starts[middle] <= offset { lower = middle + 1 } else { upper = middle }
        }
        return max(0, lower - 1)
    }
}

enum MarkdownPagination {
    private static let headingAttribute = NSAttributedString.Key("ThinkBox.markdownHeading")

    private struct Section {
        let text: NSAttributedString
        // Offsets refer to the source, including Markdown punctuation.
        let offsets: [(source: Int, rendered: Int)]
        let start: Int

        func sourceOffset(for rendered: Int) -> Int {
            var lower = 0
            var upper = offsets.count
            while lower < upper {
                let middle = (lower + upper) / 2
                if offsets[middle].rendered <= rendered { lower = middle + 1 } else { upper = middle }
            }
            guard lower > 0 else { return start }
            let line = offsets[lower - 1]
            return line.source + rendered - line.rendered
        }
    }

    private struct DrawnPage {
        let manager: NSLayoutManager
        let columns: [(range: NSRange, origin: CGPoint)]
        let start: Int
        let notes: DrawnNotes?
    }

    private struct DrawnNotes {
        let storage: NSTextStorage
        let manager: NSLayoutManager
        let range: NSRange
        let origin: CGPoint
    }

    private struct Notes {
        var definitions: [String: String]
        var numbers: [String: Int] = [:]

        mutating func replaceReferences(in text: NSMutableAttributedString) {
            guard !definitions.isEmpty else { return }
            let value = text.string
            let references = value.matches(of: /\[\^([^\]\s]+)\]/)
            var replacements: [(NSRange, String, Int)] = []
            for reference in references {
                let key = reference.1.lowercased()
                guard definitions[key] != nil else { continue }
                let number = numbers[key] ?? numbers.count + 1
                numbers[key] = number
                replacements.append((NSRange(reference.range, in: value), key, number))
            }
            for (range, key, number) in replacements.reversed() {
                let attributes = text.attributes(at: range.location, effectiveRange: nil)
                let raised = NSMutableAttributedString(string: String(number), attributes: attributes)
                raised.addAttributes([MarkdownBlocks.noteReference: key, .superscript: 1],
                                     range: NSRange(location: 0, length: raised.length))
                text.replaceCharacters(in: range, with: raised)
            }
        }

        func text(for keys: [String], ink: NSColor) -> NSAttributedString {
            let output = NSMutableAttributedString()
            for key in keys {
                guard let number = numbers[key], let content = definitions[key] else { continue }
                if output.length > 0 { output.append(NSAttributedString(string: "\n")) }
                let value = paragraph("\(number). \(content)", literal: false, code: false, newline: false, ink: ink)
                value.addAttribute(.font, value: NSFont.systemFont(ofSize: 10), range: NSRange(location: 0, length: value.length))
                output.append(value)
            }
            return output
        }
    }

    static let sourcePosition = NSAttributedString.Key("ThinkBox.sourcePosition")

    @MainActor static func continuous(_ input: MarkdownPageInput) -> NSAttributedString {
        let rendered = NSMutableAttributedString()
        let (sections, notes) = sections(input, makeImage: MarkdownBlocks.attachment)
        for part in sections {
            if rendered.length > 0 { rendered.append(NSAttributedString(string: "\n")) }
            let mapped = NSMutableAttributedString(attributedString: part.text)
            for (index, position) in part.offsets.enumerated() {
                let end = index + 1 < part.offsets.count ? part.offsets[index + 1].rendered : mapped.length
                if end > position.rendered {
                    mapped.addAttribute(sourcePosition, value: position.source,
                                        range: NSRange(location: position.rendered, length: end - position.rendered))
                }
            }
            rendered.append(mapped)
        }
        if !notes.numbers.isEmpty {
            rendered.append(NSAttributedString(string: "\n\n"))
            rendered.append(notes.text(for: notes.numbers.keys.sorted { notes.numbers[$0]! < notes.numbers[$1]! },
                                       ink: ink(for: input)))
        }
        return rendered
    }

    @MainActor static func render(_ input: MarkdownPageInput) -> MarkdownPages? {
        render(input, makeImage: MarkdownBlocks.attachment)
    }

    @MainActor static func renderPreview(_ input: MarkdownPageInput) async -> MarkdownPages? {
        if input.richTextData != nil || (!input.plain && input.source.contains("![")) { return render(input) }
        // The isolated TextKit stack has no attached view and works on a single thread.
        let job = Task.detached(priority: .userInitiated) {
            render(input, makeImage: { _, _, _ in nil })
        }
        return await withTaskCancellationHandler {
            await job.value
        } onCancel: {
            job.cancel()
        }
    }

    private typealias MakeImage = (String, [URL], CGSize) -> NSTextAttachment?

    private static func render(_ input: MarkdownPageInput, makeImage: MakeImage) -> MarkdownPages? {
        let layout = input.layout
        let size = layout.paperSize
        let (parts, notes) = sections(input, makeImage: makeImage)
        // Text storage owns its layout manager, so keep it alive until the PDF closes.
        let storages = parts.map { NSTextStorage(attributedString: $0.text) }
        var pages: [DrawnPage] = []
        for (part, storage) in zip(parts, storages) {
            let manager = NSLayoutManager()
            manager.backgroundLayoutEnabled = false
            storage.addLayoutManager(manager)
            let glyphs = manager.numberOfGlyphs
            var next = 0
            repeat {
                if Task.isCancelled { return nil }
                let start = next == 0 ? part.start : part.sourceOffset(for: manager.characterIndexForGlyph(at: next))
                let rect = layout.contentRect(page: pages.count)
                let existingContainers = manager.textContainers.count
                guard var columns = columns(in: manager, storage: storage, startingAt: next, rect: rect,
                                           count: layout.columnCount, height: rect.height) else { return nil }
                var footnotes = [DrawnNotes]()
                if !notes.numbers.isEmpty {
                    var reserved: CGFloat = 0
                    while true {
                        let keys = noteKeys(in: columns.map(\.range), manager: manager, storage: storage)
                        let text = notes.text(for: keys, ink: ink(for: input))
                        footnotes = layoutNotes(text, rect: rect)
                        guard let first = footnotes.first else { break }
                        let needed = rect.maxY - first.origin.y + 11
                        if needed <= reserved || columns.isEmpty { break }
                        let previousColumns = columns
                        let previousNotes = footnotes
                        for index in (existingContainers..<manager.textContainers.count).reversed() {
                            manager.removeTextContainer(at: index)
                        }
                        guard let fitted = Self.columns(in: manager, storage: storage, startingAt: next, rect: rect,
                                                        count: layout.columnCount, height: rect.height - needed),
                              !fitted.isEmpty else {
                            return nil
                        }
                        columns = fitted
                        reserved = needed
                        // Keeping the reservation lets boundary references flow to the following page.
                        if columns.map(\.range) == previousColumns.map(\.range) {
                            footnotes = previousNotes
                            break
                        }
                    }
                }
                if let last = columns.last { next = NSMaxRange(last.range) }
                pages.append(DrawnPage(manager: manager, columns: columns, start: start, notes: footnotes.first))
                for notePage in footnotes.dropFirst() {
                    let character = next < glyphs ? manager.characterIndexForGlyph(at: next) : storage.length
                    let source = part.sourceOffset(for: character)
                    pages.append(DrawnPage(manager: manager, columns: [], start: source, notes: notePage))
                }
            } while next < glyphs
        }

        let data = NSMutableData()
        let metadata = [kCGPDFContextTitle as String: input.metadata.title, kCGPDFContextAuthor as String: input.metadata.author]
        var mediaBox = CGRect(origin: .zero, size: size)
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, metadata as CFDictionary) else { return nil }
        withExtendedLifetime(storages) {
            for (index, page) in pages.enumerated() {
                if Task.isCancelled { break }
                context.beginPDFPage(nil)
                context.saveGState()
                context.translateBy(x: 0, y: size.height)
                context.scaleBy(x: 1, y: -1)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
                (input.dark ? NSColor(white: 0.13, alpha: 1) : .white).setFill()
                NSBezierPath(rect: mediaBox).fill()
                for column in page.columns {
                    page.manager.drawBackground(forGlyphRange: column.range, at: column.origin)
                    page.manager.drawGlyphs(forGlyphRange: column.range, at: column.origin)
                }
                if let notes = page.notes {
                    let rule = NSBezierPath()
                    rule.move(to: CGPoint(x: notes.origin.x, y: notes.origin.y - 5))
                    rule.line(to: CGPoint(x: notes.origin.x + 46, y: notes.origin.y - 5))
                    ink(for: input).setStroke()
                    rule.lineWidth = 0.6
                    rule.stroke()
                    withExtendedLifetime(notes.storage) {
                        notes.manager.drawGlyphs(forGlyphRange: notes.range, at: notes.origin)
                    }
                }
                drawLabels(layout: layout, metadata: input.metadata, page: index,
                           total: pages.count, dark: input.dark)
                NSGraphicsContext.restoreGraphicsState()
                context.restoreGState()
                context.endPDFPage()
            }
        }
        context.closePDF()
        guard !Task.isCancelled else { return nil }
        return MarkdownPages(data: data as Data, starts: pages.map(\.start))
    }

    private typealias Column = (range: NSRange, origin: CGPoint)

    private static func columns(in manager: NSLayoutManager, storage: NSTextStorage, startingAt start: Int,
                                rect: CGRect, count: Int, height: CGFloat) -> [Column]? {
        let gutter: CGFloat = 16
        let width = (rect.width - CGFloat(count - 1) * gutter) / CGFloat(count)
        var columns: [Column] = []
        var next = start
        let glyphs = manager.numberOfGlyphs
        for column in 0..<count where next < glyphs {
            let container = NSTextContainer(size: CGSize(width: width, height: height))
            container.lineFragmentPadding = 0
            manager.addTextContainer(container)
            let range = fitColumn(container, in: manager, storage: storage)
            guard range.length > 0 else { return nil }
            columns.append((range, CGPoint(x: rect.minX + CGFloat(column) * (width + gutter), y: rect.minY)))
            next = NSMaxRange(range)
        }
        return columns
    }

    private static func noteKeys(in ranges: [NSRange], manager: NSLayoutManager, storage: NSTextStorage) -> [String] {
        var keys: [String] = []
        var seen = Set<String>()
        for range in ranges {
            let textRange = manager.characterRange(forGlyphRange: range, actualGlyphRange: nil)
            storage.enumerateAttribute(MarkdownBlocks.noteReference, in: textRange) { value, _, _ in
                if let key = value as? String, seen.insert(key).inserted { keys.append(key) }
            }
        }
        return keys
    }

    private static func layoutNotes(_ text: NSAttributedString, rect: CGRect) -> [DrawnNotes] {
        guard text.length > 0 else { return [] }
        let storage = NSTextStorage(attributedString: text)
        let manager = NSLayoutManager()
        manager.backgroundLayoutEnabled = false
        storage.addLayoutManager(manager)
        var next = 0
        var notes: [DrawnNotes] = []
        let glyphs = manager.numberOfGlyphs
        while next < glyphs {
            let height = notes.isEmpty ? max(16, floor(rect.height * 0.35)) : rect.height - 10
            let container = NSTextContainer(size: CGSize(width: rect.width, height: height))
            container.lineFragmentPadding = 0
            manager.addTextContainer(container)
            let range = manager.glyphRange(for: container)
            guard range.length > 0 else { break }
            let used = ceil(manager.usedRect(for: container).height)
            let y = notes.isEmpty ? rect.maxY - used : rect.minY + 9
            notes.append(DrawnNotes(storage: storage, manager: manager, range: range, origin: CGPoint(x: rect.minX, y: y)))
            next = NSMaxRange(range)
        }
        return notes
    }

    private static func fitColumn(_ container: NSTextContainer, in manager: NSLayoutManager,
                                  storage: NSTextStorage) -> NSRange {
        let range = manager.glyphRange(for: container)
        guard range.length > 0, NSMaxRange(range) < manager.numberOfGlyphs else { return range }
        let lastGlyph = NSMaxRange(range) - 1
        let lastCharacter = manager.characterIndexForGlyph(at: lastGlyph)
        if let row = storage.attribute(MarkdownBlocks.tableRow, at: lastCharacter, effectiveRange: nil) as? Int,
           lastCharacter + 1 < storage.length {
            var rowRange = NSRange()
            _ = storage.attribute(MarkdownBlocks.tableRow, at: lastCharacter,
                                  longestEffectiveRange: &rowRange, in: NSRange(location: 0, length: storage.length))
            let nextCharacter = manager.characterIndexForGlyph(at: NSMaxRange(range))
            if storage.attribute(MarkdownBlocks.tableRow, at: nextCharacter, effectiveRange: nil) as? Int == row {
                let rowStart = manager.glyphIndexForCharacter(at: rowRange.location)
                if rowStart > range.location {
                    let top = manager.lineFragmentRect(forGlyphAt: rowStart, effectiveRange: nil).minY
                    if top > 0 {
                        let original = container.size
                        container.size.height = top
                        let adjusted = manager.glyphRange(for: container)
                        if adjusted.length > 0 { return adjusted }
                        container.size = original
                        return manager.glyphRange(for: container)
                    }
                }
            }
            return range
        }
        var line = storage.mutableString.paragraphRange(for: NSRange(location: lastCharacter, length: 0))
        var heading = storage.attribute(headingAttribute, at: line.location, effectiveRange: nil) != nil
        while !heading, line.location > 0,
              storage.mutableString.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            line = storage.mutableString.paragraphRange(for: NSRange(location: line.location - 1, length: 0))
            heading = storage.attribute(headingAttribute, at: line.location, effectiveRange: nil) != nil
        }
        let firstGlyph = manager.glyphIndexForCharacter(at: line.location)
        guard firstGlyph > range.location else { return range }
        var firstLine = NSRange()
        let rect = manager.lineFragmentRect(forGlyphAt: firstGlyph, effectiveRange: &firstLine)
        let hasFollowingContent = NSMaxRange(line) < storage.length
        let wrapsToNextColumn = NSMaxRange(firstLine) == NSMaxRange(range)
            && manager.characterIndexForGlyph(at: NSMaxRange(range)) < NSMaxRange(line)
        let paragraphGlyphs = manager.glyphRange(forCharacterRange: line, actualCharacterRange: nil)
        var lastLine = NSRange()
        _ = manager.lineFragmentRect(forGlyphAt: lastGlyph, effectiveRange: &lastLine)
        var nextLine = NSRange()
        _ = manager.lineFragmentRect(forGlyphAt: NSMaxRange(range), effectiveRange: &nextLine)
        let singleLineOnNextPage = NSMaxRange(nextLine) >= NSMaxRange(paragraphGlyphs)
            && NSMaxRange(range) < NSMaxRange(paragraphGlyphs)
        if singleLineOnNextPage && lastLine.location > range.location && lastLine.location > firstGlyph {
            let previousRect = manager.lineFragmentRect(forGlyphAt: lastLine.location, effectiveRange: nil)
            container.size.height = previousRect.minY
            let adjusted = manager.glyphRange(for: container)
            if adjusted.length > 0 { return adjusted }
        }
        guard rect.minY > 0, (heading && hasFollowingContent) || wrapsToNextColumn else { return range }
        let originalSize = container.size
        container.size.height = rect.minY
        let adjusted = manager.glyphRange(for: container)
        if adjusted.length > 0 { return adjusted }
        container.size = originalSize
        return manager.glyphRange(for: container)
    }

    static func drawLabels(layout: WritingPageLayout, metadata: PageMetadata,
                           page: Int, total: Int, dark: Bool) {
        let labels = layout.labels(page: page)
        let rect = layout.contentRect(page: page)
        let size = layout.paperSize
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9), .paragraphStyle: style,
            .foregroundColor: NSColor(white: dark ? 0.76 : 0.35, alpha: 1)
        ]
        for (template, y) in [(labels.header, (rect.minY - 12) / 2),
                              (labels.footer, (size.height + rect.maxY - 12) / 2)] where !template.isEmpty {
            let value = metadata.expand(template, number: layout.pageNumber(page), total: total)
            (value as NSString).draw(in: CGRect(x: rect.minX, y: y, width: rect.width, height: 13),
                                      withAttributes: attributes)
        }
    }

    private static func ink(for input: MarkdownPageInput) -> NSColor {
        input.dark ? NSColor(white: 0.91, alpha: 1) : .black
    }

    private static func sections(_ input: MarkdownPageInput, makeImage: MakeImage) -> ([Section], Notes) {
        if let data = input.richTextData,
           let attributed = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil) {
            let string = attributed.string as NSString
            var parts: [Section] = []
            var start = 0
            while start <= string.length {
                let rest = NSRange(location: start, length: string.length - start)
                let cut = string.range(of: "\u{000C}", range: rest)
                let end = cut.location == NSNotFound ? string.length : cut.location
                var offsets: [(source: Int, rendered: Int)] = []
                var location = start
                while location < end {
                    offsets.append((location, location - start))
                    location = NSMaxRange(string.paragraphRange(for: NSRange(location: location, length: 0)))
                }
                let text = attributed.attributedSubstring(from: NSRange(location: start, length: end - start))
                parts.append(Section(text: text, offsets: offsets, start: start))
                start = end + 1
            }
            return (parts, Notes(definitions: [:]))
        }

        let lines = MarkdownBlocks.lines(in: input.source, markdown: !input.plain)
        let parsedNotes = input.plain ? (definitions: [:], hidden: Set<Int>()) : MarkdownBlocks.notes(in: lines)
        var notes = Notes(definitions: parsedNotes.definitions)
        let ink = ink(for: input)
        let rect = input.layout.contentRect(page: 0)
        let columnCount = CGFloat(input.layout.columnCount)
        let columnWidth = (rect.width - (columnCount - 1) * 16) / columnCount
        let imageLimit = CGSize(width: max(16, (input.continuousWidth ?? columnWidth) - 8), height: max(16, rect.height * 0.63))
        var result: [Section] = []
        var text = NSMutableAttributedString()
        var offsets: [(Int, Int)] = []
        var sectionStart = 0
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line.fence || parsedNotes.hidden.contains(index) {
                index += 1
                continue
            }
            if !line.code, line.text.trimmingCharacters(in: .whitespaces) == WritingPageLayout.pageBreak {
                result.append(Section(text: text, offsets: offsets, start: sectionStart))
                text = NSMutableAttributedString()
                offsets = []
                sectionStart = line.end
            } else if !input.plain, !line.code, line.text.contains("|"),
                      let table = MarkdownBlocks.table(in: lines, at: index, hidden: parsedNotes.hidden) {
                for (row, cells) in table.rows.enumerated() {
                    let rowOffset = lines[index + (row == 0 ? 0 : row + 1)].start
                    offsets.append((rowOffset, text.length))
                    for (column, cell) in cells.enumerated() {
                        let cellText = paragraph(cell, literal: false, code: false, newline: true, ink: ink)
                        notes.replaceReferences(in: cellText)
                        let range = NSRange(location: 0, length: cellText.length)
                        cellText.addAttributes([
                            .paragraphStyle: MarkdownBlocks.cellStyle(in: table, row: row, column: column, dark: input.dark),
                            MarkdownBlocks.tableRow: rowOffset
                        ], range: range)
                        text.append(cellText)
                    }
                }
                index = table.end
                continue
            } else if !input.plain, !line.code, let image = MarkdownBlocks.image(in: line.text) {
                offsets.append((line.start, text.length))
                if let attachment = makeImage(image.path, input.imageRoots, imageLimit) {
                    text.append(NSAttributedString(attachment: attachment))
                    if line.newline { text.append(NSAttributedString(string: "\n")) }
                } else {
                    let alt = image.alt.isEmpty ? "Imagen no disponible" : "Imagen no disponible · \(image.alt)"
                    text.append(paragraph(alt, literal: true, code: false, newline: line.newline, ink: ink))
                }
            } else {
                offsets.append((line.start, text.length))
                let rendered = paragraph(line.text, literal: input.plain || line.code, code: line.code,
                                         newline: line.newline, ink: ink)
                if !line.code && line.text.contains("[^") { notes.replaceReferences(in: rendered) }
                text.append(rendered)
            }
            index += 1
        }
        result.append(Section(text: text, offsets: offsets, start: sectionStart))
        return (result, notes)
    }

    private static let inlineSyntax = CharacterSet(charactersIn: "*_~[]<>&\\" + String(UnicodeScalar(96)))

    private static func paragraph(_ line: String, literal: Bool, code: Bool, newline: Bool,
                                  ink: NSColor) -> NSMutableAttributedString {
        var value = line
        var heading = 0
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        if !literal {
            if let match = line.prefixMatch(of: /^(#{1,6})[ \t]+/) {
                heading = match.1.count
                value = String(line[match.range.upperBound...])
                paragraph.paragraphSpacingBefore = 6
            } else if let match = line.prefixMatch(of: /^([ \t]*)([-*+]|[0-9]+[.)]|>)[ \t]+/) {
                let marker = String(match.2)
                paragraph.firstLineHeadIndent = 12 + CGFloat(match.1.count * 3)
                paragraph.headIndent = paragraph.firstLineHeadIndent + 12
                value = (marker == ">" ? "" : marker.count == 1 ? "•  " : marker + "  ")
                    + line[match.range.upperBound...]
            }
        }
        let size: CGFloat = heading == 0 ? 12 : max(14, 23 - CGFloat(heading * 2))
        let base = code ? NSFont.monospacedSystemFont(ofSize: size - 1, weight: .regular)
            : NSFont.systemFont(ofSize: size, weight: heading == 0 ? .regular : .semibold)
        let result = NSMutableAttributedString()
        if !literal, value.rangeOfCharacter(from: inlineSyntax) != nil,
           let parsed = try? AttributedString(markdown: value, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            for run in parsed.runs {
                let intent = run.inlinePresentationIntent
                let traits: NSFontDescriptor.SymbolicTraits = [
                    intent?.contains(.stronglyEmphasized) == true ? .bold : [],
                    intent?.contains(.emphasized) == true ? .italic : []
                ]
                let font: NSFont
                if intent?.contains(.code) == true {
                    font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
                } else if !traits.isEmpty {
                    let descriptor = base.fontDescriptor
                    font = NSFont(descriptor: descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(traits)), size: size) ?? base
                } else {
                    font = base
                }
                var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
                if let link = run.link { attributes[.link] = link; attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                if intent?.contains(.strikethrough) == true { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                result.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
            }
        } else {
            result.append(NSAttributedString(string: value, attributes: [.font: base, .foregroundColor: ink]))
        }
        if newline { result.append(NSAttributedString(string: "\n", attributes: [.font: base, .foregroundColor: ink])) }
        guard result.length > 0 else { return result }
        result.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: result.length))
        if heading > 0 {
            result.addAttribute(headingAttribute, value: true, range: NSRange(location: 0, length: result.length))
        }
        return result
    }
}
