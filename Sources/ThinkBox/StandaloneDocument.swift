import AppKit
import SwiftUI
import WritingLibrary

struct StandaloneDocument: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var databases: LibraryDatabases
    var destination: ItemDestination?
    @ViewState private var jump: JumpRequest?
    @SceneStorage("standalone.inspector") private var inspectorVisible = false
    @SceneStorage("standalone.inspectorWidth") private var inspectorWidth = 260.0
    @ViewState private var previewWidth: CGFloat?
    @ViewState private var paletteVisible = false
    @ViewState private var pageCommand: PageCommandRequest?
    @ViewState private var readerState: DocumentReaderState?
    @ViewState private var readerRestore: DocumentReaderRestore?

    var body: some View {
        Group {
            if let destination, let store = databases.resolve(destination, preferred: LibraryDatabases.defaultID),
               let document = store.document(destination.documentID) {
                let commandContext = commands(store: store, document: document, destination: destination)
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button("Inspector", line: "sidebar.right") { inspectorVisible.toggle() }
                            .labelStyle(.iconOnly).buttonStyle(ChromeButtonStyle()).help("Mostrar u ocultar inspector")
                    }.padding(8)
                    GeometryReader { geometry in
                        HStack(spacing: 0) {
                            DocumentEditor(store: store, document: document,
                                openDocument: { target in
                                    if let source = databases.resolve(target, preferred: store.databaseID),
                                       let document = source.document(target.documentID), document.trashedAt == nil {
                                        openWindow(id: "document", value: source.destination(document.id, fragmentID: target.fragmentID))
                                    } else { store.actionError = "El documento enlazado no está disponible." }
                                },
                                openTag: nil, onTrashChange: { dismissWindow() }, focusTitle: false,
                                jump: jump, pageCommand: pageCommand, readerRestore: readerRestore,
                                onReaderState: { readerState = $0 })
                            if inspectorVisible || previewWidth != nil {
                                WorkspaceDivider(color: .secondary.opacity(0.3), extent: -inspectorWidth,
                                    resize: { inspectorWidth = min(380, max(200, -$0)) }) { inspectorVisible.toggle() }
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text("Inspector").uiFont(0, bold: true)
                                        Text(document.displayTitle).uiFont(2)
                                        Text(document.modifiedAt.formatted()).foregroundStyle(.secondary)
                                        TagEditor(tags: document.tags, suggestions: store.library.availableTags,
                                            change: { tags in store.update(document.id) { $0.tags = tags } })
                                            .disabled(document.trashedAt != nil)
                                        Text("\(document.markdown.split(whereSeparator: \.isWhitespace).count) palabras")
                                    }.padding(12)
                                }.frame(width: inspectorWidth)
                                .frame(width: previewWidth ?? inspectorWidth, alignment: .leading).clipped()
                            }
                        }.background {
                            PaneScrollMonitor(options: settings.gestures, target: { point, direction in
                                let width = min(inspectorWidth, geometry.size.width * 0.45)
                                guard point.x > geometry.size.width - (inspectorVisible ? width + 6 : CGFloat(settings.gestures.edge)),
                                      inspectorVisible ? direction == .right : direction == .left else { return nil }
                                return PaneSwipeTarget(pane: .inspector, isOpen: inspectorVisible, extent: width)
                            }, update: { target, distance in
                                guard !reduceMotion else { return }
                                previewWidth = max(0, min(target.extent + 16, target.isOpen ? target.extent - distance : distance))
                            }, finish: { _, toggle in
                                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                                    previewWidth = nil
                                    if toggle { inspectorVisible.toggle() }
                                }
                                if toggle, let window = NSApp.keyWindow {
                                    NSAccessibility.post(element: window, notification: .announcementRequested,
                                        userInfo: [.announcement: "Inspector \(inspectorVisible ? "desplegado" : "plegado")",
                                                   .priority: NSAccessibilityPriorityLevel.medium.rawValue])
                                }
                            })
                        }
                    }
                }
                .background {
                    WorkspaceWindowTracker(destination: store.destination(document.id, fragmentID: destination.fragmentID),
                        inspectorVisible: $inspectorVisible, inspectorWidth: $inspectorWidth,
                        reader: readerState, restoreReader: { readerRestore = DocumentReaderRestore(state: $0) })
                }
                .navigationTitle(document.displayTitle)
                .task(id: destination) { jump = JumpRequest(destination: destination) }
                .focusedSceneValue(\.libraryCommands, commandContext)
                .sheet(isPresented: $paletteVisible) {
                    CommandPalette(title: LibraryCommand.palette.title, entries: commandContext.paletteEntries) { action in
                        paletteVisible = false
                        action.run()
                    }
                }
                .alert("Think Box", isPresented: Binding(
                    get: { store.actionError != nil }, set: { if !$0 { store.actionError = nil } }
                )) {
                    Button("Aceptar", role: .cancel) { store.actionError = nil }
                } message: { Text(store.actionError ?? "") }
            } else {
                ContentUnavailableView("Documento no disponible", line: "doc")
            }
        }
    }

    private func commands(store: LibraryStore, document: WritingDocument,
                          destination: ItemDestination) -> LibraryCommandContext {
        LibraryCommandContext(allows: { command in
            switch command {
            case .inspector, .palette, .copyLink, .exportFile: true
            case .moveToTrash: document.trashedAt == nil
            case .putBack: document.trashedAt != nil
            default: settings.allowsPageCommand(command, for: document)
            }
        }, run: { command in
            switch command {
            case .inspector: inspectorVisible.toggle()
            case .palette: paletteVisible = true
            case .copyLink: copyText(store.destination(document.id, fragmentID: destination.fragmentID).url.absoluteString)
            case .exportFile: store.exportDocument(document)
            case .moveToTrash: if store.setTrashed(document.id, true) { dismissWindow() }
            case .putBack: store.setTrashed(document.id, false)
            default: pageCommand = PageCommandRequest(command: command, document: document.id)
            }
        })
    }
}
