import SwiftUI
import WritingLibrary

struct CanvasNodeForm: View {
    @Environment(\.dismiss) private var dismiss
    @ViewState private var node: CanvasNode
    var save: (CanvasNode) -> Void

    init(node: CanvasNode, save: @escaping (CanvasNode) -> Void) {
        _node = ViewState(wrappedValue: node)
        self.save = save
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Editar nodo").uiFont(4, bold: true)
            switch node.type {
            case "text":
                TextEditor(text: field("text")).font(.body.monospaced()).frame(height: 150)
                    .accessibilityLabel("Texto Markdown del nodo")
                    .border(.quaternary)
            case "file":
                TextField("Ruta relativa del archivo", text: field("file"))
                TextField("Sección o bloque, p. ej. #Introducción", text: field("subpath"))
            case "link":
                TextField("URL", text: field("url"))
            case "group":
                TextField("Nombre del grupo", text: field("label"))
                TextField("Ruta de la imagen de fondo", text: field("background"))
                Picker("Ajuste del fondo", selection: field("backgroundStyle")) {
                    Text("Predeterminado").tag("")
                    Text("Cubrir").tag("cover")
                    Text("Mantener proporción").tag("ratio")
                    Text("Repetir").tag("repeat")
                }
            default:
                Text(node.type).foregroundStyle(.secondary)
            }
            HStack {
                TextField("X", value: $node.x, format: .number).accessibilityLabel("Posición X")
                TextField("Y", value: $node.y, format: .number).accessibilityLabel("Posición Y")
                TextField("Ancho", value: $node.width, format: .number).accessibilityLabel("Ancho")
                TextField("Alto", value: $node.height, format: .number).accessibilityLabel("Alto")
            }
            ColorField(value: field("color"))
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                Button("Guardar nodo") { save(node); dismiss() }.keyboardShortcut(.defaultAction)
                    .disabled(node.width <= 0 || node.height <= 0)
            }
        }.padding(20).frame(width: 420)
    }

    private func field(_ key: String) -> Binding<String> {
        Binding(get: { node[key] ?? "" }, set: { value in
            node[key] = value.isEmpty && !["text", "file", "url"].contains(key) ? nil : value
        })
    }
}

struct CanvasEdgeForm: View {
    @Environment(\.dismiss) private var dismiss
    @ViewState private var edge: CanvasEdge
    var save: (CanvasEdge) -> Void

    init(edge: CanvasEdge, save: @escaping (CanvasEdge) -> Void) {
        _edge = ViewState(wrappedValue: edge)
        self.save = save
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Editar conexión").uiFont(4, bold: true)
            TextField("Rótulo", text: field("label"))
            HStack {
                side("Lado de origen", key: "fromSide")
                side("Lado de destino", key: "toSide")
            }
            HStack {
                end("Origen", key: "fromEnd")
                end("Destino", key: "toEnd")
            }
            ColorField(value: field("color"))
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                Button("Guardar conexión") { save(edge); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 480)
    }

    private func side(_ title: String, key: String) -> some View {
        Picker(title, selection: field(key)) {
            Text("Automático").tag("")
            Text("Arriba").tag("top")
            Text("Abajo").tag("bottom")
            Text("Izquierda").tag("left")
            Text("Derecha").tag("right")
        }
    }

    private func end(_ title: String, key: String) -> some View {
        Picker(title, selection: field(key)) {
            Text("Predeterminado").tag("")
            Text("Sin flecha").tag("none")
            Text("Con flecha").tag("arrow")
        }
    }

    private func field(_ key: String) -> Binding<String> {
        Binding(get: { edge[key] ?? "" }, set: { edge[key] = $0.isEmpty ? nil : $0 })
    }
}

private struct ColorField: View {
    @Binding var value: String

    var body: some View {
        HStack {
            TextField("Color (1–6 o #RRGGBB)", text: $value)
            Menu("Colores") {
                Button("Predeterminado") { value = "" }
                ForEach(Array(["Rojo", "Naranja", "Amarillo", "Verde", "Cian", "Violeta"].enumerated()), id: \.offset) { index, color in
                    Button(color) { value = String(index + 1) }
                }
            }.fixedSize()
        }
    }
}
