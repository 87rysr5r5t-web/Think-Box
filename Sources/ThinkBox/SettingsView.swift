import AppKit
import SwiftUI
import WritingLibrary

struct SettingsView: View {
    @Bindable var settings: AppSettings
    var store: LibraryStore

    var body: some View {
        TabView {
            appearance.tabItem { Label("Apariencia", systemImage: "circle.lefthalf.filled") }
            editor.tabItem { Label("Editor", systemImage: "text.alignleft") }
            library.tabItem { Label("Biblioteca", systemImage: "folder") }
            reading.tabItem { Label("Lectura", systemImage: "book") }
            pages.tabItem { Label("Página", systemImage: "doc") }
            gestures.tabItem { Label("Gestos", systemImage: "hand.point.up.left") }
        }
        .font(settings.font())
        .frame(width: 620, height: 540)
    }

    private var pages: some View {
        Form {
            Section("Valores iniciales") {
                writingViews("Markdown", options: $settings.pages.markdown)
                writingViews("Texto plano", options: $settings.pages.plainText)
                writingViews("Texto enriquecido", options: Binding(get: { settings.pages.richText ?? WritingPageViews() }, set: { settings.pages.richText = $0 }))
                writingViews("HTML", options: Binding(get: { settings.pages.html ?? WritingPageViews() }, set: { settings.pages.html = $0 }))
            }
            Section("Visualización") {
                Toggle("Usar papel oscuro en el tema oscuro", isOn: $settings.pages.darkPaper)
                Toggle("Sincronizar el desplazamiento en vista dividida", isOn: $settings.pages.synchronize)
            }
            PageLayoutForm(layout: $settings.pages.layout)
            Button("Restablecer ajustes de página") { settings.pages = PageViewOptions() }
        }.formStyle(.grouped)
    }

    @ViewBuilder private func writingViews(_ title: String, options: Binding<WritingPageViews>) -> some View {
        Picker(title, selection: options.mode) {
            ForEach(WritingViewMode.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        Toggle("Paginar el editor de " + title, isOn: options.editor)
        Toggle("Paginar la previsualización de " + title, isOn: options.preview)
    }

    private var gestures: some View {
        Form {
            Toggle("Plegar y desplegar con dos dedos", isOn: $settings.gestures.enabled)
            Picker("Sensibilidad", selection: Binding(
                get: { settings.gestures.sensitivity ?? .medium },
                set: { settings.gestures.sensitivity = $0 }
            )) {
                ForEach(SwipeSensitivity.allCases, id: \.self) { value in
                    Text(value.title).tag(value)
                }
            }
            Toggle("Plegar y desplegar nodos de árboles", isOn: Binding(
                get: { settings.gestures.foldNodes ?? true },
                set: { settings.gestures.foldNodes = $0 }
            ))
            Toggle("Invertir dirección", isOn: $settings.gestures.reverse)
            Toggle("Permitir rueda horizontal del ratón", isOn: Binding(
                get: { settings.gestures.horizontalWheel ?? false },
                set: { settings.gestures.horizontalWheel = $0 }
            ))
            Toggle("Plegar paneles en cascada desde el visor", isOn: $settings.gestures.cascade)
            LabeledContent("Recorrido para completar el gesto") {
                Slider(value: $settings.gestures.threshold, in: 0.25...0.65, step: 0.05)
                Text(settings.gestures.threshold.formatted(.percent.precision(.fractionLength(0))))
            }
            pointStepper("Zona de borde", value: $settings.gestures.edge, range: 12...48, step: 4)
            Button("Restablecer gestos") { settings.gestures = GestureOptions() }
        }.formStyle(.grouped)
    }

    private var appearance: some View {
        Form {
            Section("Interfaz") {
                ChoicePicker("Tema", selection: $settings.appearance.theme)
                FontFacePicker(title: "Fuente de la interfaz", selected: $settings.appearance.font)
                pointStepper("Tamaño de la interfaz", value: $settings.appearance.fontSize, range: 11...20)
                pointStepper("Tamaño de la lista", value: $settings.appearance.listSize, range: 10...22)
            }
            Section("Barra lateral") {
                Toggle("Mostrar barra lateral", isOn: $settings.appearance.showSidebar)
                Toggle("Filas compactas", isOn: $settings.appearance.compactRows)
                pointStepper("Ancho de la barra lateral", value: $settings.appearance.sidebarWidth, range: 230...360, step: 5)
            }
            Button("Restablecer apariencia") { settings.appearance = AppearanceOptions() }
        }.formStyle(.grouped)
    }

    private var editor: some View {
        Form {
            Section("Texto") {
                FontFacePicker(title: "Fuente del editor", selected: $settings.editor.font)
                pointStepper("Tamaño del editor", value: $settings.editor.fontSize, range: 10...34)
                pointStepper("Interlineado adicional", value: $settings.editor.lineSpacing, range: 0...18)
                pointStepper("Ancho de la columna", value: $settings.editor.columnWidth, range: 480...1200, step: 20)
                Toggle("Ajustar líneas al ancho de la columna", isOn: $settings.editor.wrapLines)
                Toggle("Mostrar recuento de palabras", isOn: $settings.editor.showWordCount)
            }
            Section("Colores") {
                Toggle("Personalizar los colores del editor", isOn: $settings.editor.customColors)
                if settings.editor.customColors {
                    ColorPicker("Fondo del editor", selection: colorBinding(\.paper), supportsOpacity: false)
                    ColorPicker("Texto del editor", selection: colorBinding(\.ink), supportsOpacity: false)
                }
            }
            Section("Al escribir") {
                Toggle("Revisar ortografía mientras escribo", isOn: $settings.editor.spellCheck)
                Toggle("Revisar gramática", isOn: $settings.editor.grammarCheck).disabled(!settings.editor.spellCheck)
                Toggle("Corregir ortografía automáticamente", isOn: $settings.editor.autoCorrect)
                Toggle("Comillas tipográficas", isOn: $settings.editor.smartQuotes)
                Toggle("Guiones tipográficos", isOn: $settings.editor.smartDashes)
                Toggle("Copiar y pegar de forma inteligente", isOn: $settings.editor.smartCopyPaste)
                Toggle("Sustituciones de texto del sistema", isOn: $settings.editor.textReplacement)
            }
            Button("Restablecer editor") { settings.editor = EditorOptions() }
        }.formStyle(.grouped)
    }

    private var library: some View {
        Form {
            Section("Lista de documentos") {
                ChoicePicker("Ordenar por", selection: $settings.list.order)
                Toggle("Mostrar fecha de modificación", isOn: $settings.list.showDates)
                Toggle("Mostrar tipos y estados", isOn: $settings.list.showDetails)
                Toggle("Mostrar etiquetas en resultados", isOn: $settings.list.showTags)
                Toggle("Mostrar extensiones de archivo", isOn: $settings.list.showExtensions)
            }
            Section("Reglas de etiquetado") {
                TagRuleControls(store: store)
            }
        }.formStyle(.grouped)
    }

    private var reading: some View {
        Form {
            Section("PDF") {
                ChoicePicker("Modo de lectura al abrir", selection: $settings.reader.pdfLayout)
                ChoicePicker("Panel inicial", selection: $settings.reader.pdfSidebar)
                ChoicePicker("Zoom inicial", selection: $settings.reader.pdfZoom)
                ChoicePicker("Fondo del visor", selection: $settings.reader.pdfBackground)
                TextField("Autor de las anotaciones", text: $settings.reader.author)
            }
            Section("Canvas") {
                Toggle("Mostrar la cuadrícula de puntos", isOn: $settings.reader.canvasGrid)
                Toggle("Encuadrar el lienzo al abrir", isOn: $settings.reader.fitCanvas)
            }
        }.formStyle(.grouped)
    }

    private func pointStepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int = 1) -> some View {
        HStack {
            Text(title).accessibilityHidden(true)
            Spacer()
            Text("\(value.wrappedValue) pt").monospacedDigit().foregroundStyle(.secondary).accessibilityHidden(true)
            Stepper(title, value: value, in: range, step: step).labelsHidden()
                .accessibilityLabel(title).accessibilityValue("\(value.wrappedValue) puntos")
        }
    }

    private func colorBinding(_ path: WritableKeyPath<EditorOptions, RGBColor>) -> Binding<Color> {
        Binding(get: { settings.editor[keyPath: path].color }, set: { color in
            if let value = RGBColor(color) { settings.editor[keyPath: path] = value }
        })
    }
}

private struct ChoicePicker<Choice: PreferenceChoice>: View {
    let title: String
    @Binding var selection: Choice

