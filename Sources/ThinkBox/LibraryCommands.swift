import AppKit
import SwiftUI
import WritingLibrary

enum LibraryCommand: CaseIterable, Identifiable {
    case newText, newCanvas, newProject, newTag, importFiles, exportFile, copyLink
    case newDatabase, openDatabase, moveToTrash, putBack
    case sidebar, search, inbox, trash, palette, goTo, saveWorkspace, restoreWorkspace, manageWorkspaces
    case results, inspector, wide, stacked, listOnly, focus, back, forward, newTab, closeTab, openWindow

    case pageEditor, pagePreview, pageBoth, pageNone, pageSetup, pageBreak, pageGo
    case pagePDF, pagePrint, pageZoomIn, pageZoomOut, pageZoomReset, pageOutline

    var id: Self { self }

    var isPageCommand: Bool {
        switch self {
        case .pageEditor, .pagePreview, .pageBoth, .pageNone, .pageSetup, .pageBreak, .pageGo,
             .pagePDF, .pagePrint, .pageZoomIn, .pageZoomOut, .pageZoomReset, .pageOutline: true
        default: false
        }
    }

    var title: String {
        switch self {
        case .newText: "Nuevo texto Markdown"
        case .newCanvas: "Nuevo canvas"
        case .newProject: "Nuevo grupo"
        case .newTag: "Nueva etiqueta"
        case .importFiles: "Importar archivos…"
        case .exportFile: "Exportar documento…"
        case .copyLink: "Copiar enlace de objeto"
        case .newDatabase: "Nueva base de datos…"
        case .openDatabase: "Abrir base de datos…"
        case .moveToTrash: "Mover a la papelera"
        case .putBack: "Restaurar de la papelera"
        case .saveWorkspace: "Guardar espacio de trabajo…"
        case .restoreWorkspace: "Restaurar espacio de trabajo…"
        case .manageWorkspaces: "Gestionar espacios de trabajo…"
        case .sidebar: "Mostrar u ocultar barra lateral"
        case .search: "Buscar en esta vista"
        case .inbox: "Ir a Entrada"
        case .trash: "Ir a Papelera"
        case .palette: "Paleta de comandos…"
        case .goTo: "Ir a documento o grupo…"
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
        case .pageEditor: "Vista de página en el editor"
        case .pagePreview: "Vista de página en la previsualización"
        case .pageBoth: "Vista de página en ambos paneles"
        case .pageNone: "Desactivar la vista de página"
        case .pageSetup: "Configurar página…"
        case .pageBreak: "Insertar salto de página"
        case .pageGo: "Ir a página…"
        case .pageOutline: "Mostrar u ocultar esquema"
        case .pagePDF: "Exportar a PDF…"
        case .pagePrint: "Imprimir…"
        case .pageZoomIn: "Acercar página"
        case .pageZoomOut: "Alejar página"
        case .pageZoomReset: "Ajustar a la página"
        }
    }

    var shortcut: KeyboardShortcut? {
        switch self {
        case .saveWorkspace: KeyboardShortcut("s", modifiers: [.command, .option, .shift])
        case .openDatabase: KeyboardShortcut("o")
        case .moveToTrash: KeyboardShortcut(.delete)
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
        case .pageOutline: KeyboardShortcut("o", modifiers: [.command, .option])
        case .pageEditor: KeyboardShortcut("1", modifiers: [.command, .option])
        case .pagePreview: KeyboardShortcut("2", modifiers: [.command, .option])
        case .pageBoth: KeyboardShortcut("3", modifiers: [.command, .option])
        case .pageNone: KeyboardShortcut("0", modifiers: [.command, .option])
        case .pageBreak: KeyboardShortcut(.return, modifiers: [.command])
        case .pagePrint: KeyboardShortcut("p", modifiers: [.command, .option])
        case .pageZoomIn: KeyboardShortcut("+")
        case .pageZoomOut: KeyboardShortcut("-")
        case .pageZoomReset: KeyboardShortcut("0")
        default: nil
        }
    }

    var shortcutLabel: String? {
        guard let shortcut else { return nil }
        let keys = shortcut.modifiers
        let key = switch shortcut.key {
        case .return: "↩"
        case .delete: "⌫"
        default: String(shortcut.key.character).uppercased()
        }
        return (keys.contains(.control) ? "⌃" : "") + (keys.contains(.option) ? "⌥" : "")
            + (keys.contains(.shift) ? "⇧" : "") + (keys.contains(.command) ? "⌘" : "") + key
    }
}

struct LibraryCommandContext {
    var allows: (LibraryCommand) -> Bool
    var run: (LibraryCommand) -> Void
    var isSelected: (LibraryCommand) -> Bool = { _ in false }

