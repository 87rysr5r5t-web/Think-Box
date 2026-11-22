import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WritingLibrary

struct CanvasEditor: View {
    @Environment(AppSettings.self) private var settings
    var store: LibraryStore
    var document: WritingDocument

    @ViewState private var board: CanvasBoard?
    @ViewState private var offset = CGSize(width: 50, height: 50)
    @ViewState private var zoom = 1.0
    @GestureState private var panning = CGSize.zero
    @ViewState private var drag: NodeDrag?
    @ViewState private var selection: String?
    @ViewState private var editingNode: CanvasNode?
    @ViewState private var editingEdge: CanvasEdge?
    @ViewState private var connectingFrom: String?
    @ViewState private var openedFile: CanvasFileLink?
    @ViewState private var invalid = false

    private var editable: Bool { document.trashedAt == nil }

    var body: some View {
        Group {
            if let board {
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        toolbar(size: geometry.size)
                        Divider()
                        surface(board)
                    }
                    .onChange(of: board.nodes.isEmpty, initial: true) { _, empty in
                        if !empty && selection == nil && settings.reader.fitCanvas { fit(geometry.size) }
                    }
                }
            } else if invalid {
                ContentUnavailableView("Canvas no disponible", systemImage: "rectangle.on.rectangle.slash")
            } else {
                ProgressView("Abriendo canvas…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if let data = document.attachment?.canvasData {
                do { board = try CanvasBoard(data: data) }
                catch { invalid = true; store.actionError = error.localizedDescription }
            } else { invalid = true }
        }
        .sheet(item: $editingNode) { node in
            CanvasNodeForm(node: node) { updated in
                mutate { board in
                    if let index = board.nodes.firstIndex(where: { $0.id == updated.id }) { board.nodes[index] = updated }
                }
            }
        }
        .sheet(item: $editingEdge) { edge in
            CanvasEdgeForm(edge: edge) { updated in
                mutate { board in
                    if let index = board.edges.firstIndex(where: { $0.id == updated.id }) { board.edges[index] = updated }
                }
            }
        }
        .sheet(item: $openedFile) { file in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(file.url.lastPathComponent).uiFont(0, bold: true)
                    if let subpath = file.subpath, !subpath.isEmpty { Text(subpath).foregroundStyle(.secondary) }
                    Spacer()
                    Button("Cerrar") { openedFile = nil }.keyboardShortcut(.cancelAction)
                }.padding(12)
                if let excerpt = file.excerpt {
                    ScrollView { Text(excerpt).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).padding(14) }
                } else {
                    FilePreview(url: file.url)
                }
            }.frame(minWidth: 560, minHeight: 380)
        }
    }

    private func toolbar(size: CGSize) -> some View {
        HStack(spacing: 12) {
            Menu("Añadir nodo", line: "plus") {
                Button("Texto", line: "text.alignleft") { addNode("text", size: size) }
                Button("Archivo", line: "doc") { addNode("file", size: size) }
                Button("Enlace web", line: "link") { addNode("link", size: size) }
                Button("Grupo", line: "rectangle.dashed") { addNode("group", size: size) }
            }.menuStyle(.button).buttonStyle(ChromeButtonStyle()).fixedSize().disabled(!editable)
            if let fromID = connectingFrom, let from = board?.nodes.first(where: { $0.id == fromID }) {
                Menu("Conectar con…", systemImage: "arrow.turn.down.right") {
                    ForEach((board?.nodes ?? []).filter { $0.id != fromID }) { node in
                        Button(nodeTitle(node)) { connect(from: from.id, to: node.id) }
                    }
                    Button("Cancelar") { connectingFrom = nil }
                }.menuStyle(.button).buttonStyle(ChromeButtonStyle()).fixedSize()
            }
            Spacer(minLength: 2)
            Button("Alejar canvas", line: "minus.magnifyingglass") { scale(zoom / 1.22, around: center(size)) }
                .labelStyle(.iconOnly).buttonStyle(ChromeButtonStyle())
            Text("\(Int(zoom * 100)) %").uiFont(-2).monospacedDigit().foregroundStyle(.secondary)
            Button("Acercar canvas", line: "plus.magnifyingglass") { scale(zoom * 1.22, around: center(size)) }
                .labelStyle(.iconOnly).buttonStyle(ChromeButtonStyle())
            Button("Encuadrar canvas", line: "viewfinder") { fit(size) }.labelStyle(.iconOnly).buttonStyle(ChromeButtonStyle())
            Menu("Opciones del canvas", line: "ellipsis") {
                Button("Vincular carpeta de archivos…", action: chooseRoot).disabled(!editable)
                if let folder = document.attachment?.sourceFolder { Text(folder.lastPathComponent) }
                Button("Exportar canvas…") { store.exportDocument(document) }
                if let edges = board?.edges, !edges.isEmpty {
                    Menu("Conexiones") {
                        ForEach(edges) { edge in
                            Button(edgeTitle(edge)) { editingEdge = edge }.disabled(!editable)
                        }
                    }
                }
            }.labelStyle(.iconOnly).chromeMenu()
        }
        .buttonStyle(ChromeButtonStyle())
        .padding(.horizontal, 13).padding(.vertical, 7)
    }

    private func surface(_ board: CanvasBoard) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Rectangle().fill(.background).overlay {
                    Canvas { context, size in
                        guard settings.reader.canvasGrid else { return }
                        let spacing = max(14, zoom * 24)
                        let xStart = origin.width.truncatingRemainder(dividingBy: spacing)
                        let yStart = origin.height.truncatingRemainder(dividingBy: spacing)
                        for x in stride(from: xStart, to: size.width, by: spacing) {
                            for y in stride(from: yStart, to: size.height, by: spacing) {
                                let dot = Path(ellipseIn: CGRect(x: x, y: y, width: 1.8, height: 1.8))
                                context.fill(dot, with: .color(.primary.opacity(0.18)))
                            }
                        }
                    }.allowsHitTesting(false)
                }
                .gesture(DragGesture().updating($panning) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        offset.width += value.translation.width
                        offset.height += value.translation.height
                    })
                .onTapGesture { selection = nil }

                // Edges use screen-space coordinates so strokes and arrowheads remain legible at low zoom.
                Canvas { context, _ in
                    let byID = Dictionary(uniqueKeysWithValues: board.nodes.map { ($0.id, $0) })
                    for edge in board.edges {
                        if let from = byID[edge.from], let to = byID[edge.to] {
                            draw(edge, from: rectangle(from), to: rectangle(to), in: context)
                        }
                    }
                }.allowsHitTesting(false)
                ForEach(board.nodes) { node in card(node, board: board) }

                if board.nodes.isEmpty {
                    ContentUnavailableView("Canvas vacío", line: "rectangle.on.rectangle",
                                           description: Text("Añade un nodo para empezar."))
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .allowsHitTesting(false)
                }
            }
            .clipped()
            .simultaneousGesture(MagnifyGesture().onEnded { scale(zoom * $0.magnification, around: center(geometry.size)) })
        }
    }

    private func card(_ node: CanvasNode, board: CanvasBoard) -> some View {
        let rect = rectangle(node)
        let group = node.type == "group"
        let color = canvasColor(node["color"])
        return VStack(alignment: .leading, spacing: 5) {
            if zoom >= 0.32 {
                Label(nodeTitle(node), systemImage: nodeIcon(node))
                    .font(settings.font(bold: true))
                    .lineLimit(1)
                if !group && zoom > 0.52 {
                    nodeBody(node).font(settings.font(-1)).lineLimit(max(1, Int(min(7, rect.height / 20))))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(7 * min(1.4, zoom))
        .frame(width: rect.width, height: rect.height, alignment: .topLeading)
        .background {
            if group {
                RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.09))
                if let background = node["background"], let url = store.canvasFile(background, in: document.attachment?.sourceFolder),
                   let image = NSImage(contentsOf: url) {
                    groupBackground(image, style: node["backgroundStyle"], size: rect.size).opacity(0.58)
                }
            } else {
                RoundedRectangle(cornerRadius: 8).fill(.background).shadow(color: .black.opacity(0.10), radius: 3, y: 2)
                RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.09))
            }
        }
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(color, style: StrokeStyle(
            lineWidth: selection == node.id ? 2.5 : 1, dash: group ? [5, 3] : [])) }
        .clipShape(.rect(cornerRadius: 8))
        .contentShape(Rectangle())
        .contextMenu { nodeMenu(node, board: board) }
        .onTapGesture(count: 2) { activate(node) }
        .onTapGesture {
            if let from = connectingFrom, from != node.id, editable { connect(from: from, to: node.id) }
            else { selection = node.id }
        }
        .gesture(DragGesture(minimumDistance: 4).onChanged { value in
            guard editable else { return }
            selection = node.id
            if drag?.id != node.id { drag = NodeDrag(id: node.id, members: members(of: node, in: board), resizing: false, translation: .zero) }
            drag?.translation = value.translation
        }.onEnded { _ in finishDrag() })
        .overlay(alignment: .bottomTrailing) {
            if editable && selection == node.id {
                ChromeSymbol(name: "arrow.up.left.and.arrow.down.right").uiFont(-3)
                    .frame(width: 21, height: 21).background(.regularMaterial, in: .rect(topLeadingRadius: 5))
                    .accessibilityLabel("Redimensionar nodo")
                    .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                        drag = NodeDrag(id: node.id, members: [node.id], resizing: true, translation: value.translation)
                    }.onEnded { _ in finishDrag() })
            }
        }
        .position(x: rect.midX, y: rect.midY)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(nodeTitle(node))
    }

    @ViewBuilder private func groupBackground(_ image: NSImage, style: String?, size: CGSize) -> some View {
        switch style {
        case "repeat": Image(nsImage: image).resizable(resizingMode: .tile).frame(width: size.width, height: size.height)
        case "ratio": Image(nsImage: image).resizable().scaledToFit().frame(width: size.width, height: size.height)
        default: Image(nsImage: image).resizable().scaledToFill().frame(width: size.width, height: size.height).clipped()
        }
    }

    @ViewBuilder private func nodeBody(_ node: CanvasNode) -> some View {
        switch node.type {
        case "text":
            let markdown = node["text"] ?? ""
            let formatted = try? AttributedString(markdown: markdown,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
            Text(formatted ?? AttributedString(markdown)).foregroundStyle(.secondary)
        case "file":
            let path = node["file"] ?? ""
            if let url = store.canvasFile(path, in: document.attachment?.sourceFolder),
               (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.conforms(to: .image)) == true,
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFit()
            } else { Text(path + (node["subpath"] ?? "")).foregroundStyle(.secondary) }
        case "link": Text(node["url"] ?? "").foregroundStyle(.secondary)
        default: EmptyView()
        }
    }

    @ViewBuilder private func nodeMenu(_ node: CanvasNode, board: CanvasBoard) -> some View {
        if node.type == "file" { Button("Abrir archivo") { activate(node) } }
        if node.type == "link" { Button("Abrir enlace") { activate(node) } }
        if editable {
            Button("Editar nodo…") { editingNode = node }
            Button("Conectar desde aquí") { connectingFrom = node.id }
            let edges = board.edges.filter { $0.from == node.id || $0.to == node.id }
            if !edges.isEmpty {
                Menu("Conexiones") {
                    ForEach(edges) { edge in
                        Menu(edgeTitle(edge)) {
                            Button("Editar…") { editingEdge = edge }
                            Button("Quitar conexión", role: .destructive) { mutate { $0.edges.removeAll { $0.id == edge.id } } }
                        }
                    }
                }
            }
            Button("Enviar al fondo") { reorder(node, front: false) }
            Button("Traer al frente") { reorder(node, front: true) }
            Divider()
            Button("Quitar nodo", role: .destructive) {
                mutate { $0.removeNode(node.id) }
                if selection == node.id { selection = nil }
                if connectingFrom == node.id { connectingFrom = nil }
            }
        }
    }

    private var origin: CGSize { CGSize(width: offset.width + panning.width, height: offset.height + panning.height) }

    private func rectangle(_ node: CanvasNode) -> CGRect {
        let changed = drag.flatMap { $0.members.contains(node.id) ? $0 : nil }
        let movement = changed?.resizing == false ? changed?.translation ?? .zero : .zero
        let size = changed?.resizing == true ? changed?.translation ?? .zero : .zero
        return CGRect(x: Double(node.x) * zoom + origin.width + movement.width,
                      y: Double(node.y) * zoom + origin.height + movement.height,
                      width: max(1, min(4_000_000, Double(node.width) * zoom + size.width)),
                      height: max(1, min(4_000_000, Double(node.height) * zoom + size.height)))
    }

    private func members(of node: CanvasNode, in board: CanvasBoard) -> Set<String> {
        guard node.type == "group" else { return [node.id] }
        let bounds = rectangle(node)
        return Set(board.nodes.filter { bounds.contains(rectangle($0)) }.map(\.id)).union([node.id])
    }

    private func mutate(_ change: (inout CanvasBoard) -> Void) {
        guard editable, var updated = board else { return }
        change(&updated)
        if updated != board, store.saveCanvas(updated, documentID: document.id) { board = updated }
    }

    private func finishDrag() {
        guard let drag else { return }
        self.drag = nil
        mutate { board in
            for index in board.nodes.indices where drag.members.contains(board.nodes[index].id) {
                if drag.resizing {
                    board.nodes[index].width = max(40, canvasInt(Double(board.nodes[index].width) + drag.translation.width / zoom))
                    board.nodes[index].height = max(32, canvasInt(Double(board.nodes[index].height) + drag.translation.height / zoom))
                } else {
                    board.nodes[index].x = canvasInt(Double(board.nodes[index].x) + drag.translation.width / zoom)
                    board.nodes[index].y = canvasInt(Double(board.nodes[index].y) + drag.translation.height / zoom)
                }
            }
        }
    }

    private func addNode(_ type: String, size: CGSize) {
        let middle = center(size)
        var node = CanvasNode(type: type, x: canvasInt((middle.x - offset.width) / zoom - 130),
                              y: canvasInt((middle.y - offset.height) / zoom - 75))
        if type == "group" { node.width = 420; node.height = 270 }
        mutate { board in
            if type == "group" { board.nodes.insert(node, at: 0) }
            else { board.nodes.append(node) }
        }
        selection = node.id
        editingNode = node
    }

    private func connect(from: String, to: String) {
        var edge = CanvasEdge(from: from, to: to)
        edge["toEnd"] = "arrow"
        mutate { $0.edges.append(edge) }
        connectingFrom = nil
    }

    private func reorder(_ node: CanvasNode, front: Bool) {
        mutate { board in
            board.nodes.removeAll { $0.id == node.id }
            board.nodes.insert(node, at: front ? board.nodes.endIndex : board.nodes.startIndex)
        }
    }

    private func activate(_ node: CanvasNode) {
        selection = node.id
        switch node.type {
        case "file":
            if let path = node["file"], let url = store.canvasFile(path, in: document.attachment?.sourceFolder) {
                openedFile = CanvasFileLink(url: url, subpath: node["subpath"])
            } else { store.actionError = "No se encuentra el archivo en la carpeta vinculada al canvas." }
        case "link":
            if let link = node["url"], let url = URL(string: link), let scheme = url.scheme?.lowercased(),
               ["http", "https"].contains(scheme), url.host != nil {
                NSWorkspace.shared.open(url)
            } else { store.actionError = "El nodo requiere un enlace web HTTP o HTTPS válido." }
        default: if editable { editingNode = node }
        }
    }

    private func chooseRoot() {
        let panel = NSOpenPanel()
        panel.title = "Vincular carpeta de archivos"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.directoryURL = document.attachment?.sourceFolder
        if panel.runModal() == .OK, let url = panel.url {
            store.update(document.id) { $0.attachment?.sourceFolder = url }
        }
    }

    private func center(_ size: CGSize) -> CGPoint { CGPoint(x: size.width / 2, y: max(0, size.height - 37) / 2) }

    private func scale(_ value: Double, around point: CGPoint) {
        let next = max(0.08, min(4, value))
        let ratio = next / zoom
        offset = CGSize(width: point.x - (point.x - offset.width) * ratio,
                        height: point.y - (point.y - offset.height) * ratio)
        zoom = next
    }

    private func fit(_ size: CGSize) {
        guard let nodes = board?.nodes, !nodes.isEmpty else { return }
        let bounds = nodes.reduce(CGRect.null) { bounds, node in
            bounds.union(CGRect(x: node.x, y: node.y, width: node.width, height: node.height))
        }
        zoom = min(1, max(0.00001, min((size.width - 50) / max(1, bounds.width), (size.height - 87) / max(1, bounds.height))))
        let point = center(size)
        offset = CGSize(width: point.x - bounds.midX * zoom, height: point.y - bounds.midY * zoom)
    }

    private func edgeTitle(_ edge: CanvasEdge) -> String {
        if let label = edge["label"], !label.isEmpty { return label }
        let from = board?.nodes.first { $0.id == edge.from }.map(nodeTitle) ?? edge.from
        let to = board?.nodes.first { $0.id == edge.to }.map(nodeTitle) ?? edge.to
        return "\(from) → \(to)"
    }
}

