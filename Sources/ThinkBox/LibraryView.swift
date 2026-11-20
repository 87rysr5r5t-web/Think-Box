import SwiftUI
import WritingLibrary

struct LibraryView: View {
    var store: LibraryStore
    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openWindow) private var openWindow
    @ViewState private var scope: LibraryScope = .all
    @ViewState private var selection: ItemDestination?
    @ViewState private var jump: JumpRequest?
    @ViewState private var fragmentToEdit: LibraryResult?
    @ViewState private var showTagSettings = false
    @ViewState private var projectForTags: UUID?
    @ViewState private var tagToRemove: String?
    @ViewState private var query = ""
    @ViewState private var dialog: CreationDialog?
    @ViewState private var titleFocusRequest: UUID?
    @ViewState private var quickMode: LibraryCommand?
    @ViewState private var queuedQuickAction: QuickAction?
    @ViewState private var tabs = [LibraryTab()]
    @ViewState private var activeTab = 0
    @ViewState private var inspectorSection = InspectorSection.details
    @ViewState private var lastLayout = WorkspaceLayout.wide
    @SceneStorage("workspace.layout") private var layoutsData = Data()
    @SceneStorage("workspace.inspector") private var inspectorVisible = false
    @SceneStorage("workspace.list") private var listVisible = true
    @SceneStorage("workspace.listWidth") private var listWidth = 250.0
    @SceneStorage("workspace.listHeight") private var listHeight = 225.0
    @SceneStorage("workspace.inspectorWidth") private var inspectorWidth = 285.0
    @FocusState private var searchFocused: Bool

    private var palette: WindowPalette { WindowPalette(scheme: scheme) }
    private var rowPadding: CGFloat { settings.appearance.compactRows ? 3 : 6 }

    var body: some View {
        Group {
            if let error = store.openError {
                ContentUnavailableView("No se pudo abrir la biblioteca", systemImage: "exclamationmark.triangle",
                                       description: Text(error))
            } else {
                VStack(spacing: 0) {
                    toolbar
                    rule
                    if tabs.count > 1 { tabBar; rule }
                    GeometryReader { geometry in
                        HStack(spacing: 0) {
                            if settings.appearance.showSidebar && layout != .focus {
                                sidebar.frame(width: min(CGFloat(settings.appearance.sidebarWidth), geometry.size.width * 0.23))
                                WorkspaceDivider(color: palette.border, extent: CGFloat(settings.appearance.sidebarWidth), resize: {
                                    settings.appearance.sidebarWidth = Int(min(360, max(230, $0)))
                                }) { run(.sidebar) }
                            }
                            centralWorkspace(width: geometry.size.width)
                            if inspectorVisible && layout != .focus {
                                WorkspaceDivider(color: palette.border, extent: -inspectorWidth, resize: {
                                    inspectorWidth = min(380, max(230, -$0))
                                }) { run(.inspector) }
                                inspector.frame(width: min(inspectorWidth, geometry.size.width * 0.27))
                            }
                        }
                    }
                    rule
                    statusBar
                }
            }
        }
        .tint(palette.tint)
        .background(palette.workspace)
        .focusedSceneValue(\.libraryCommands, LibraryCommandContext(allows: allows, run: { run($0) }))
        .sheet(item: $quickMode, onDismiss: {
            let action = queuedQuickAction
            queuedQuickAction = nil
            action?.run()
        }) { mode in
            CommandPalette(title: mode.title, entries: quickEntries(mode)) { entry in
                queuedQuickAction = entry
                quickMode = nil
            }
        }
        .sheet(item: $dialog) { item in
            CreationForm(dialog: item) { name in
                switch item {
                case .project:
                    if let id = store.createProject(name) { setScope(.project(id)) }
                case .savedSearch(let search):
                    if let id = store.createSavedSearch(name: name, query: search) { setScope(.savedSearch(id)) }
                case .tag, .renameTagSeed:
                    let path = TagPath.normalize(name)
                    if !path.isEmpty, store.commit({ $0.createTag(path) }) { setScope(.tag(path)) }
                case .renameTag(let previous):
                    let path = TagPath.normalize(name)
                    if !path.isEmpty, store.commit({ $0.replaceTag(previous, with: path) }) { setScope(.tag(path)) }
                }
            }
        }
        .sheet(isPresented: $showTagSettings) { TagPreferences(store: store) }
        .sheet(isPresented: Binding(get: { projectForTags != nil }, set: { if !$0 { projectForTags = nil } })) {
            if let projectForTags { ProjectTags(id: projectForTags, store: store) }
        }
        .sheet(item: $fragmentToEdit) { hit in
            if let fragment = hit.fragment {
                FragmentTagSheet(fragment: fragment, tags: store.library.availableTags) { store.setTags($0, at: hit.id) }
            }
        }
        .confirmationDialog("Quitar etiqueta y subetiquetas", isPresented: Binding(
            get: { tagToRemove != nil }, set: { if !$0 { tagToRemove = nil } }
        ), titleVisibility: .visible) {
            Button("Quitar etiquetas", role: .destructive) {
                if let tag = tagToRemove, store.commit({ $0.replaceTag(tag, with: nil) }) { setScope(.all) }
                tagToRemove = nil
            }
        } message: { Text("Se quitarán las asignaciones de esta rama. Los documentos y fragmentos seguirán en la biblioteca.") }
        .alert("Think Box", isPresented: Binding(
            get: { store.actionError != nil }, set: { if !$0 { store.actionError = nil } }
        )) {
            Button("Aceptar", role: .cancel) { store.actionError = nil }
        } message: {
            Text(store.actionError ?? "")
        }
        .onOpenURL { url in
            if let target = ItemDestination(url: url) { openDocument(target) }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text("Navegación").font(settings.font(-1, bold: true)).padding(.leading, 3)
                Spacer(minLength: 0)
                Menu {
                    ForEach([LibraryCommand.newProject, .importFiles, .newCanvas, .palette]) { command in
                        Button(command.title) { run(command) }
                    }
                    Button("Reglas de etiquetado…", systemImage: "tag") { showTagSettings = true }
                } label: {
                    ChromeSymbol(name: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Acciones de biblioteca")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)

            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    scopeButton("Todos los documentos", icon: "square.on.square", destination: .all)
                    scopeButton("Entrada", icon: "tray", destination: .inbox)
                    scopeButton("Borradores", icon: "pencil", destination: .drafts)
                    scopeButton("Papelera", icon: "trash", destination: .trash)
                    sectionHeader("Proyectos") {
                        Button(LibraryCommand.newProject.title, systemImage: "plus") { run(.newProject) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.plain)
                            .help("Nuevo proyecto")
                    }
                    ForEach(store.library.projects) { project in
                        scopeButton(project.name, icon: "folder", destination: .project(project.id))
                            .contextMenu { Button("Etiquetas del proyecto…") { projectForTags = project.id } }
                    }
                    tagsSection
                    if !store.library.savedSearches.isEmpty {
                        sectionHeader("Búsquedas guardadas") { EmptyView() }
                        ForEach(store.library.savedSearches) { search in
                            scopeButton(search.name, icon: "bookmark", destination: .savedSearch(search.id))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 9)
            }
            sidebarFooter
        }
        .background(palette.sidebar)
    }

    private var resultsPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text(scopeTitle).font(settings.font(-1, bold: true)).lineLimit(1)
                Spacer()
                if layout != .listOnly { chrome(.results, symbol: "line.3.horizontal", label: "Ocultar lista") }
            }.padding(.horizontal, 12).padding(.top, 5)
            HStack(spacing: 8) {
                ChromeSymbol(name: "magnifyingglass", size: 12).foregroundStyle(.secondary)
                TextField("Buscar en esta vista", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .accessibilityIdentifier("library-search")
                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("Guardar búsqueda para toda la biblioteca", systemImage: "bookmark") {
                        dialog = .savedSearch(query.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .help("Guardar búsqueda para toda la biblioteca")
                    Button("Borrar búsqueda", systemImage: "xmark") { query = "" }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .background(palette.selection.opacity(0.55), in: .rect(cornerRadius: DesignTokens.rowRadius))
            .overlay { RoundedRectangle(cornerRadius: DesignTokens.rowRadius).strokeBorder(palette.border) }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)

            documentList
        }
        .background(palette.workspace)
    }

    private var sidebarFooter: some View {
        HStack(spacing: 4) {
            SettingsLink {
                HStack(spacing: 6) {
                    ChromeSymbol(name: "gearshape")
                    Text("Ajustes")
                }
            }.buttonStyle(ChromeButtonStyle()).accessibilityLabel("Ajustes")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .overlay(alignment: .top) { Rectangle().fill(palette.border).frame(height: 1) }
    }

    private var tagsSection: some View {
        Group {
            sectionHeader("Etiquetas") {
                Button(LibraryCommand.newTag.title, systemImage: "plus") { run(.newTag) }
                    .labelStyle(.iconOnly).buttonStyle(.plain).help("Nueva etiqueta")
            }
            OutlineGroup(store.library.tagTree, children: \.children) { branch in
                scopeButton(branch.name, icon: "tag", destination: .tag(branch.id))
                    .help(branch.id)
                    .draggable("thinkbox-tag:" + branch.id)
                    .dropDestination(for: String.self) { values, _ in drop(values, on: branch.id) }
                    .contextMenu {
                        Button("Nueva subetiqueta…") { dialog = .renameTagSeed(branch.id + "/") }
                        Button("Cambiar nombre o ruta…") { dialog = .renameTag(branch.id) }
                        Button("Añadir al filtro") {
                            let clause = "tag:\"\(branch.id)\""
                            query = query.isEmpty ? clause : query + " " + clause
                        }
                        if let selection {
                            Button("Asignar a la selección") {
                                guard let item = store.document(selection.documentID) else { return }
                                let tags = selection.fragmentID.flatMap { id in item.fragments?.first { $0.id == id }?.tags }
                                    ?? item.tags
                                store.setTags(TagPath.unique(tags + [branch.id]), at: selection)
                            }
                        }
                        Divider()
                        Button("Quitar etiqueta y subetiquetas…", role: .destructive) { tagToRemove = branch.id }
                    }
            }
        }
    }

    private func sectionHeader<Content: View>(_ label: String, @ViewBuilder action: () -> Content) -> some View {
        HStack {
            Text(label).font(settings.font(-1))
            Spacer()
            action()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .padding(.bottom, 3)
    }

    private func scopeButton(_ title: String, icon: String, destination: LibraryScope) -> some View {
        Button { setScope(destination) } label: {
            HStack(spacing: 8) {
                ChromeSymbol(name: icon, size: 13).frame(width: 15)
                Text(title).font(settings.font(bold: scope == destination))
            }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, rowPadding)
                .contentShape(Rectangle())
                .background {
                    if scope == destination { RoundedRectangle(cornerRadius: DesignTokens.rowRadius).fill(palette.selection) }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(scope == destination ? .isSelected : [])
    }

    private var documentList: some View {
        let results = store.library.results(in: scope, matching: query)
        let documents = settings.list.order == .title ? results.sorted { first, second in
            let order = listTitle(first.document).localizedStandardCompare(listTitle(second.document))
            if order == .orderedSame { return first.id.url.absoluteString < second.id.url.absoluteString }
            return order == .orderedAscending
        } : results
        return Group {
            if documents.isEmpty {
                Text(query.isEmpty ? "No hay documentos en esta vista" : "Sin resultados")
                    .font(settings.font(list: true))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 19)
                    .padding(.top, 12)
            } else {
                List(documents, selection: resultSelection) { hit in
                    VStack(alignment: .leading, spacing: 4) {
                        if let fragment = hit.fragment {
                            HStack(alignment: .top, spacing: 5) {
                                ChromeSymbol(name: "quote.opening", size: 11).padding(.top, 2)
                                Text(fragment.quote).lineLimit(2)
                            }.font(settings.font(list: true))
                            Text(listTitle(hit.document)).font(settings.font(-2, list: true)).foregroundStyle(.secondary).lineLimit(1)
                        } else {
                            Text(listTitle(hit.document)).font(settings.font(list: true)).lineLimit(1)
                            if settings.list.showDetails || settings.list.showDates {
                                HStack(spacing: 6) {
                                    if settings.list.showDetails { Text(hit.document.attachment?.kind.label ?? hit.document.stage.title) }
                                    Spacer(minLength: 0)
                                    if settings.list.showDates { Text(hit.document.modifiedAt, format: .dateTime.day().month(.abbreviated)) }
                                }.font(settings.font(-2, list: true)).foregroundStyle(.secondary)
                            }
                        }
                        let tags = hit.fragment?.tags ?? store.library.effectiveTags(of: hit.document)
                        if settings.list.showTags && !tags.isEmpty {
                            Text(tags.joined(separator: " · ")).font(settings.font(-2, list: true)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .padding(.vertical, rowPadding)
                    .tag(hit.id)
                    .draggable(hit.id.url.absoluteString)
                    .contextMenu {
                        Button(LibraryCommand.copyLink.title) { run(.copyLink, target: hit.id) }
                        Button(LibraryCommand.exportFile.title) { run(.exportFile, target: hit.id) }
                        Button("Abrir en pestaña nueva") { openTab(at: hit.id) }
                        Button(LibraryCommand.openWindow.title) { run(.openWindow, target: hit.id) }
                        Button("Abrir en el visor") {
                            if layout == .listOnly { setLayout(.wide) }
                            visit(LibraryLocation(scope: scope, selection: hit.id, target: hit.id, query: query))
                        }
                        if hit.fragment != nil {
                            Button("Ir al fragmento") { openDocument(hit.id) }
                            Button("Editar etiquetas del fragmento…") { fragmentToEdit = hit }
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func listTitle(_ document: WritingDocument) -> String {
        guard settings.list.showExtensions else { return document.displayTitle }
        let ext = document.attachment.map { ($0.filename as NSString).pathExtension } ?? "md"
        guard !ext.isEmpty, !document.displayTitle.lowercased().hasSuffix("." + ext.lowercased()) else { return document.displayTitle }
        return document.displayTitle + "." + ext
    }

    private var resultSelection: Binding<ItemDestination?> {
        Binding(get: { selection }, set: { destination in
            visit(LibraryLocation(scope: scope, selection: destination, target: destination, query: query))
        })
    }

    private func drop(_ values: [String], on tag: String) -> Bool {
        var accepted = false
        for value in values {
            if let url = URL(string: value), let target = ItemDestination(url: url),
               let document = store.document(target.documentID), document.trashedAt == nil {
                let tags: [String]
                if let id = target.fragmentID {
                    guard let fragment = document.fragments?.first(where: { $0.id == id }) else { continue }
                    tags = fragment.tags
                } else { tags = document.tags }
                store.setTags(TagPath.unique(tags + [tag]), at: target)
                accepted = true
            } else if value.hasPrefix("thinkbox-tag:") {
                let origin = String(value.dropFirst("thinkbox-tag:".count))
                guard store.library.availableTags.contains(origin), !TagPath.includes(tag, tag: origin),
                      let leaf = origin.split(separator: "/").last else { continue }
                let destination = tag + "/" + leaf
                if store.commit({ $0.replaceTag(origin, with: destination) }) {
                    if case .tag(let current) = scope, TagPath.includes(current, tag: origin) { setScope(.tag(destination)) }
                    accepted = true
                }
            }
        }
        return accepted
    }

    private var rule: some View { Rectangle().fill(palette.border).frame(height: DesignTokens.divider) }

    private var layouts: [String: WorkspaceLayout] {
        (try? JSONDecoder().decode([String: WorkspaceLayout].self, from: layoutsData)) ?? [:]
    }

    private var layoutKey: String {
        if case .project(let id) = scope { return id.uuidString }
        return "window"
    }

    private var layout: WorkspaceLayout { layouts[layoutKey] ?? layouts["window"] ?? .wide }

    private func setLayout(_ value: WorkspaceLayout) {
        if layout != .focus { lastLayout = layout }
        var values = layouts
        values[layoutKey] = value
        if let encoded = try? JSONEncoder().encode(values) { layoutsData = encoded }
    }

    private func centralWorkspace(width: CGFloat) -> some View {
        let stacked = layout == .stacked
        let arrangement = stacked ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        return arrangement {
            if (listVisible && layout != .focus) || layout == .listOnly {
                resultsPane.frame(width: !stacked && layout != .listOnly ? min(listWidth, width * 0.25) : nil,
                                  height: stacked ? listHeight : nil)
                    .frame(maxWidth: layout == .listOnly || stacked ? .infinity : nil, maxHeight: stacked ? nil : .infinity)
                if layout != .listOnly {
                    WorkspaceDivider(color: palette.border, vertical: !stacked, extent: stacked ? listHeight : listWidth, resize: {
                        if stacked { listHeight = min(320, max(160, $0)) }
                        else { listWidth = min(365, max(175, $0)) }
                    }) { run(.results) }
                }
            }
            if layout != .listOnly {
                workspace.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chrome(_ command: LibraryCommand, symbol: String, label: String? = nil) -> some View {
        Button { run(command) } label: { ChromeSymbol(name: symbol) }
            .buttonStyle(ChromeButtonStyle())
            .accessibilityLabel(label ?? command.title)
            .help(label ?? command.title)
            .disabled(!allows(command))
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            chrome(.sidebar, symbol: "sidebar.left", label: settings.appearance.showSidebar && layout != .focus ? "Ocultar barra lateral" : "Mostrar barra lateral")
            chrome(.back, symbol: "chevron.left")
            chrome(.forward, symbol: "chevron.right")
            Button("Biblioteca") { setScope(.all) }.buttonStyle(.plain).foregroundStyle(.secondary).lineLimit(1)
            if scope != .all {
                ChromeSymbol(name: "chevron.right", size: 9).foregroundStyle(.secondary)
                Button(scopeTitle) { setScope(scope) }.buttonStyle(.plain).lineLimit(1)
            }
            if let document = currentDocument {
                ChromeSymbol(name: "chevron.right", size: 9).foregroundStyle(.secondary)
                Text(document.displayTitle).lineLimit(1)
            }
            Spacer(minLength: 4)
            chrome(.search, symbol: "magnifyingglass")
            chrome(.newTab, symbol: "rectangle.on.rectangle.badge.plus")
            chrome(.newText, symbol: "square.and.pencil")
            Menu {
                ForEach([LibraryCommand.wide, .stacked, .listOnly, .focus]) { command in
                    Button(command.title) { run(command) }
                }
            } label: { ChromeSymbol(name: "rectangle.split.2x1") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Disposición")
            chrome(.results, symbol: "list.bullet", label: listVisible && layout != .focus ? "Ocultar lista" : "Mostrar lista")
            chrome(.inspector, symbol: "sidebar.right", label: inspectorVisible && layout != .focus ? "Ocultar inspector" : "Mostrar inspector")
            SettingsLink { ChromeSymbol(name: "gearshape") }
                .buttonStyle(ChromeButtonStyle()).accessibilityLabel("Ajustes")
        }
        .font(settings.font(-1)).padding(.horizontal, 12).padding(.top, DesignTokens.windowInset)
        .frame(minHeight: DesignTokens.headerHeight)
    }

    private var tabBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 1) {
                ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                    let location = index == activeTab ? currentLocation : tab.location
                    HStack(spacing: 4) {
                        Button(tabTitle(location)) { switchTab(to: index) }.buttonStyle(.plain).lineLimit(1)
                            .accessibilityAddTraits(index == activeTab ? .isSelected : [])
                        Button("Cerrar pestaña", systemImage: "xmark") { closeTab(at: index) }
                            .labelStyle(.iconOnly).buttonStyle(ChromeButtonStyle())
                    }
                    .padding(.horizontal, 9)
                    .background(alignment: .top) {
                        if index == activeTab { Rectangle().fill(palette.tint).frame(height: DesignTokens.divider) }
                    }
                }
            }
        }.scrollIndicators(.never).background(palette.sidebar)
    }

    private var currentDocument: WritingDocument? { selection.flatMap { store.document($0.documentID) } }

    private var inspector: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Inspector").font(settings.font(-1, bold: true))
                Spacer()
                chrome(.inspector, symbol: "xmark", label: "Ocultar inspector")
            }.padding(.horizontal, 12).padding(.top, 5)
            Picker("Sección del inspector", selection: $inspectorSection) {
                ForEach(InspectorSection.allCases) { section in Text(section.rawValue).tag(section) }
            }.pickerStyle(.segmented).labelsHidden().padding(10)
            rule
            if let document = currentDocument {
                ScrollView {
                    VStack(alignment: .leading, spacing: 11) {
                        Text(document.displayTitle).font(settings.font(bold: true)).textSelection(.enabled)
                        Text(document.modifiedAt, format: .dateTime.day().month(.abbreviated).year()).foregroundStyle(.secondary)
                        if let fragment = document.fragments?.first(where: { $0.id == selection?.fragmentID }) {
                            Text(fragment.quote).foregroundStyle(.secondary).textSelection(.enabled)
                            if !fragment.tags.isEmpty { Text(fragment.tags.joined(separator: " · ")).foregroundStyle(.secondary) }
                        }
                        rule
                        if inspectorSection == .details {
                            DocumentDetails(store: store, document: document, openTag: { setScope(.tag($0)) })
                                .disabled(document.trashedAt != nil)
                        } else {
                            DocumentLinks(store: store, document: document, openDocument: openDocument)
                        }
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView("Sin selección", systemImage: "sidebar.right")
            }
        }.background(palette.sidebar)
    }

    private var statusBar: some View {
        HStack {
            let count = store.library.results(in: scope, matching: query).count
            Text(count == 1 ? "1 resultado" : "\(count) resultados")
            if selection != nil { Text("1 seleccionado") }
            Spacer()
            if let document = currentDocument { Text(document.attachment?.kind.label ?? "Markdown") }
        }.font(settings.font(-2)).foregroundStyle(.secondary).padding(.horizontal, 12).frame(height: 24)
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            if let selectedID = selection?.documentID, let document = store.document(selectedID) {
                DocumentEditor(store: store, document: document, openDocument: openDocument,
                               openTag: { setScope(.tag($0)) }, onTrashChange: { selection = nil },
                               focusTitle: titleFocusRequest == selectedID, jump: jump,
                               showInspector: { section in
                                   if layout == .focus { setLayout(.wide) }
                                   inspectorSection = section
                                   inspectorVisible = true
                               })
                    .id(selectedID)
            } else {
                ContentUnavailableView {
                    Label("Selecciona un documento", systemImage: "text.alignleft")
                } actions: {
                    Button(LibraryCommand.newText.title) { run(.newText) }
                    Button(LibraryCommand.importFiles.title) { run(.importFiles) }
                }
            }
        }
        .background(palette.workspace)
    }

    private func allows(_ command: LibraryCommand) -> Bool {
        guard store.openError == nil else { return false }
        switch command {
        case .copyLink, .exportFile: return selection != nil
        case .openWindow: return currentDocument?.trashedAt == nil && currentDocument != nil
        case .back: return tabs[activeTab].history.canGoBack
        case .forward: return tabs[activeTab].history.canGoForward
        case .closeTab: return tabs.count > 1
        default: return true
        }
    }

    private func run(_ command: LibraryCommand, target: ItemDestination? = nil) {
        guard target != nil || allows(command) else { return }
        switch command {
        case .newText: createDocument()
        case .newCanvas: createCanvas()
        case .newProject: dialog = .project
        case .newTag: dialog = .tag
        case .importFiles: importDocuments()
        case .exportFile:
            if let id = (target ?? selection)?.documentID, let document = store.document(id) { store.exportDocument(document) }
        case .copyLink:
            if let destination = target ?? selection { copyText(destination.url.absoluteString) }
        case .sidebar:
            if layout == .focus { setLayout(.wide); settings.appearance.showSidebar = true }
            else { settings.appearance.showSidebar.toggle() }
        case .search:
            if layout == .focus { setLayout(.wide) }
            listVisible = true
            searchFocused = true
        case .inbox: setScope(.inbox)
        case .trash: setScope(.trash)
        case .palette, .goTo: quickMode = command
        case .results:
            if layout == .focus || layout == .listOnly { setLayout(.wide); listVisible = true }
            else { listVisible.toggle() }
        case .inspector:
            if layout == .focus { setLayout(.wide); inspectorVisible = true }
            else { inspectorVisible.toggle() }
        case .wide: setLayout(.wide); listVisible = true
        case .stacked: setLayout(.stacked); listVisible = true
        case .listOnly: setLayout(.listOnly)
        case .focus: setLayout(layout == .focus ? lastLayout : .focus)
        case .back:
            if let previous = tabs[activeTab].history.back(from: currentLocation) { restore(previous) }
        case .forward:
            if let next = tabs[activeTab].history.forward(from: currentLocation) { restore(next) }
        case .newTab: openTab()
        case .closeTab: closeTab(at: activeTab)
        case .openWindow:
            if let destination = target ?? selection, let document = store.document(destination.documentID), document.trashedAt == nil {
                openWindow(id: "document", value: destination)
            }
        }
    }

    private func quickEntries(_ mode: LibraryCommand) -> [QuickAction] {
        if mode == .palette {
            return LibraryCommand.allCases.filter { $0 != .palette && allows($0) }.map { command in
                QuickAction(id: String(describing: command), title: command.title, detail: command.shortcutLabel) { run(command) }
            }
        }
        let projects = store.library.projects.map { project in
            QuickAction(id: "project-\(project.id)", title: project.name, detail: "Proyecto") { setScope(.project(project.id)) }
        }
        let documents = store.library.activeDocuments.map { document in
            QuickAction(id: document.id.uuidString, title: document.displayTitle, detail: document.attachment?.kind.label ?? "Texto") {
                openDocument(ItemDestination(document.id))
            }
        }
        return (projects + documents).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private var scopeTitle: String { title(for: scope) }

    private func title(for scope: LibraryScope) -> String {
        switch scope {
        case .all: "Todos los documentos"
        case .inbox: "Entrada"
        case .drafts: "Borradores"
        case .trash: "Papelera"
        case .project(let id): store.library.projects.first { $0.id == id }?.name ?? "Proyecto"
        case .savedSearch(let id): store.library.savedSearches.first { $0.id == id }?.name ?? "Búsqueda guardada"
        case .tag(let tag): tag
        }
    }

    private func setScope(_ destination: LibraryScope) {
        visit(LibraryLocation(scope: destination))
    }

    private var currentLocation: LibraryLocation {
        LibraryLocation(scope: scope, selection: selection, target: jump?.destination, query: query)
    }

    private func visit(_ location: LibraryLocation) {
        tabs[activeTab].history.record(from: currentLocation, to: location)
        restore(location)
    }

    private func restore(_ location: LibraryLocation) {
        scope = location.scope
        query = location.query
        selection = location.selection
        jump = location.target.map { JumpRequest(destination: $0) }
        titleFocusRequest = nil
    }

    private func tabTitle(_ location: LibraryLocation) -> String {
        if let id = location.selection?.documentID, let document = store.document(id) { return document.displayTitle }
        return title(for: location.scope)
    }

    private func openTab(at destination: ItemDestination? = nil) {
        tabs[activeTab].location = currentLocation
        let newLocation = LibraryLocation(selection: destination.map { ItemDestination($0.documentID) }, target: destination)
        tabs.append(LibraryTab(location: newLocation))
        activeTab = tabs.count - 1
        restore(newLocation)
    }

    private func switchTab(to index: Int) {
        guard index != activeTab else { return }
        tabs[activeTab].location = currentLocation
        activeTab = index
        restore(tabs[index].location)
    }

    private func closeTab(at index: Int) {
        guard tabs.count > 1 else { return }
        let closingActive = index == activeTab
        tabs.remove(at: index)
        if index < activeTab { activeTab -= 1 }
        if closingActive {
            activeTab = min(activeTab, tabs.count - 1)
            restore(tabs[activeTab].location)
        }
    }

    private func createDocument() {
        guard let id = store.createDocument(in: scope) else { return }
        showNewDocument(id, focusTitle: true)
    }

    private func importDocuments() {
        guard let id = store.importDocuments(in: scope) else { return }
        showNewDocument(id, focusTitle: false)
    }

    private func createCanvas() {
        guard let id = store.createCanvas(in: scope) else { return }
        showNewDocument(id, focusTitle: true)
    }

    private func showNewDocument(_ id: UUID, focusTitle: Bool) {
        let destination: LibraryScope = switch scope {
        case .savedSearch, .tag, .trash: .inbox
        case .drafts where store.document(id)?.attachment != nil: .inbox
        default: scope
        }
        if layout == .listOnly { setLayout(.wide) }
        visit(LibraryLocation(scope: destination, selection: ItemDestination(id)))
        titleFocusRequest = focusTitle ? id : nil
    }

    private func openDocument(_ destination: ItemDestination) {
        guard let document = store.document(destination.documentID), document.trashedAt == nil else {
            store.actionError = "El documento enlazado no está disponible en esta biblioteca."
            return
        }
        if let fragmentID = destination.fragmentID, document.fragments?.contains(where: { $0.id == fragmentID }) != true {
            store.actionError = "El fragmento enlazado no está disponible."
            return
        }
        if layout == .listOnly { setLayout(.wide) }
        visit(LibraryLocation(selection: ItemDestination(destination.documentID), target: destination))
    }
}

private enum CreationDialog: Identifiable {
    case project, savedSearch(String), tag, renameTag(String), renameTagSeed(String)

    var id: String { title }

    var title: String {
        switch self {
        case .project: "Nuevo proyecto"
        case .savedSearch: "Guardar búsqueda"
        case .tag, .renameTagSeed: "Nueva etiqueta"
        case .renameTag: "Cambiar ruta de etiqueta"
        }
    }

    var initialName: String {
        switch self {
        case .renameTag(let path), .renameTagSeed(let path): path
        default: ""
        }
    }
}

private struct CreationForm: View {
    @Environment(\.dismiss) private var dismiss
    var dialog: CreationDialog
    var save: (String) -> Void
    @ViewState private var name = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(dialog.title).font(.title2.weight(.semibold))
            if case .savedSearch(let query) = dialog {
                Text(query).font(.callout).foregroundStyle(.secondary)
            }
            TextField("Nombre", text: $name).focused($nameFocused)
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Guardar") {
                    dismiss()
                    save(name.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 360)
        .onAppear { name = dialog.initialName; nameFocused = true }
    }
}
