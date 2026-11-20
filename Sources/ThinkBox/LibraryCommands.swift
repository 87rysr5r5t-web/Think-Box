import SwiftUI
import WritingLibrary

enum LibraryCommand: CaseIterable, Identifiable {
    case newText, newCanvas, newProject, newTag, importFiles, exportFile, copyLink
    case sidebar, search, inbox, trash, palette, goTo
    case results, inspector, wide, stacked, listOnly, focus, back, forward, newTab, closeTab, openWindow

    var id: Self { self }

    var title: String {
        switch self {
        case .newText: "Nuevo texto"
        case .newCanvas: "Nuevo canvas"
        case .newProject: "Nuevo proyecto"
        case .newTag: "Nueva etiqueta"
        case .importFiles: "Importar archivos…"
        case .exportFile: "Exportar documento…"
        case .copyLink: "Copiar enlace de objeto"
        case .sidebar: "Mostrar u ocultar barra lateral"
        case .search: "Buscar en esta vista"
        case .inbox: "Ir a Entrada"
        case .trash: "Ir a Papelera"
        case .palette: "Paleta de comandos…"
        case .goTo: "Ir a documento o proyecto…"
        case .results: "Mostrar u ocultar lista"
        case .inspector: "Mostrar u ocultar inspector"
        case .wide: WorkspaceLayout.wide.title
        case .stacked: WorkspaceLayout.stacked.title
        case .listOnly: WorkspaceLayout.listOnly.title
        case .focus: "Alternar modo enfoque"
        case .back: "Atrás"
        case .forward: "Adelante"
        case .newTab: "Nueva pestaña"
        case .closeTab: "Cerrar pestaña de biblioteca"
        case .openWindow: "Abrir documento en ventana nueva"
        }
    }

    var shortcut: KeyboardShortcut? {
        switch self {
        case .newText: KeyboardShortcut("n")
        case .importFiles: KeyboardShortcut("i", modifiers: [.command, .shift])
        case .search: KeyboardShortcut("f")
        case .sidebar: KeyboardShortcut("l", modifiers: [.command, .shift])
        case .palette: KeyboardShortcut("p", modifiers: [.command, .shift])
        case .goTo: KeyboardShortcut("p")
        case .results: KeyboardShortcut("j", modifiers: [.command, .shift])
        case .inspector: KeyboardShortcut("i", modifiers: [.command, .option])
        case .back: KeyboardShortcut("[")
        case .forward: KeyboardShortcut("]")
        case .newTab: KeyboardShortcut("t")
        case .closeTab: KeyboardShortcut("w", modifiers: [.command, .shift])
        default: nil
        }
    }

    var shortcutLabel: String? {
        guard let shortcut else { return nil }
        let keys = shortcut.modifiers
        return (keys.contains(.option) ? "⌥" : "") + (keys.contains(.shift) ? "⇧" : "")
            + (keys.contains(.command) ? "⌘" : "") + String(shortcut.key.character).uppercased()
    }
}

struct LibraryCommandContext {
    var allows: (LibraryCommand) -> Bool
    var run: (LibraryCommand) -> Void
}

private struct LibraryCommandKey: FocusedValueKey { typealias Value = LibraryCommandContext }

extension FocusedValues {
    var libraryCommands: LibraryCommandContext? {
        get { self[LibraryCommandKey.self] }
        set { self[LibraryCommandKey.self] = newValue }
    }
}

struct LibraryMenuCommands: Commands {
    @FocusedValue(\.libraryCommands) private var context

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            buttons([.newText, .newCanvas, .newProject, .newTag, .newTab, .closeTab, .openWindow])
            Divider()
            buttons([.importFiles, .exportFile])
        }
        CommandGroup(after: .pasteboard) { buttons([.copyLink]) }
        CommandGroup(after: .sidebar) {
            buttons([.sidebar, .results, .inspector])
            Menu("Disposición") { buttons([.wide, .stacked, .listOnly, .focus]) }
        }
        CommandMenu("Ir") { buttons([.back, .forward, .goTo, .inbox, .trash]) }
        CommandMenu("Herramientas") { buttons([.search, .palette]) }
    }

    private func buttons(_ commands: [LibraryCommand]) -> some View {
        ForEach(commands) { command in
            Button(command.title) { context?.run(command) }
                .keyboardShortcut(command.shortcut)
                .disabled(context?.allows(command) != true)
        }
    }
}

struct QuickAction: Identifiable {
    let id: String
    let title: String
    var detail: String?
    let run: () -> Void
}

struct CommandPalette: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchFocused: Bool
    @ViewState private var query = ""
    @ViewState private var selected: String?
    var title: String
    var entries: [QuickAction]
    var choose: (QuickAction) -> Void

    private var results: [QuickAction] {
        let filter = FuzzyTitleQuery(query)
        return entries.filter { filter.matches($0.title) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField(title, text: $query).textFieldStyle(.roundedBorder)
                .focused($searchFocused).padding(DesignTokens.palettePadding)
                .onSubmit { if let entry = results.first(where: { $0.id == selected }) ?? results.first { choose(entry) } }
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.upArrow) { move(-1); return .handled }
            Divider()
            if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                ScrollViewReader { scroll in
                    List(results, selection: $selected) { entry in
                        Button { choose(entry) } label: {
                            HStack {
                                Text(entry.title)
                                Spacer()
                                if let detail = entry.detail { Text(detail).foregroundStyle(.secondary) }
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).tag(entry.id)
                    }
                    .onChange(of: selected) { if let selected { scroll.scrollTo(selected) } }
                }
            }
        }
        .frame(width: DesignTokens.paletteWidth, height: DesignTokens.paletteHeight)
        .onAppear { searchFocused = true; selected = results.first?.id }
        .onChange(of: query) { selected = results.first?.id }
        .onExitCommand { dismiss() }
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        let index = results.firstIndex { $0.id == selected } ?? 0
        selected = results[min(results.count - 1, max(0, index + delta))].id
    }

}
