import CoreGraphics
import Foundation

public struct ItemDestination: Hashable, Codable {
    public let documentID: UUID
    public let fragmentID: UUID?
    public let databaseID: UUID?

    public init(_ documentID: UUID, fragmentID: UUID? = nil, databaseID: UUID? = nil) {
        self.documentID = documentID
        self.fragmentID = fragmentID
        self.databaseID = databaseID
    }

    public init?(url: URL) {
        guard url.scheme?.lowercased() == "thinkbox", url.host?.lowercased() == "document",
              url.pathComponents.count == 2, let id = UUID(uuidString: url.lastPathComponent) else { return nil }
        let database = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "base" }
        let databaseID = database?.value.flatMap(UUID.init(uuidString:))
        guard database == nil || databaseID != nil else { return nil }
        if let fragment = url.fragment {
            guard let fragmentID = UUID(uuidString: fragment) else { return nil }
            self.init(id, fragmentID: fragmentID, databaseID: databaseID)
        } else {
            self.init(id, databaseID: databaseID)
        }
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = "thinkbox"
        components.host = "document"
        components.path = "/\(documentID.uuidString)"
        if let databaseID { components.queryItems = [URLQueryItem(name: "base", value: databaseID.uuidString)] }
        components.fragment = fragmentID?.uuidString
        return components.url!
    }

    public func markdownLink(label: String) -> String {
        let escaped = label.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
        return "[\(escaped)](\(url.absoluteString))"
    }
}

public struct TextAnchor: Codable, Equatable, Sendable {
    public private(set) var location: Int
    public let quote: String
    private let before: String
    private let after: String

    public init?(text: String, range: NSRange) {
        let source = text as NSString
        guard range.location >= 0, range.location <= source.length, range.length > 0,
              range.length <= source.length - range.location, let selection = Range(range, in: text) else { return nil }
        location = range.location
        quote = String(text[selection])
        before = String(text[..<selection.lowerBound].suffix(40))
        after = String(text[selection.upperBound...].prefix(40))
    }

    public func resolve(in text: String) -> NSRange? {
        let source = text as NSString
        let length = quote.utf16.count
        guard length > 0 else { return nil }
        let expected = NSRange(location: location, length: length)
        if location >= 0, location <= source.length, length <= source.length - location,
           source.substring(with: expected) == quote { return expected }

        var matches: [NSRange] = []
        var offset = 0
        while offset < source.length {
            let range = source.range(of: quote, options: .literal, range: NSRange(location: offset, length: source.length - offset))
            guard range.location != NSNotFound else { break }
            matches.append(range)
            offset = NSMaxRange(range)
        }
        if matches.count == 1, location >= 0 { return matches.first }
        let contextual = matches.filter { range in
            let prefix = source.substring(to: range.location)
            let suffix = source.substring(from: NSMaxRange(range))
            let prefixMatches = before.isEmpty ? prefix.isEmpty : prefix.hasSuffix(before)
            let suffixMatches = after.isEmpty ? suffix.isEmpty : suffix.hasPrefix(after)
            return location < 0 ? prefixMatches && suffixMatches : prefixMatches || suffixMatches
        }
        return contextual.count == 1 ? contextual.first : nil
    }

    mutating func adjust(for replaced: NSRange, replacementLength: Int, newText: String) {
        if location >= NSMaxRange(replaced) {
            location += replacementLength - replaced.length
        } else if NSMaxRange(NSRange(location: location, length: quote.utf16.count)) > replaced.location {
            // An edit through the quotation may invalidate it. Reattach only when the quotation can still be found.
            location = -1
            if let resolved = resolve(in: newText) { location = resolved.location }
        }
    }
}

public struct PDFTextSpan: Codable, Equatable, Sendable {
    public let page: Int
    public let anchor: TextAnchor

    public init(page: Int, anchor: TextAnchor) {
        self.page = page
        self.anchor = anchor
    }
}

public enum FragmentLocation: Codable, Equatable, Sendable {
    case text(TextAnchor)
    case pdf(page: Int, spans: [PDFTextSpan])
    case pdfArea(page: Int, bounds: CGRect)
}

public struct DocumentFragment: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var quote: String
    public var location: FragmentLocation
    public var tags: [String]

    public init(quote: String, location: FragmentLocation, tags: [String] = []) {
        self.quote = quote
        self.location = location
        self.tags = tags
    }
}

public struct LibraryResult: Identifiable {
    public let document: WritingDocument
    public let fragment: DocumentFragment?

    public var id: ItemDestination { ItemDestination(document.id, fragmentID: fragment?.id) }
}

public enum AttachmentKind: String, Codable, Sendable {
    case pdf, canvas, preview

    public var label: String {
        switch self {
        case .pdf: "PDF"
        case .canvas: "Canvas"
        case .preview: "Archivo"
        }
    }
}

public struct DocumentAttachment: Codable, Equatable, Sendable {
    public let filename: String
    public let kind: AttachmentKind
    public var sourceFolder: URL?
    public var searchText: String?
    public var canvasData: Data?

    public init(filename: String, kind: AttachmentKind, sourceFolder: URL? = nil, searchText: String? = nil) {
        self.filename = filename
        self.kind = kind
        self.sourceFolder = sourceFolder
        self.searchText = searchText
    }
}
