import AppKit
import SwiftUI
import WritingLibrary

struct LibraryView: View {
    var databases: LibraryDatabases
    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var location = LibraryLocation(databaseID: LibraryDatabases.defaultID)
    @ViewState private var jump: JumpRequest?
    @ViewState private var fragmentToEdit: LibraryResult?
    @ViewState private var showTagSettings = false
    @ViewState private var projectForTags: UUID?
    @ViewState private var tagToRemove: String?
    @ViewState private var dialog: CreationDialog?
    @ViewState private var titleFocusRequest: UUID?
    @ViewState private var pageCommand: PageCommandRequest?
    @ViewState private var quickMode: LibraryCommand?
    @ViewState private var queuedQuickAction: QuickAction?
    @ViewState private var tabs = [LibraryTab()]
    @ViewState private var activeTab = 0
    @AppStorage("workspace.saved") private var savedWorkspacesData = Data()
    @ViewState private var workspaceName = ""
    @ViewState private var rememberedLocations: [UUID: LibraryLocation] = [:]
    @ViewState private var restoredScene = false
    @ViewState private var showWorkspaces = false
    @ViewState private var workspaceToRename: UUID?
    @ViewState private var editingWorkspaceName = false
    @ViewState private var inspectorSection = InspectorSection.details
    @ViewState private var lastLayout = WorkspaceLayout.wide
    @ViewState private var swipePreview: (pane: SwipePane, extent: CGFloat)?
    @SceneStorage("workspace.sidebarVisible") private var savedSidebarVisible: Bool?
    @SceneStorage("workspace.sidebarWidth") private var savedSidebarWidth: Int?
    @SceneStorage("workspace.layout") private var layoutsData = Data()
    @SceneStorage("workspace.inspector") private var inspectorVisible = false
    @SceneStorage("workspace.list") private var listVisible = true
    @SceneStorage("workspace.listWidth") private var listWidth = 250.0
    @SceneStorage("workspace.listHeight") private var listHeight = 225.0
    @SceneStorage("workspace.inspectorWidth") private var inspectorWidth = 285.0
    @SceneStorage("workspace.database") private var savedDatabaseID: String?
    @SceneStorage("workspace.databaseLocations") private var databaseLocations = Data()
    @FocusState private var searchFocused: Bool

    private var sidebarVisible: Bool {
        get { savedSidebarVisible ?? settings.appearance.showSidebar }
        nonmutating set { savedSidebarVisible = newValue }
    }

    private var sidebarWidth: Int {
        get { savedSidebarWidth ?? settings.appearance.sidebarWidth }
        nonmutating set { savedSidebarWidth = newValue }
    }

    private var palette: WindowPalette { WindowPalette(scheme: scheme) }
    private var rowPadding: CGFloat { settings.appearance.compactRows ? 3 : 6 }
    private var scope: LibraryScope { location.scope }
    private var selection: ItemDestination? {
        get { location.selection }
        nonmutating set {
            location.selection = newValue
            if newValue == nil { location.target = nil }
            remember(location)
        }
    }
    private var query: String {
        get { location.query }
        nonmutating set {
            location.query = newValue
            remember(location)
        }
    }
    private var database: LibraryDatabase {
        databases.entry(for: location.databaseID) ?? databases.entries[0]
    }
    private var store: LibraryStore { databases.store(for: database.id)! }

