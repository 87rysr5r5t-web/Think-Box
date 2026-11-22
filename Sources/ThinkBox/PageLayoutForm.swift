import SwiftUI
import WritingLibrary

struct PageLayoutForm: View {
    @Binding var layout: WritingPageLayout

    var body: some View {
        Section("Papel") {
            Picker("Tamaño", selection: $layout.paper) {
                ForEach(WritingPaper.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if layout.paper == .custom {
                measure("Ancho", value: $layout.width)
                measure("Alto", value: $layout.height)
            }
            Picker("Orientación", selection: $layout.landscape) {
                Text("Vertical").tag(false)
                Text("Horizontal").tag(true)
            }
            Picker("Márgenes", selection: $layout.margins) {
                ForEach(WritingMargins.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if layout.margins == .custom {
                measure("Superior", value: $layout.customInsets.top)
                measure("Inferior", value: $layout.customInsets.bottom)
                measure("Izquierdo", value: $layout.customInsets.left)
                measure("Derecho", value: $layout.customInsets.right)
            }
            Picker("Columnas de previsualización e impresión", selection: $layout.columns) {
                ForEach(1...3, id: \.self) { Text(String($0)).tag($0) }
            }
        }
        Section("Encabezado y pie") {
            TextField("Encabezado", text: $layout.labels.header)
            TextField("Pie", text: $layout.labels.footer)
            Toggle("Primera página distinta", isOn: variant(\.firstLabels))
            if let fields = labels(\.firstLabels) {
                TextField("Encabezado inicial", text: fields.header)
                TextField("Pie inicial", text: fields.footer)
            }
            Toggle("Páginas pares distintas", isOn: variant(\.evenLabels))
            if let fields = labels(\.evenLabels) {
                TextField("Encabezado par", text: fields.header)
                TextField("Pie par", text: fields.footer)
            }
            TextField("Empezar a numerar en", value: $layout.firstNumber, format: .number)
            Text("{titulo}   {pagina}   {paginas}   {fecha}   {base}   {grupo}   {autor}")
                .uiFont(-2).foregroundStyle(.secondary)
        }
    }

    private func measure(_ title: String, value: Binding<Double>) -> some View {
        LabeledContent(title) {
            TextField(title, value: value, format: .number.precision(.fractionLength(0...1)))
                .labelsHidden().multilineTextAlignment(.trailing).frame(width: 78)
            Text("mm").foregroundStyle(.secondary)
        }
    }

    private func variant(_ path: WritableKeyPath<WritingPageLayout, PageLabels?>) -> Binding<Bool> {
        Binding(get: { layout[keyPath: path] != nil }, set: { layout[keyPath: path] = $0 ? layout.labels : nil })
    }

    private func labels(_ path: WritableKeyPath<WritingPageLayout, PageLabels?>) -> Binding<PageLabels>? {
        guard layout[keyPath: path] != nil else { return nil }
        return Binding(get: { layout[keyPath: path] ?? layout.labels }, set: { layout[keyPath: path] = $0 })
    }
}

struct PageSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ViewState var layout: WritingPageLayout
    let save: (WritingPageLayout) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form { PageLayoutForm(layout: $layout) }.formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Aplicar") { save(layout); dismiss() }.keyboardShortcut(.defaultAction)
            }.padding(14)
        }.frame(width: 560, height: 540)
    }
}

extension WritingViewMode {
    var symbol: String {
        switch self {
        case .source: "pencil"
        case .split: "rectangle.split.2x1"
        case .preview: "book"
        }
    }


    var title: String {
        switch self {
        case .source: "Editor"
        case .preview: "Previsualización"
        case .split: "Dividido"
        }
    }
}
