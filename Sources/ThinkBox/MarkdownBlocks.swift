import AppKit
import ImageIO

enum MarkdownBlocks {
    static let noteReference = NSAttributedString.Key("ThinkBox.noteReference")
    static let tableRow = NSAttributedString.Key("ThinkBox.tableRow")

    struct Line {
        let text: String
        let start: Int
        let end: Int
        let newline: Bool
        let code: Bool
        let fence: Bool
    }

    static func lines(in source: String, markdown: Bool) -> [Line] {
        let source = source as NSString
        var lines: [Line] = []
        var start = 0
        var fence: (marker: Character, count: Int)?
        while start < source.length {
            var end = 0
            var contentsEnd = 0
            source.getLineStart(nil, end: &end, contentsEnd: &contentsEnd,
                                for: NSRange(location: start, length: 0))
            let value = source.substring(with: NSRange(location: start, length: contentsEnd - start))
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            var boundary = false
            if markdown, let marker = trimmed.first, marker == "~" || marker.asciiValue == 96 {
                let count = trimmed.prefix { $0 == marker }.count
                if let active = fence {
                    if marker == active.marker, count >= active.count, trimmed.count == count {
                        fence = nil
                        boundary = true
                    }
                } else if count >= 3 {
                    fence = (marker, count)
                    boundary = true
                }
            }
            lines.append(Line(text: value, start: start, end: end, newline: end > contentsEnd,
                              code: fence != nil, fence: boundary))
            start = end
        }
        return lines
    }

    static func notes(in lines: [Line]) -> (definitions: [String: String], hidden: Set<Int>) {
        var definitions: [String: String] = [:]
        var hidden: Set<Int> = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            guard !line.code, !line.fence,
                  let definition = line.text.prefixMatch(of: /^ {0,3}\[\^([^\]\s]+)\]:[ \t]*(.*)$/) else {
                index += 1
                continue
            }
            let key = definition.1.lowercased()
            var body = String(definition.2)
            hidden.insert(index)
            index += 1
            while index < lines.count, !lines[index].fence,
                  lines[index].text.hasPrefix("    ") || lines[index].text.hasPrefix("\t") {
                body += "\n" + lines[index].text.trimmingCharacters(in: .whitespaces)
                hidden.insert(index)
                index += 1
            }
            if definitions[key] == nil { definitions[key] = body }
        }
        return (definitions, hidden)
    }

    struct Table {
        let rows: [[String]]
        let alignment: [NSTextAlignment]
        let table: NSTextTable
        let end: Int
    }

    static func table(in lines: [Line], at index: Int, hidden: Set<Int>) -> Table? {
        guard index + 1 < lines.count,
              let header = cells(in: lines[index].text),
              let separator = cells(in: lines[index + 1].text, allowSingleColumn: header.count == 1),
              separator.count == header.count,
              separator.allSatisfy({ $0.wholeMatch(of: /^:?-+:?$/) != nil }) else { return nil }
        let alignment: [NSTextAlignment] = separator.map {
            if $0.hasSuffix(":") { return $0.hasPrefix(":") ? .center : .right }
            return .left
        }
        var rows = [header]
        var next = index + 2
        while next < lines.count, !hidden.contains(next), !lines[next].code, !lines[next].fence,
              let row = cells(in: lines[next].text) {
            rows.append(header.indices.map { $0 < row.count ? row[$0] : "" })
            next += 1
        }
        let table = NSTextTable()
        table.numberOfColumns = header.count
        table.collapsesBorders = true
        return Table(rows: rows, alignment: alignment, table: table, end: next)
    }

    private static func cells(in line: String, allowSingleColumn: Bool = false) -> [String]? {
        let text = line.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        var cells = [""]
        var escaped = false
        var code = false
        var hasDelimiter = false
        for character in text {
            if escaped {
                cells[cells.count - 1].append(character)
                escaped = false
            } else if character == "\\" {
                cells[cells.count - 1].append(character)
                escaped = true
            } else if character.asciiValue == 96 {
                cells[cells.count - 1].append(character)
                code.toggle()
            } else if character == "|", !code {
                cells.append("")
                hasDelimiter = true
            } else {
                cells[cells.count - 1].append(character)
            }
        }
        guard hasDelimiter || allowSingleColumn else { return nil }
        if cells.first == "" { cells.removeFirst() }
        if cells.last == "" { cells.removeLast() }
        return cells.isEmpty ? nil : cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func cellStyle(in table: Table, row: Int, column: Int, dark: Bool) -> NSParagraphStyle {
        let block = NSTextTableBlock(table: table.table, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1)
        block.setWidth(4, type: .absoluteValueType, for: .padding)
        block.setWidth(0.6, type: .absoluteValueType, for: .border)
        block.setBorderColor(NSColor(white: dark ? 0.34 : 0.75, alpha: 1))
        if row == 0 { block.backgroundColor = NSColor(white: dark ? 0.22 : 0.93, alpha: 1) }
        let style = NSMutableParagraphStyle()
        style.alignment = table.alignment[column]
        style.textBlocks = [block]
        return style
    }

    static func image(in text: String) -> (alt: String, path: String)? {
        let imagePattern = /!\[([^\]]*)\]\(\s*(?:<([^>]+)>|([^\s)]+))(?:\s+"[^"]*")?\s*\)/
        guard text.contains("![") else { return nil }
        guard let match = text.trimmingCharacters(in: .whitespaces).wholeMatch(of: imagePattern),
              let path = match.2 ?? match.3 else { return nil }
        return (String(match.1), String(path))
    }

    static func relativeImagePaths(in source: String) -> Set<String> {
        Set(lines(in: source, markdown: true).compactMap { line in
            guard !line.code, !line.fence, let image = image(in: line.text) else { return nil }
            return relativePath(image.path) == nil ? nil : image.path
        })
    }

    private static func relativePath(_ reference: String) -> String? {
        guard let path = reference.removingPercentEncoding, !path.isEmpty,
              !path.hasPrefix("/"), !path.contains(":"), !path.contains("\0"),
              !path.split(separator: "/").contains("..") else { return nil }
        return path
    }

    static func localImageURL(_ reference: String, relativeTo root: URL) -> URL? {
        guard let path = relativePath(reference) else { return nil }
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        let image = root.appending(path: path).standardizedFileURL.resolvingSymlinksInPath()
        guard image.pathComponents.starts(with: root.pathComponents), image != root,
              (try? image.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return nil }
        return image
    }

    @MainActor static func attachment(path: String, roots: [URL], maximum: CGSize) -> NSTextAttachment? {
        let imageSource: CGImageSource?
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        if path.hasPrefix("data:image/"), let comma = path.firstIndex(of: ","),
           path[..<comma].hasSuffix(";base64"), path.utf8.count < 25_000_000,
           let data = Data(base64Encoded: String(path[path.index(after: comma)...])) {
            imageSource = CGImageSourceCreateWithData(data as CFData, options)
        } else if let url = roots.lazy.compactMap({ localImageURL(path, relativeTo: $0) }).first {
            imageSource = CGImageSourceCreateWithURL(url as CFURL, options)
        } else { return nil }
        guard let imageSource,
              let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600
              ] as CFDictionary) else { return nil }
        let scale = min(1, maximum.width / CGFloat(image.width), maximum.height / CGFloat(image.height))
        guard scale > 0 else { return nil }
        let attachment = NSTextAttachment()
        attachment.image = NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width) * scale,
                                                                height: CGFloat(image.height) * scale))
        if let prepared = attachment.image {
            attachment.attachmentCell = NSTextAttachmentCell(imageCell: prepared)
        }
        return attachment
    }
}