private struct NodeDrag {
    let id: String
    let members: Set<String>
    let resizing: Bool
    var translation: CGSize
}

private struct CanvasFileLink: Identifiable {
    let url: URL
    let subpath: String?
    var id: URL { url }

    var excerpt: String? {
        guard let subpath, subpath.hasPrefix("#"), ["md", "markdown", "txt"].contains(url.pathExtension.lowercased()),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let key = String(subpath.dropFirst()).removingPercentEncoding ?? String(subpath.dropFirst())
        let lines = text.components(separatedBy: .newlines)
        if key.hasPrefix("^"), let line = lines.first(where: { $0.hasSuffix(" " + key) }) { return line }
        if let index = lines.firstIndex(where: { $0.hasPrefix("#") && $0.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces) == key }) {
            let level = lines[index].prefix(while: { $0 == "#" }).count
            return ([lines[index]] + lines.dropFirst(index + 1).prefix(while: {
                let heading = $0.prefix(while: { $0 == "#" }).count
                return heading == 0 || heading > level
            })).joined(separator: "\n")
        }
        return nil
    }
}

private func canvasInt(_ value: Double) -> Int { Int(max(-4_000_000, min(4_000_000, value.rounded()))) }

private func nodeIcon(_ node: CanvasNode) -> String {
    switch node.type {
    case "text": "text.alignleft"
    case "link": "link"
    case "group": "rectangle.dashed"
    default: "doc"
    }
}