    var paletteEntries: [QuickAction] {
        LibraryCommand.allCases.filter { $0 != .palette && allows($0) }.map { command in
            QuickAction(id: String(describing: command), title: command.title, detail: command.shortcutLabel) { run(command) }
        }
    }
}

extension AppSettings {
    func writingViews(for document: WritingDocument) -> WritingPageViews {
        if let views = document.pageViews { return views }
        if document.richTextData != nil {
            if ["html", "htm"].contains(document.richTextFormat ?? "") { return pages.html ?? WritingPageViews() }
            return pages.richText ?? WritingPageViews()
        }
        return document.plainText == true ? pages.plainText : pages.markdown
    }

    func allowsPageCommand(_ command: LibraryCommand, for document: WritingDocument) -> Bool {
        if let asset = document.attachment { return asset.kind == .pdf && command == .pagePrint }
        let views = writingViews(for: document)
        switch command {
        case .pageGo, .pageZoomIn, .pageZoomOut, .pageZoomReset:
            return (views.mode != .preview && views.editor) || (views.mode != .source && views.preview)
        case .pageBreak: return document.trashedAt == nil
        default: return command.isPageCommand
        }
    }
}

struct PageCommandRequest: Equatable {
    let id = UUID()
    let command: LibraryCommand
    let document: UUID
}

private struct PageCommandKey: FocusedValueKey { typealias Value = LibraryCommandContext }

private struct LibraryCommandKey: FocusedValueKey { typealias Value = LibraryCommandContext }

extension FocusedValues {
    var pageCommands: LibraryCommandContext? {
        get { self[PageCommandKey.self] }
        set { self[PageCommandKey.self] = newValue }
    }

    var libraryCommands: LibraryCommandContext? {
        get { self[LibraryCommandKey.self] }
        set { self[LibraryCommandKey.self] = newValue }
    }
}

struct LibraryMenuCommands: Commands {
    @FocusedValue(\.libraryCommands) private var context
    @FocusedValue(\.pageCommands) private var pageContext

    var body: some Commands {
        // Estructura de menús siguiendo DEVONthink (MN-FILE, MN-EDIT, MN-DATA, MN-VIEW, MN-GO, MN-TOOLS, MN-WIN).
        // Todas las entradas salen del registro compartido con la paleta y solo se muestran las que existen.
        CommandGroup(replacing: .newItem) {
            buttons([.newDatabase, .openDatabase])
            Divider()
            buttons([.newTab, .openWindow, .closeTab])
            Divider()
            buttons([.importFiles, .exportFile, .pagePDF])
        }
        CommandGroup(replacing: .printItem) {
            buttons([.pageSetup])
            buttons([.pagePrint])
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            buttons([.copyLink])
        }
        CommandMenu("Datos") {
            Menu("Nuevo") { buttons([.newText, .newCanvas, .newProject, .newTag]) }
            Divider()
            buttons([.moveToTrash, .putBack])
        }
        CommandMenu("Formato") { buttons([.pageSetup, .pageBreak]) }
        CommandGroup(after: .sidebar) {
            Menu("Mostrar/Ocultar") { buttons([.sidebar, .results, .inspector, .pageOutline]) }
            Menu("Disposición") { buttons([.wide, .stacked, .listOnly]) }
            buttons([.focus])
            Divider()
            Menu("Vista de página") { buttons([.pageEditor, .pagePreview, .pageBoth, .pageNone]) }
            Menu("Zoom") { buttons([.pageZoomIn, .pageZoomOut, .pageZoomReset]) }
        }
        CommandMenu("Ir") {
            buttons([.back, .forward])
            Divider()
            buttons([.goTo, .pageGo])
            Divider()
            buttons([.inbox, .trash])
        }
        CommandMenu("Herramientas") {
            buttons([.search, .palette])
        }
        CommandGroup(before: .windowArrangement) {
            Menu("Espacios de trabajo") { buttons([.saveWorkspace, .restoreWorkspace, .manageWorkspaces]) }
            Divider()
        }
    }

    private func buttons(_ commands: [LibraryCommand]) -> some View {
        ForEach(commands) { command in
            let active = command.isPageCommand ? pageContext : context
            Button { active?.run(command) } label: {
                if active?.isSelected(command) == true { Label(command.title, systemImage: "checkmark") }
                else { Text(command.title) }
            }
                .keyboardShortcut(command.shortcut)
                .disabled(active?.allows(command) != true)
        }
    }

    static func orderNativeMenus() {
        guard let bar = NSApp.mainMenu, let go = bar.items.first(where: { $0.title == "Ir" }),
              let view = bar.items.first(where: { item in
                  item.submenu?.items.contains { $0.title == LibraryCommand.sidebar.title } == true
              }),
              bar.index(of: view) != bar.index(of: go) - 1 else { return }
        bar.removeItem(view)
        bar.insertItem(view, at: bar.index(of: go))
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
