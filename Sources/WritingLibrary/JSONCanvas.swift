import Foundation

enum CanvasValue: Codable, Equatable {
    case string(String), integer(Int64), decimal(Double), bool(Bool), object([String: Self]), array([Self]), null

    init(from decoder: Decoder) throws {
        let box = try decoder.singleValueContainer()
        if box.decodeNil() { self = .null }
        else if let value = try? box.decode(Bool.self) { self = .bool(value) }
        else if let value = try? box.decode(Int64.self) { self = .integer(value) }
        else if let value = try? box.decode(Double.self) { self = .decimal(value) }
        else if let value = try? box.decode(String.self) { self = .string(value) }
        else if let value = try? box.decode([Self].self) { self = .array(value) }
        else { self = .object(try box.decode([String: Self].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var box = encoder.singleValueContainer()
        switch self {
        case .null: try box.encodeNil()
        case .string(let value): try box.encode(value)
        case .integer(let value): try box.encode(value)
        case .decimal(let value): try box.encode(value)
        case .bool(let value): try box.encode(value)
        case .object(let value): try box.encode(value)
        case .array(let value): try box.encode(value)
        }
    }

    var string: String? { if case .string(let value) = self { value } else { nil } }
    var integer: Int? { if case .integer(let value) = self { Int(exactly: value) } else { nil } }
    var object: [String: Self]? { if case .object(let value) = self { value } else { nil } }
    var array: [Self]? { if case .array(let value) = self { value } else { nil } }
}

public struct CanvasNode: Identifiable, Equatable {
    var fields: [String: CanvasValue]

    public init(type: String, x: Int, y: Int) {
        fields = ["id": .string(UUID().uuidString.lowercased()), "type": .string(type),
                  "x": .integer(Int64(x)), "y": .integer(Int64(y)),
                  "width": .integer(260), "height": .integer(150)]
        switch type {
        case "text": self["text"] = ""
        case "file": self["file"] = ""
        case "link": self["url"] = ""
        case "group": self["label"] = "Grupo"
        default: break
        }
    }

    init(fields: [String: CanvasValue]) { self.fields = fields }

    public var id: String { self["id"] ?? "" }
    public var type: String { self["type"] ?? "" }
    public var x: Int {
        get { fields["x"]?.integer ?? 0 }
        set { fields["x"] = .integer(Int64(newValue)) }
    }
    public var y: Int {
        get { fields["y"]?.integer ?? 0 }
        set { fields["y"] = .integer(Int64(newValue)) }
    }
    public var width: Int {
        get { fields["width"]?.integer ?? 1 }
        set { fields["width"] = .integer(Int64(newValue)) }
    }
    public var height: Int {
        get { fields["height"]?.integer ?? 1 }
        set { fields["height"] = .integer(Int64(newValue)) }
    }

    public subscript(_ key: String) -> String? {
        get { fields[key]?.string }
        set { fields[key] = newValue.map(CanvasValue.string) }
    }
}

public struct CanvasEdge: Identifiable, Equatable {
    var fields: [String: CanvasValue]

    public init(from: String, to: String) {
        fields = ["id": .string(UUID().uuidString.lowercased()), "fromNode": .string(from), "toNode": .string(to)]
    }

    init(fields: [String: CanvasValue]) { self.fields = fields }

    public var id: String { self["id"] ?? "" }
    public var from: String { self["fromNode"] ?? "" }
    public var to: String { self["toNode"] ?? "" }

    public subscript(_ key: String) -> String? {
        get { fields[key]?.string }
        set { fields[key] = newValue.map(CanvasValue.string) }
    }
}

public struct CanvasBoard: Equatable {
    private var root: [String: CanvasValue]
    public var nodes: [CanvasNode]
    public var edges: [CanvasEdge]

    public init() {
        root = [:]
        nodes = []
        edges = []
    }

    public init(data: Data) throws {
        root = try JSONDecoder().decode([String: CanvasValue].self, from: data)
        func objects(_ key: String) throws -> [[String: CanvasValue]] {
            guard let value = root[key] else { return [] }
            guard let array = value.array else { throw CanvasFormatError.invalid }
            let objects = array.compactMap(\.object)
            guard objects.count == array.count else { throw CanvasFormatError.invalid }
            return objects
        }
        nodes = []
        edges = []
        nodes = try objects("nodes").map(CanvasNode.init(fields:))
        edges = try objects("edges").map(CanvasEdge.init(fields:))
        let nodeIDs = Set(nodes.map(\.id))
        let edgeIDs = Set(edges.map(\.id))
        guard nodeIDs.count == nodes.count, edgeIDs.count == edges.count,
              nodes.allSatisfy({ node in
                  !node.id.isEmpty && !node.type.isEmpty && ["x", "y", "width", "height"].allSatisfy { node.fields[$0]?.integer != nil }
                      && node.width > 0 && node.height > 0
              }), edges.allSatisfy({ !$0.id.isEmpty && !$0.from.isEmpty && !$0.to.isEmpty }) else {
            throw CanvasFormatError.invalid
        }
    }

    public var searchText: String {
        let fields = ["text", "label", "file", "url"]
        let nodeText = nodes.flatMap { node in fields.compactMap { node[$0] } }
        return (nodeText + edges.compactMap { $0["label"] }).joined(separator: "\n")
    }

    public func data() throws -> Data {
        var output = root
        output["nodes"] = .array(nodes.map { .object($0.fields) })
        output["edges"] = .array(edges.map { .object($0.fields) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(output)
    }

    public mutating func removeNode(_ id: String) {
        nodes.removeAll { $0.id == id }
        edges.removeAll { $0.from == id || $0.to == id }
    }
}

private enum CanvasFormatError: LocalizedError {
    case invalid
    var errorDescription: String? { "El archivo no tiene una estructura JSON Canvas válida." }
}