    var body: some View {
        Group {
            if let error = store.openError {
                VStack(spacing: 12) {
                    databaseMenu
                    ContentUnavailableView("No se pudo abrir la base de datos", line: "exclamationmark.triangle",
                                           description: Text(error))
                }
            } else {
                let results = store.library.results(in: scope, matching: query)
                VStack(spacing: 0) {
                    if tabs.count > 1 { tabBar; rule }
                    GeometryReader { paneWorkspace(size: $0.size, results: results) }
                    rule
                    statusBar(count: results.count)
                }
            }
        }
        .themedWindow()
        .background(palette.workspace)
        .background { MainWindowTracker() }
        .overlay { AboutOverlay() }
        .toolbar(id: "library") { libraryToolbar }
        .toolbarRole(.editor)
        .focusedSceneValue(\.libraryCommands, LibraryCommandContext(allows: allows, run: { run($0) },
                                                                    isSelected: isSelected))
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
            get: { store.actionError != nil || databases.actionError != nil },
            set: { if !$0 { store.actionError = nil; databases.actionError = nil } }
        )) {
            Button("Aceptar", role: .cancel) { store.actionError = nil; databases.actionError = nil }
        } message: {
            Text(store.actionError ?? databases.actionError ?? "")
        }
        .alert(workspaceToRename == nil ? "Guardar espacio de trabajo" : "Renombrar espacio de trabajo", isPresented: $editingWorkspaceName) {
            TextField("Nombre", text: $workspaceName)
            Button("Cancelar", role: .cancel) {}
            Button("Guardar") { saveWorkspace() }
        }
        .sheet(isPresented: $showWorkspaces) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Espacios de trabajo").font(.title2)
                List(savedWorkspaces) { workspace in
                    HStack {
                        Text(workspace.name)
                        Spacer()
                        Button("Renombrar…") {
                            showWorkspaces = false
                            workspaceToRename = workspace.id
                            workspaceName = workspace.name
                            editingWorkspaceName = true
                        }
                        Button("Eliminar", line: "trash", role: .destructive) { deleteWorkspace(workspace) }
                            .labelStyle(.iconOnly).buttonStyle(ChromeButtonStyle())
                    }
                }
                HStack {
                    Spacer()
                    Button("Cerrar") { showWorkspaces = false }.keyboardShortcut(.cancelAction)
                }
            }.padding(18).frame(width: 500, height: 330)
        }
        .onOpenURL { url in
            if let target = ItemDestination(url: url) { openDocument(target) }
        }
        .onChange(of: currentDocument?.trashedAt, initial: true) {
            if let selection, !canShow(selection, in: store, scope: scope) {
                self.selection = nil
                jump = nil
            }
        }
        .onAppear {
            guard !restoredScene else { return }
            restoredScene = true
            let id = savedDatabaseID.flatMap(UUID.init(uuidString:)) ?? LibraryDatabases.defaultID
            rememberedLocations = (try? JSONDecoder().decode([UUID: LibraryLocation].self, from: databaseLocations)) ?? [:]
            restore(rememberedLocations[id] ?? LibraryLocation(databaseID: id))
        }
    }

    private var savedWorkspaces: [SavedWorkspace] {
        (try? JSONDecoder().decode([SavedWorkspace].self, from: savedWorkspacesData)) ?? []
    }

    private var workspaceMenu: some View {
        Menu {
            Button(LibraryCommand.saveWorkspace.title) { run(.saveWorkspace) }
            Button(LibraryCommand.manageWorkspaces.title) { run(.manageWorkspaces) }
            if !savedWorkspaces.isEmpty { Divider() }
            ForEach(savedWorkspaces) { workspace in
                Menu(workspace.name) {
                    Button("Restaurar") { restoreWorkspace(workspace) }
                    Button("Renombrar…") {
                        workspaceToRename = workspace.id; workspaceName = workspace.name; editingWorkspaceName = true
                    }
                    Button("Eliminar", role: .destructive) { deleteWorkspace(workspace) }
                }
            }
        } label: { Label("Espacios de trabajo", line: "rectangle.on.rectangle") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).labelStyle(.iconOnly).fixedSize()
            .help("Espacios de trabajo")
    }

    private func deleteWorkspace(_ workspace: SavedWorkspace) {
        writeWorkspaces(savedWorkspaces.filter { $0.id != workspace.id })
    }

    private func restoreWorkspace(_ workspace: SavedWorkspace) {
        guard !workspace.tabs.isEmpty else { return }
        let windows = (workspace.documentWindows ?? []).compactMap { saved -> SavedDocumentWindow? in
            guard let source = databases.resolve(saved.destination, preferred: saved.destination.databaseID),
                  let document = source.document(saved.destination.documentID), document.trashedAt == nil else { return nil }
            var window = saved
            window.destination = source.destination(document.id, fragmentID: saved.destination.fragmentID)
            return window
        }
        if workspace.documentWindows != nil {
            WorkspaceWindows.shared.restore(windows) { openWindow(id: "document", value: $0) }
        }
        tabs = workspace.tabs
        activeTab = min(max(0, workspace.activeTab), tabs.count - 1)
        layoutsData = workspace.layouts
        inspectorSection = workspace.inspector
        restore(tabs[activeTab].location)
        if let panels = tabs[activeTab].panels { restorePanels(panels) }
        if let window = WorkspaceWindows.shared.mainWindow { workspace.mainFrame?.apply(to: window) }
    }

    private func writeWorkspaces(_ values: [SavedWorkspace]) {
        if let data = try? JSONEncoder().encode(values) { savedWorkspacesData = data }
    }

    private func saveWorkspace() {
        let name = workspaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var values = savedWorkspaces
        if let workspaceToRename, let index = values.firstIndex(where: { $0.id == workspaceToRename }) {
            values[index].name = name
        } else {
            tabs[activeTab].location = currentLocation
            tabs[activeTab].panels = currentPanels
            values.append(SavedWorkspace(name: name, tabs: tabs, activeTab: activeTab,
                layouts: layoutsData, inspector: inspectorSection, documentWindows: WorkspaceWindows.shared.snapshot(),
                mainFrame: WorkspaceWindows.shared.mainFrame))
        }
        writeWorkspaces(values)
    }

    private func paneWorkspace(size: CGSize, results: [LibraryResult]) -> some View {
        HStack(spacing: 0) {
            if (sidebarVisible || swipePreview?.pane == .navigation) && layout != .focus {
                let width = navigationExtent(size.width)
                sidebar.frame(width: width)
                    .frame(width: swipeExtent(.navigation, width), alignment: .trailing).clipped()
                WorkspaceDivider(color: palette.border, extent: CGFloat(sidebarWidth), resize: {
                    sidebarWidth = Int(min(360, max(230, $0)))
                }) { run(.sidebar) }
            }
            centralWorkspace(width: size.width, results: results)
            if (inspectorVisible || swipePreview?.pane == .inspector) && layout != .focus {
                WorkspaceDivider(color: palette.border, extent: -inspectorWidth, resize: {
                    inspectorWidth = min(380, max(230, -$0))
                }) { run(.inspector) }
                let width = inspectorExtent(size.width)
                inspector.frame(width: width)
                    .frame(width: swipeExtent(.inspector, width), alignment: .leading).clipped()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            PaneScrollMonitor(options: settings.gestures, target: { point, direction in
                swipeTarget(at: point, direction: direction, size: size)
            }, update: previewSwipe, finish: finishSwipe)
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
                    Button("Reglas de etiquetado…", line: "tag") { showTagSettings = true }
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
                    sectionHeader("Bases de datos") {
                        Menu {
                            Button(LibraryCommand.newDatabase.title) { run(.newDatabase) }
                            Button(LibraryCommand.openDatabase.title) { run(.openDatabase) }
                        } label: { ChromeSymbol(name: "plus") }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            .accessibilityLabel("Añadir base de datos")
                    }
                    ForEach(databases.entries) { entry in
                        let selected = entry.id == database.id
                        scopeButton(entry.name, icon: "cylinder", selected: selected) {
                            if selected { setScope(.all) } else { switchDatabase(to: entry.id) }
                        }.help(entry.fileURL.path)
                    }
                    scopeButton("Entrada", icon: "tray", destination: .inbox)
                    scopeButton("Borradores", icon: "pencil", destination: .drafts)
                    scopeButton("Papelera", icon: "trash", destination: .trash)
                    sectionHeader("Grupos") {
                        Button(LibraryCommand.newProject.title, line: "plus") { run(.newProject) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.plain)
                            .help("Nuevo grupo")
                    }
                    ForEach(store.library.projects) { project in
                        scopeButton(project.name, icon: "folder", destination: .project(project.id))
                            .contextMenu { Button("Etiquetas del grupo…") { projectForTags = project.id } }
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

    private func resultsPane(_ results: [LibraryResult]) -> some View {
        documentList(results).background(palette.workspace)
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
                Button(LibraryCommand.newTag.title, line: "plus") { run(.newTag) }
                    .labelStyle(.iconOnly).buttonStyle(ChromeButtonStyle()).buttonStyle(.plain).help("Nueva etiqueta")
            }
            SwipeTree(nodes: store.library.tagTree, children: { $0.children }) { branch in
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
        scopeButton(title, icon: icon, selected: scope == destination) { setScope(destination) }
    }

    private func scopeButton(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ChromeSymbol(name: icon, size: 13).frame(width: 15)
                Text(title).font(settings.font(bold: selected))
            }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, rowPadding)
                .contentShape(Rectangle())
                .background {
                    if selected { RoundedRectangle(cornerRadius: DesignTokens.rowRadius).fill(palette.selection) }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func documentList(_ results: [LibraryResult]) -> some View {
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
                    let target = store.destination(hit.document.id, fragmentID: hit.fragment?.id)
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
                    .tag(target)
                    .draggable(target.url.absoluteString)
                    .contextMenu {
                        Button(LibraryCommand.copyLink.title) { run(.copyLink, target: target) }
                        Button(LibraryCommand.exportFile.title) { run(.exportFile, target: target) }
                        if hit.document.trashedAt == nil {
                            Button("Abrir en pestaña nueva") { openTab(at: target) }
                            Button(LibraryCommand.openWindow.title) { run(.openWindow, target: target) }
                        }
                        Button("Abrir en el visor") {
                            if layout == .listOnly { setLayout(.wide) }
                            visit(LibraryLocation(scope: scope, selection: target, target: target, query: query))
                        }
                        if hit.fragment != nil, hit.document.trashedAt == nil {
                            Button("Ir al fragmento") { openDocument(target) }
                            Button("Editar etiquetas del fragmento…") { fragmentToEdit = hit }
                        }
                        Divider()
                        if hit.document.trashedAt == nil {
                            Button(LibraryCommand.moveToTrash.title, role: .destructive) { run(.moveToTrash, target: target) }
                        } else {
                            Button(LibraryCommand.putBack.title) { run(.putBack, target: target) }
                        }
                    }
                }
                .id(database.id)
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
        let displayedDatabase = database.id
        let displayedScope = scope
        return Binding(get: { selection }, set: { destination in
            guard displayedDatabase == database.id, displayedScope == scope, destination != selection else { return }
            visit(LibraryLocation(scope: displayedScope, selection: destination, target: destination, query: query,
                                  databaseID: displayedDatabase))
        })
    }

    private func drop(_ values: [String], on tag: String) -> Bool {
        var accepted = false
        for value in values {
            if let url = URL(string: value), let target = ItemDestination(url: url),
               target.databaseID == nil || target.databaseID == database.id,
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
        return database.id == LibraryDatabases.defaultID ? "window" : database.id.uuidString
    }

    private var layout: WorkspaceLayout { layouts[layoutKey] ?? layouts["window"] ?? .wide }

    private func setLayout(_ value: WorkspaceLayout) {
        if layout != .focus { lastLayout = layout }
        var values = layouts
        values[layoutKey] = value
        if let encoded = try? JSONEncoder().encode(values) { layoutsData = encoded }
    }

    private func centralWorkspace(width: CGFloat, results: [LibraryResult]) -> some View {
        let stacked = layout == .stacked
        let arrangement = stacked ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        return VStack(spacing: 0) {
        locationBar(count: results.count)
        rule
        arrangement {
            if ((listVisible || swipePreview?.pane == .results) && layout != .focus) || layout == .listOnly {
                let extent = resultsExtent(width)
                resultsPane(results).frame(width: !stacked && layout != .listOnly ? extent : nil,
                                  height: stacked ? extent : nil)
                    .frame(width: !stacked && layout != .listOnly ? swipeExtent(.results, extent) : nil,
                           height: stacked ? swipeExtent(.results, extent) : nil,
                           alignment: stacked ? .bottom : .trailing).clipped()
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func navigationExtent(_ width: CGFloat) -> CGFloat { min(CGFloat(sidebarWidth), width * 0.23) }
    private func inspectorExtent(_ width: CGFloat) -> CGFloat { min(inspectorWidth, width * 0.27) }
    private func resultsExtent(_ width: CGFloat) -> CGFloat { layout == .stacked ? listHeight : min(listWidth, width * 0.25) }

    private func swipeExtent(_ pane: SwipePane, _ usual: CGFloat) -> CGFloat {
        swipePreview?.pane == pane ? swipePreview?.extent ?? usual : usual
    }

    private func swipeTarget(at point: CGPoint, direction: SwipeDirection, size: CGSize) -> PaneSwipeTarget? {
        guard layout != .focus else { return nil }
        let edge = CGFloat(settings.gestures.edge)
        let width = size.width
        let nav = PaneSwipeTarget(pane: .navigation, isOpen: sidebarVisible, extent: navigationExtent(width))
        let results = PaneSwipeTarget(pane: .results, isOpen: listVisible, extent: resultsExtent(width))
        let details = PaneSwipeTarget(pane: .inspector, isOpen: inspectorVisible, extent: inspectorExtent(width))
        let navEnd: CGFloat = nav.isOpen ? nav.extent + 3 : 0
        let inspectorStart = details.isOpen ? width - details.extent - 3 : width
        if point.x < (nav.isOpen ? navEnd : edge) {
            return (nav.isOpen ? direction == .left : direction == .right) ? nav : nil
        }
        if point.x > (details.isOpen ? inspectorStart : width - edge) {
            return (details.isOpen ? direction == .right : direction == .left) ? details : nil
        }
        guard layout != .listOnly else { return nil }
        let inResults = layout == .stacked ? point.y <= DesignTokens.pathBarHeight + (results.isOpen ? results.extent + 3 : edge)
            : point.x <= navEnd + (results.isOpen ? results.extent + 3 : edge)
        if inResults {
            return (results.isOpen ? direction == .left : direction == .right) ? results : nil
        }
        guard settings.gestures.cascade, currentDocument?.attachment == nil else { return nil }
        if point.x > (navEnd + inspectorStart) / 2 {
            return (details.isOpen ? direction == .right : direction == .left) ? details : nil
        }
        if direction == .left { return nav.isOpen ? nav : results.isOpen ? results : nil }
        return !results.isOpen ? results : !nav.isOpen ? nav : nil
    }

    private func previewSwipe(_ target: PaneSwipeTarget, _ distance: CGFloat) {
        guard !reduceMotion else { return }
        let raw = target.isOpen ? target.extent - distance : distance
        let extent = min(target.extent + 16, max(0, raw > target.extent ? target.extent + (raw - target.extent) * 0.18 : raw))
        swipePreview = (target.pane, extent)
    }

    private func finishSwipe(_ target: PaneSwipeTarget, _ toggle: Bool) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
            swipePreview = nil
            guard toggle else { return }
            switch target.pane {
            case .navigation: sidebarVisible = !target.isOpen
            case .results: listVisible = !target.isOpen
            case .inspector: inspectorVisible = !target.isOpen
            }
        }
        if toggle, let window = NSApp.keyWindow {
            let name: String = switch target.pane {
            case .navigation: "Navegación"
            case .results: "Lista de documentos"
            case .inspector: "Inspector"
            }
            NSAccessibility.post(element: window, notification: .announcementRequested, userInfo: [
                .announcement: "\(name): \(target.isOpen ? "oculto" : "visible")",
                .priority: NSAccessibilityPriorityLevel.medium.rawValue,
            ])
        }
    }

    private func chrome(_ command: LibraryCommand, symbol: String, label: String? = nil, active: Bool = false) -> some View {
        Button { run(command) } label: { ChromeSymbol(name: symbol) }
            .buttonStyle(ChromeButtonStyle(active: active))
            .accessibilityAddTraits(active ? .isSelected : [])
            .accessibilityLabel(label ?? command.title)
            .help(label ?? command.title)
            .disabled(!allows(command))
    }

    /// Main toolbar, DEVONthink-style: a native unified toolbar that spans the whole window above
    /// every pane and holds the window controls. Groups by function: panels and list view,
    /// creation, search, inspector. Customisable from Visualización → Personalizar barra de herramientas.
    @ToolbarContentBuilder private var libraryToolbar: some CustomizableToolbarContent {
        ToolbarItem(id: "about", placement: .navigation) { AboutButton() }
        ToolbarItem(id: "sidebar", placement: .navigation) {
            chrome(.sidebar, symbol: "sidebar.left", label: sidebarVisible && layout != .focus ? "Ocultar barra lateral" : "Mostrar barra lateral",
                   active: sidebarVisible && layout != .focus)
        }
        ToolbarItem(id: "listView", placement: .navigation) {
            HStack(spacing: 2) {
                chrome(.wide, symbol: "rectangle.split.2x1", label: "Lista a la izquierda", active: layout == .wide)
                chrome(.stacked, symbol: "rectangle.split.1x2", label: "Lista arriba", active: layout == .stacked)
                chrome(.listOnly, symbol: "list.bullet.rectangle", label: "Lista en el centro", active: layout == .listOnly)
            }
            .padding(2)
            .overlay { RoundedRectangle(cornerRadius: DesignTokens.rowRadius).strokeBorder(palette.border) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Vista de la lista de documentos")
        }
        ToolbarItem(id: "newText", placement: .primaryAction) {
            chrome(.newText, symbol: "square.and.pencil")
        }
        ToolbarItem(id: "newTab", placement: .primaryAction) {
            chrome(.newTab, symbol: "rectangle.on.rectangle.badge.plus")
        }
        ToolbarItem(id: "workspaces", placement: .primaryAction) {
            workspaceMenu
        }
        ToolbarItem(id: "search", placement: .primaryAction) {
            searchField.frame(minWidth: 180, idealWidth: 300, maxWidth: 420)
        }
        ToolbarItem(id: "inspector", placement: .primaryAction) {
            chrome(.inspector, symbol: "sidebar.right", label: inspectorVisible && layout != .focus ? "Ocultar inspector" : "Mostrar inspector",
                   active: inspectorVisible && layout != .focus)
        }
        ToolbarItem(id: "settings", placement: .primaryAction) {
            SettingsLink { ChromeSymbol(name: "gearshape") }
                .buttonStyle(ChromeButtonStyle()).accessibilityLabel("Ajustes").help("Ajustes")
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            ChromeSymbol(name: "magnifyingglass", size: 13).foregroundStyle(palette.textTertiary)
            TextField("Buscar en esta vista", text: Binding(get: { query }, set: { query = $0 }))
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .accessibilityIdentifier("library-search")
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button("Guardar búsqueda en la base activa", line: "bookmark") {
                    dialog = .savedSearch(query.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(palette.textSecondary)
                .help("Guardar búsqueda en la base activa")
                Button("Borrar búsqueda", line: "xmark") { query = "" }
                    .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(palette.textSecondary)
            }
        }
        .font(settings.font(-1))
        .padding(.horizontal, 8).frame(height: 26)
        .background(palette.background, in: .rect(cornerRadius: DesignTokens.rowRadius))
        .overlay { RoundedRectangle(cornerRadius: DesignTokens.rowRadius).strokeBorder(palette.border) }
    }

    /// Path bar of the central column (list and document): history, location and counts.
    /// It starts at the navigation pane's edge and never covers it.
    private func locationBar(count: Int) -> some View {
        HStack(spacing: 4) {
            chrome(.back, symbol: "chevron.left")
            chrome(.forward, symbol: "chevron.right")
            databaseMenu
            if scope != .all {
                ChromeSymbol(name: "chevron.right", size: 9).foregroundStyle(palette.textTertiary)
                Button(scopeTitle) { setScope(scope) }.buttonStyle(.plain).lineLimit(1)
            }
            if let document = currentDocument {
                ChromeSymbol(name: "chevron.right", size: 9).foregroundStyle(palette.textTertiary)
                Text(document.displayTitle).lineLimit(1)
            }
            Rectangle().fill(palette.border).frame(width: DesignTokens.divider, height: 14).padding(.horizontal, 6)
            Text((count == 1 ? "1 elemento" : "\(count) elementos") + (selection != nil ? ", 1 seleccionado" : ""))
                .foregroundStyle(palette.textSecondary).lineLimit(1)
            Spacer(minLength: 4)
        }
        .font(settings.font(-1)).padding(.horizontal, 8)
        .frame(height: DesignTokens.pathBarHeight)
        .background(palette.background)
    }

    private var databaseMenu: some View {
        Menu {
            ForEach(databases.entries) { entry in
                Button {
                    if entry.id == database.id { setScope(.all) }
                    else { switchDatabase(to: entry.id) }
                } label: {
                    if entry.id == database.id { Label(entry.name, line: "checkmark") }
                    else { Text(entry.name) }
                }
            }
            Divider()
            Button(LibraryCommand.newDatabase.title) { run(.newDatabase) }
            Button(LibraryCommand.openDatabase.title) { run(.openDatabase) }
        } label: { Label(database.name, line: "cylinder").lineLimit(1) }
            .menuStyle(.borderlessButton).fixedSize()
            .accessibilityLabel("Base de datos activa: \(database.name)")
    }

    /// Editor-style tabs: the active one takes the editor background with a 1 px accent line on
    /// top; the close button shows on the active tab and under the pointer.
    private var tabBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                    let location = index == activeTab ? currentLocation : tab.location
                    ChromeTab(title: tabTitle(location), active: index == activeTab,
                              select: { switchTab(to: index) }, close: { closeTab(at: index) })
                    Rectangle().fill(palette.border).frame(width: DesignTokens.divider)
                }
            }
        }.scrollIndicators(.never).frame(height: 30).background(palette.surface)
    }

    private var currentDocument: WritingDocument? { selection.flatMap { store.document($0.documentID) } }

    private var inspector: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Inspector").font(settings.font(-1, bold: true))
                Spacer()
                chrome(.inspector, symbol: "xmark", label: "Ocultar inspector")
            }.padding(.horizontal, 12).padding(.top, 5)
            ChromeSegmented(title: "Sección del inspector", selection: $inspectorSection,
                            options: InspectorSection.allCases.map { ($0, $0.rawValue) })
                .font(settings.font(-1)).padding(10)
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
                ContentUnavailableView("Sin selección", line: "sidebar.right")
            }
        }.frame(maxHeight: .infinity, alignment: .topLeading).background(palette.sidebar)
    }

    private func statusBar(count: Int) -> some View {
        HStack {
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
                               }, pageCommand: pageCommand)
                    .id(store.destination(selectedID))
            } else {
                ContentUnavailableView {
                    Label("Selecciona un documento", line: "text.alignleft")
                } actions: {
                    VStack(spacing: 6) {
                        Button(LibraryCommand.newText.title) { run(.newText) }
                        Button(LibraryCommand.importFiles.title) { run(.importFiles) }
                    }
                }
            }
        }
        .background(palette.workspace)
    }

    private func allows(_ command: LibraryCommand) -> Bool {
        if command == .newDatabase || command == .openDatabase { return true }
        guard store.openError == nil else { return false }
        if command.isPageCommand {
            guard layout != .listOnly, let document = currentDocument else { return false }
            return settings.allowsPageCommand(command, for: document)
        }
        switch command {
        case .copyLink, .exportFile: return selection != nil
        case .moveToTrash: return currentDocument.map { $0.trashedAt == nil } ?? false
        case .putBack: return currentDocument?.trashedAt != nil
        case .openWindow: return currentDocument?.trashedAt == nil && currentDocument != nil
        case .back: return tabs[activeTab].history.canGoBack
        case .forward: return tabs[activeTab].history.canGoForward
        case .closeTab: return tabs.count > 1
        case .restoreWorkspace, .manageWorkspaces: return !savedWorkspaces.isEmpty
        default: return true
        }
    }

    private func isSelected(_ command: LibraryCommand) -> Bool {
        switch command {
        case .sidebar: sidebarVisible && layout != .focus
        case .results: (listVisible || layout == .listOnly) && layout != .focus
        case .inspector: inspectorVisible && layout != .focus
        case .wide: layout == .wide
        case .stacked: layout == .stacked
        case .listOnly: layout == .listOnly
        case .focus: layout == .focus
        default: false
        }
    }

    private func run(_ command: LibraryCommand, target: ItemDestination? = nil) {
        guard target != nil || allows(command) else { return }
        switch command {
        case .pageEditor, .pagePreview, .pageBoth, .pageNone, .pageSetup, .pageBreak, .pageGo,
             .pagePDF, .pagePrint, .pageOutline:
            if let id = (target ?? selection)?.documentID { pageCommand = PageCommandRequest(command: command, document: id) }
        case .saveWorkspace:
            workspaceToRename = nil; workspaceName = ""; editingWorkspaceName = true
        case .restoreWorkspace: quickMode = command
        case .manageWorkspaces: showWorkspaces = true
        case .newDatabase, .openDatabase:
            if let id = databases.chooseDatabase(creating: command == .newDatabase) { switchDatabase(to: id) }
        case .moveToTrash, .putBack:
            if let id = (target ?? selection)?.documentID,
               store.setTrashed(id, command == .moveToTrash), selection?.documentID == id {
                selection = nil
                jump = nil
                titleFocusRequest = nil
            }
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
            if layout == .focus { setLayout(.wide); sidebarVisible = true }
            else { sidebarVisible.toggle() }
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
            return LibraryCommandContext(allows: allows, run: { run($0) }).paletteEntries
        }
        if mode == .restoreWorkspace {
            return savedWorkspaces.map { workspace in
                QuickAction(id: workspace.id.uuidString, title: workspace.name) { restoreWorkspace(workspace) }
            }
        }
        return databases.entries.flatMap { entry -> [QuickAction] in
            guard let source = databases.store(for: entry.id) else { return [] }
            let groups = source.library.projects.map { group in
                QuickAction(id: "\(entry.id)/group/\(group.id)", title: group.name, detail: "Grupo · \(entry.name)") {
                    visit(LibraryLocation(scope: .project(group.id), databaseID: entry.id))
                }
            }
            let documents = source.library.activeDocuments.map { document in
                QuickAction(id: "\(entry.id)/\(document.id)", title: document.displayTitle,
                            detail: "\(document.attachment?.kind.label ?? "Texto") · \(entry.name)") {
                    openDocument(source.destination(document.id))
                }
            }
            return groups + documents
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private var scopeTitle: String { title(for: scope) }

    private func title(for scope: LibraryScope, databaseID: UUID? = nil) -> String {
        let entry = databases.entry(for: databaseID ?? database.id) ?? database
        let source = databases.store(for: entry.id)
        switch scope {
        case .all: return entry.name
        case .inbox: return "Entrada"
        case .drafts: return "Borradores"
        case .trash: return "Papelera"
        case .project(let id): return source?.library.projects.first { $0.id == id }?.name ?? "Grupo"
        case .savedSearch(let id): return source?.library.savedSearches.first { $0.id == id }?.name ?? "Búsqueda guardada"
        case .tag(let tag): return tag
        }
    }

    private func setScope(_ destination: LibraryScope) {
        visit(LibraryLocation(scope: destination))
    }

    private var currentLocation: LibraryLocation { location }

    private func remember(_ location: LibraryLocation) {
        guard let id = location.databaseID else { return }
        guard rememberedLocations[id] != location else { return }
        rememberedLocations[id] = location
        if let encoded = try? JSONEncoder().encode(rememberedLocations) { databaseLocations = encoded }
    }

    private func switchDatabase(to id: UUID) {
        guard id != database.id else { return }
        visit(rememberedLocations[id] ?? LibraryLocation(databaseID: id))
    }

    private func visit(_ requested: LibraryLocation) {
        var location = requested
        location.databaseID = location.databaseID ?? database.id
        if location.databaseID != database.id { remember(currentLocation) }
        tabs[activeTab].history.record(from: currentLocation, to: location)
        restore(location)
    }

    private func restore(_ requested: LibraryLocation) {
        let entry = databases.entry(for: requested.databaseID) ?? databases.entries[0]
        guard let source = databases.store(for: entry.id) else { return }
        var restored = requested
        restored.databaseID = entry.id
        if let selected = restored.selection, canShow(selected, in: source, scope: restored.scope) {
            restored.selection = source.destination(selected.documentID, fragmentID: selected.fragmentID)
            restored.target = restored.target.map { source.destination($0.documentID, fragmentID: $0.fragmentID) }
        } else {
            restored.selection = nil
            restored.target = nil
        }
        location = restored
        jump = restored.target.map { JumpRequest(destination: $0) }
        savedDatabaseID = entry.id.uuidString
        databases.activeID = entry.id
        remember(restored)
        titleFocusRequest = nil
    }

    private func canShow(_ destination: ItemDestination, in source: LibraryStore, scope: LibraryScope) -> Bool {
        guard destination.databaseID == nil || destination.databaseID == source.databaseID,
              let document = source.document(destination.documentID) else { return false }
        return (document.trashedAt != nil) == (scope == .trash)
    }

    private func tabTitle(_ location: LibraryLocation) -> String {
        let id = location.databaseID ?? LibraryDatabases.defaultID
        if let target = location.selection, let document = databases.store(for: id)?.document(target.documentID) {
            return document.displayTitle
        }
        return title(for: location.scope, databaseID: id)
    }

    private func openTab(at destination: ItemDestination? = nil) {
        tabs[activeTab].location = currentLocation
        tabs[activeTab].panels = currentPanels
        let newLocation = LibraryLocation(selection: destination.map { store.destination($0.documentID) },
                                          target: destination, databaseID: database.id)
        tabs.append(LibraryTab(location: newLocation, panels: currentPanels))
        activeTab = tabs.count - 1
        restore(newLocation)
    }

    private func switchTab(to index: Int) {
        guard index != activeTab else { return }
        tabs[activeTab].location = currentLocation
        tabs[activeTab].panels = currentPanels
        activeTab = index
        restore(tabs[index].location)
        if let panels = tabs[index].panels { restorePanels(panels) }
    }

    private func closeTab(at index: Int) {
        guard tabs.count > 1 else { return }
        let closingActive = index == activeTab
        tabs.remove(at: index)
        if index < activeTab { activeTab -= 1 }
        if closingActive {
            activeTab = min(activeTab, tabs.count - 1)
            restore(tabs[activeTab].location)
            if let panels = tabs[activeTab].panels { restorePanels(panels) }
        }
    }

    private var currentPanels: TabPanels {
        TabPanels(sidebarVisible: sidebarVisible, sidebarWidth: sidebarWidth,
                  listVisible: listVisible, listWidth: listWidth, listHeight: listHeight,
                  inspectorVisible: inspectorVisible, inspectorWidth: inspectorWidth)
    }

    private func restorePanels(_ panels: TabPanels) {
        sidebarVisible = panels.sidebarVisible
        sidebarWidth = panels.sidebarWidth
        listVisible = panels.listVisible
        listWidth = panels.listWidth
        listHeight = panels.listHeight
        inspectorVisible = panels.inspectorVisible
        inspectorWidth = panels.inspectorWidth
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
        visit(LibraryLocation(scope: destination, selection: store.destination(id)))
        titleFocusRequest = focusTitle ? id : nil
    }

    private func openDocument(_ destination: ItemDestination) {
        guard let source = databases.resolve(destination, preferred: database.id),
              let document = source.document(destination.documentID), document.trashedAt == nil else {
            store.actionError = "El documento enlazado no está disponible en las bases de datos abiertas."
            return
        }
        if let fragmentID = destination.fragmentID, document.fragments?.contains(where: { $0.id == fragmentID }) != true {
            store.actionError = "El fragmento enlazado no está disponible."
            return
        }
        if layout == .listOnly { setLayout(.wide) }
        visit(LibraryLocation(selection: source.destination(document.id),
                              target: source.destination(document.id, fragmentID: destination.fragmentID),
                              databaseID: source.databaseID))
    }
}

private enum CreationDialog: Identifiable {
    case project, savedSearch(String), tag, renameTag(String), renameTagSeed(String)

    var id: String { title }

    var title: String {
        switch self {
        case .project: "Nuevo grupo"
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

private struct ChromeTab: View {
    let title: String
    let active: Bool
    let select: () -> Void
    let close: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false

    var body: some View {
        let palette = WindowPalette(scheme: scheme)
        HStack(spacing: 6) {
            Button(action: select) { Text(title).lineLimit(1) }
                .buttonStyle(.plain)
                .foregroundStyle(active ? palette.textPrimary : palette.textSecondary)
                .accessibilityAddTraits(active ? .isSelected : [])
            Button(action: close) { ChromeSymbol(name: "xmark", size: 12) }
                .buttonStyle(.plain)
                .foregroundStyle(palette.textSecondary)
                .frame(width: 16, height: 16)
                .opacity(active || hovering ? 1 : 0)
                .accessibilityLabel("Cerrar pestaña")
                .help("Cerrar pestaña")
        }
        .padding(.leading, 12).padding(.trailing, 8)
        .frame(maxHeight: .infinity)
        .background(active ? palette.background : hovering ? palette.hover : .clear)
        .overlay(alignment: .top) {
            if active { Rectangle().fill(palette.accent).frame(height: DesignTokens.divider) }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
