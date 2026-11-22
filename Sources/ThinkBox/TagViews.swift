import SwiftUI
import WritingLibrary

struct TagEditor: View {
    @Environment(AppSettings.self) private var settings
    var tags: [String]
    var suggestions: [String]
    var change: ([String]) -> Void
    var reveal: ((String) -> Void)?
    @ViewState private var input = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !tags.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        ForEach(tags, id: \.self) { tag in
                            HStack(spacing: 4) {
                                if let reveal {
                                    Button(tag) { reveal(tag) }.buttonStyle(.plain)
                                } else {
                                    Text(tag)
                                }
                                Button("Quitar \(tag)", line: "xmark") {
                                    change(tags.filter { $0 != tag })
                                }
                                .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
                            }
                            .font(settings.font(-2))
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(.tint.opacity(0.12), in: Capsule())
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            HStack {
                TextField("Etiqueta o ruta/nivel", text: $input).accessibilityLabel("Añadir etiquetas")
                    .onSubmit(add)
                Button("Añadir", action: add).disabled(TagPath.list(input).isEmpty)
                if !suggestions.isEmpty {
                    Menu("Etiquetas existentes") {
                        ForEach(suggestions.filter { input.isEmpty || $0.localizedStandardContains(input) }, id: \.self) { tag in
                            Button(tag) { change(TagPath.unique(tags + [tag])); input = "" }
                        }
                    }.labelsHidden().fixedSize()
                }
            }
        }
    }

    private func add() {
        change(TagPath.unique(tags + TagPath.list(input)))
        input = ""
    }
}

struct FragmentTagSheet: View {
    @Environment(\.dismiss) private var dismiss
    let fragment: DocumentFragment
    let tags: [String]
    let complete: ([String]) -> Void
    @ViewState private var selected: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Etiquetar fragmento").font(.title2.weight(.semibold))
            Text(fragment.quote).lineLimit(4).foregroundStyle(.secondary).textSelection(.enabled)
            TagEditor(tags: selected, suggestions: tags, change: { selected = $0 })
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                Button("Guardar") { complete(selected); dismiss() }.keyboardShortcut(.defaultAction)
                    .disabled(selected.isEmpty && fragment.tags.isEmpty)
            }
        }
        .padding(22).frame(width: 420)
        .onAppear { selected = fragment.tags }
    }
}

struct TagPreferences: View {
    @Environment(\.dismiss) private var dismiss
    var store: LibraryStore

    var body: some View {
        Form {
            TagRuleControls(store: store)
            Button("Cerrar") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding(22).frame(width: 450)
    }
}

struct TagRuleControls: View {
    var store: LibraryStore

    var body: some View {
        Toggle("Usar el nombre del grupo como etiqueta", isOn: setting(\.projectNames))
        Toggle("Heredar las etiquetas de los grupos", isOn: setting(\.inheritProjectTags))
        Toggle("Leer hashtags en líneas independientes de Markdown", isOn: setting(\.hashtags))
        Toggle("Intercambiar etiquetas con Finder al importar y exportar", isOn: setting(\.finderTags))
        Toggle("Importar las palabras clave de los PDF", isOn: setting(\.pdfKeywords))
    }

    private func setting(_ key: WritableKeyPath<TagSettings, Bool>) -> Binding<Bool> {
        Binding(get: { store.library.tagging[keyPath: key] }, set: { value in
            store.commit { library in
                var options = library.tagging
                options[keyPath: key] = value
                library.tagSettings = options
            }
        })
    }
}

struct ProjectTags: View {
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    var store: LibraryStore

    var body: some View {
        if let project = store.library.projects.first(where: { $0.id == id }) {
            VStack(alignment: .leading, spacing: 14) {
                Text(project.name).font(.title2.weight(.semibold))
                TagEditor(tags: project.tags ?? [], suggestions: store.library.availableTags, change: { tags in
                    update { $0.tags = tags }
                })
                Toggle("Excluir de las etiquetas dinámicas", isOn: Binding(
                    get: { project.excludedFromTagging ?? false }, set: { value in update { $0.excludedFromTagging = value } }
                ))
                Button("Cerrar") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(22).frame(width: 420)
        }
    }

    private func update(_ change: (inout Project) -> Void) {
        store.commit { library in
            if let index = library.projects.firstIndex(where: { $0.id == id }) { change(&library.projects[index]) }
        }
    }
}