private func nodeTitle(_ node: CanvasNode) -> String {
    switch node.type {
    case "text": "Texto"
    case "file": node["file"].flatMap { $0.isEmpty ? nil : ($0 as NSString).lastPathComponent } ?? "Archivo"
    case "group": node["label"].flatMap { $0.isEmpty ? nil : $0 } ?? "Grupo"
    case "link": node["url"].flatMap { URL(string: $0)?.host } ?? "Enlace web"
    default: node.type
    }
}

private func canvasColor(_ value: String?) -> Color {
    switch value {
    case "1": .red
    case "2": .orange
    case "3": .yellow
    case "4": .green
    case "5": .cyan
    case "6": .purple
    case let hex? where hex.hasPrefix("#") && hex.count == 7:
        if let rgb = UInt32(hex.dropFirst(), radix: 16) {
            Color(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
        } else { .secondary }
    default: .secondary
    }
}

private func endpoint(_ side: String?, rect: CGRect, toward: CGRect) -> CGPoint {
    let dx = toward.midX - rect.midX
    let dy = toward.midY - rect.midY
    let auto = abs(dx) >= abs(dy) ? (dx >= 0 ? "right" : "left") : (dy >= 0 ? "bottom" : "top")
    return switch side ?? auto {
    case "top": CGPoint(x: rect.midX, y: rect.minY)
    case "bottom": CGPoint(x: rect.midX, y: rect.maxY)
    case "left": CGPoint(x: rect.minX, y: rect.midY)
    default: CGPoint(x: rect.maxX, y: rect.midY)
    }
}

private func draw(_ edge: CanvasEdge, from: CGRect, to: CGRect, in context: GraphicsContext) {
    let start = endpoint(edge["fromSide"], rect: from, toward: to)
    let end = endpoint(edge["toSide"], rect: to, toward: from)
    let color = canvasColor(edge["color"])
    var path = Path()
    path.move(to: start)
    path.addLine(to: end)
    func arrow(at point: CGPoint, from other: CGPoint) {
        let angle = atan2(point.y - other.y, point.x - other.x)
        for delta in [-0.50, 0.50] {
            path.move(to: point)
            path.addLine(to: CGPoint(x: point.x - 10 * cos(angle + delta), y: point.y - 10 * sin(angle + delta)))
        }
    }
    if edge["fromEnd"] == "arrow" { arrow(at: start, from: end) }
    if edge["toEnd"] == "arrow" || edge["toEnd"] == nil { arrow(at: end, from: start) }
    context.stroke(path, with: .color(color), lineWidth: 1.6)
    if let label = edge["label"], !label.isEmpty {
        let middle = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 - 9)
        context.draw(Text(label).font(.caption2).foregroundStyle(Color.primary), at: middle)
    }
}