    init(_ title: String, selection: Binding<Choice>) {
        self.title = title
        _selection = selection
    }

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(Array(Choice.allCases), id: \.self) { choice in Text(choice.title).tag(choice) }
        }
    }
}

private struct FontFacePicker: View {
    let title: String
    @Binding var selected: String
    @ViewState private var picking = false

    var body: some View {
        HStack {
            Text(title).accessibilityHidden(true)
            Spacer()
            Menu(AppFonts.label(selected)) {
                ForEach([AppFonts.quattro, AppFonts.quattroBold, AppFonts.jetbrainsLight, AppFonts.system], id: \.self) { name in
                    Button { selected = name } label: {
                        if selected == name { Label(AppFonts.label(name), systemImage: "checkmark") }
                        else { Text(AppFonts.label(name)) }
                    }
                }
                Divider()
                Button("Elegir fuente instalada…") { picking = true }
            }.accessibilityLabel(title).accessibilityValue(AppFonts.label(selected))
        }
        .sheet(isPresented: $picking) { InstalledFonts(selected: $selected, title: title) }
    }
}

private struct InstalledFonts: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selected: String
    let title: String
    @ViewState private var query = ""
    @ViewState private var family: String?
    @ViewState private var face: String?

    var body: some View {
        let manager = NSFontManager.shared
        let families = manager.availableFontFamilies.filter { query.isEmpty || $0.localizedStandardContains(query) }
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            TextField("Buscar familia tipográfica", text: $query)
            List(families, id: \.self, selection: $family) { Text($0).tag($0) }.frame(height: 220)
            if let family, let faces = manager.availableMembers(ofFontFamily: family) {
                Picker("Estilo", selection: $face) {
                    ForEach(faces.compactMap(FontMember.init), id: \.name) { member in
                        Text(member.style).tag(Optional(member.name))
                    }
                }
            }
            Text("El cielo de noviembre. 0123456789")
                .font(face.map { .custom($0, fixedSize: 17) } ?? .system(size: 17))
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                Button("Usar fuente") { if let face { selected = face; dismiss() } }
                    .keyboardShortcut(.defaultAction).disabled(face == nil)
            }
        }
        .padding(22).frame(width: 440)
        .onAppear { family = NSFont(name: selected, size: 13)?.familyName; face = selected == AppFonts.system ? nil : selected }
        .onChange(of: family) { _, family in
            let members = family.flatMap { manager.availableMembers(ofFontFamily: $0) }?.compactMap(FontMember.init) ?? []
            if !members.contains(where: { $0.name == face }) { face = members.first?.name }
        }
    }
}

private struct FontMember {
    let name: String
    let style: String

    init?(_ values: [Any]) {
        guard values.count >= 2, let name = values[0] as? String, let style = values[1] as? String else { return nil }
        self.name = name
        self.style = style
    }
}
