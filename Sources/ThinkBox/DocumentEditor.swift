import AppKit
import PDFKit
import UniformTypeIdentifiers
import SwiftUI
import WritingLibrary

struct JumpRequest: Equatable {
    let id = UUID()
    let destination: ItemDestination
}

struct DocumentEditor: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var store: LibraryStore
    var document: WritingDocument
    var openDocument: (ItemDestination) -> Void
    var openTag: ((String) -> Void)?
    var onTrashChange: () -> Void
    var focusTitle: Bool
    var jump: JumpRequest?
    var showInspector: ((InspectorSection) -> Void)?
    var pageCommand: PageCommandRequest? = nil
    var readerRestore: DocumentReaderRestore? = nil
    var onReaderState: ((DocumentReaderState) -> Void)? = nil

    @FocusState private var titleFocused: Bool
    @SceneStorage("document.outlineVisible") private var outlineVisible = false
    @ViewState private var outlinePreview: CGFloat?
    @AppStorage("editor.outlineWidth") private var outlineWidth = 180.0
    @ViewState private var showingDetails = false
    @ViewState private var showingLinks = false
    @ViewState private var selectedText = NSRange(location: 0, length: 0)
    @ViewState private var reveal: TextReveal?
    @ViewState private var tagFragment: DocumentFragment?
    @ViewState private var showExtractedText = false

    @ViewState private var showPageSetup = false
    @ViewState private var showPageRulers = false
    @ViewState private var sourceRulerHeight: CGFloat = 0
    @ViewState private var showPageJump = false
    @ViewState private var pageNumber = ""
    @ViewState private var insertion: TextInsertion?
    @ViewState private var rendered: (input: MarkdownPageInput, pages: MarkdownPages)?
    /// Zoom of the paginated preview relative to the editor's sheet width (1 = same as the editor).
    @ViewState private var previewZoom: CGFloat = 1
    @ViewState private var renderSequence = 0
    @ViewState private var shownSequence = 0
    @ViewState private var pageDisplay = PageDisplay.continuous
    @ViewState private var pageZoom = PageZoom.width
    @ViewState private var sourceZoom = PageZoom.width
    @ViewState private var jumpInPreview = true
    @ViewState private var showPageThumbnails = false
    @ViewState private var previewView: PDFView?
    @ViewState private var previewTarget: PageDestination?
    @ViewState private var sourceTarget: PageDestination?
    @ViewState private var continuousTarget: TextReveal?
    @ViewState private var sourceScroll: TextReveal?
    @ViewState private var activePreviewPage = 0
    @ViewState private var activeSourcePage = 0
    @ViewState private var sourcePageCount = 1
    @ViewState private var previewSyncPage: Int?
    @ViewState private var sourceSyncOffset: Int?
    @ViewState private var readerSourceOffset = 0
    @ViewState private var readerPreviewOffset = 0

    private var palette: WindowPalette { WindowPalette(scheme: scheme) }

    var body: some View {
        VStack(spacing: 0) {
            if let asset = document.attachment {
                TextField("Sin título", text: binding(\.title))
                    .font(settings.font(6, bold: true)).textFieldStyle(.plain)
                    .focused($titleFocused).accessibilityLabel("Título del documento")
                    .disabled(document.trashedAt != nil)
                    .padding(.horizontal, 22).padding(.vertical, 10)
                attachmentContent(asset)
            } else {
                writingContent
            }

            Rectangle().fill(palette.border).frame(height: 1)
            documentBar
        }
        .focusedSceneValue(\.pageCommands, LibraryCommandContext(allows: allowsPageCommand, run: runPageCommand,
                                                                 isSelected: isPageCommandSelected))
        .onChange(of: pageCommand) {
            if let pageCommand, pageCommand.document == document.id, allowsPageCommand(pageCommand.command) {
                runPageCommand(pageCommand.command)
            }
        }
        .onAppear { titleFocused = focusTitle }
        .onChange(of: jump, initial: true) {
            guard let target = jump?.destination.fragmentID,
                  let fragment = (document.fragments ?? []).first(where: { $0.id == target }),
                  case .text(let anchor) = fragment.location else { return }
            if let range = anchor.resolve(in: selectableText) {
                if document.attachment?.kind == .preview { showExtractedText = true }
                if document.attachment == nil && pageViews.mode == .preview {
                    changeViews { $0.mode = .split }
                }
                reveal = TextReveal(range: range)
            } else {
                store.actionError = "El fragmento cambió o ya no está en el documento."
            }
        }
        .sheet(item: $tagFragment) { fragment in
            FragmentTagSheet(fragment: fragment, tags: store.library.availableTags) { tags in
                store.saveFragment(documentID: document.id, fragment: fragment, tags: tags, copyLink: false)
            }
        }
    }

    private var pageViews: WritingPageViews { settings.writingViews(for: document) }

    private var pageLayout: WritingPageLayout { document.pageLayout ?? settings.pages.layout }
    private var darkPaper: Bool { scheme == .dark && settings.pages.darkPaper }

    private var pageInput: MarkdownPageInput {
        let projects = store.library.projects.filter { document.projectIDs.contains($0.id) }.map(\.name).sorted()
        return MarkdownPageInput(source: document.markdown, plain: document.plainText == true, layout: pageLayout,
                                 metadata: PageMetadata(title: document.displayTitle, date: document.modifiedAt,
                                    library: store.fileURL.deletingPathExtension().lastPathComponent,
                                    group: projects.joined(separator: ", "), author: settings.reader.author),
                                 dark: darkPaper, richTextData: document.richTextData,
                                 imageRoots: store.markdownImageRoots(for: document.id),
                                 bodySize: CGFloat(settings.preview.fontSize), bodyFont: settings.preview.font,
                                 lineSpacing: CGFloat(settings.preview.lineSpacing),
                                 justified: settings.preview.justify, hyphenated: settings.preview.hyphenate)
    }

    private var shouldRender: Bool { pageViews.mode != .source && pageViews.preview }

    private var writingContent: some View {
        writingPanels
        .onChange(of: onReaderState == nil ? nil : readingState, initial: true) {
            if let onReaderState { onReaderState(.writing(readingState)) }
        }
        .onChange(of: readerRestore, initial: true) {
            if case .writing(let state) = readerRestore?.state { restoreReading(state) }
        }
        .task(id: shouldRender ? pageInput : nil) {
            // The preview follows typing: renders run one at a time, the newest input waits for
            // the one in progress, and a result is shown even if more text arrived meanwhile,
            // unless a newer result is already on screen.
            guard shouldRender else { return }
            let input = pageInput
            renderSequence += 1
            let sequence = renderSequence
            guard let pages = await PreviewRenderQueue.shared.render(input) else {
                if !Task.isCancelled && sequence > shownSequence {
                    rendered = nil
                    store.actionError = "No se pudo componer la vista de página."
                }
                return
            }
            guard sequence > shownSequence else { return }
            shownSequence = sequence
            rendered = (input, pages)
        }
        .sheet(isPresented: $showPageSetup) {
            PageSetupSheet(layout: pageLayout) { layout in
                store.update(document.id, touch: false) { $0.pageLayout = layout }
            }
        }
        .alert("Ir a página", isPresented: $showPageJump) {
            TextField("Número de página", text: $pageNumber)
            Button("Cancelar", role: .cancel) {}
            Button("Ir") {
                if let number = Int(pageNumber), number >= 1 { goToPage(number - 1) }
            }.keyboardShortcut(.defaultAction)
        }
    }

    private var writingPanels: some View {
        GeometryReader { outer in
            let split = pageViews.mode == .split
            let docked = outer.size.width >= (split ? 540 : 390)
            VStack(spacing: 0) {
                writingHeader(width: outer.size.width, docked: docked)
                Divider()
                HStack(spacing: 0) {
                    if docked && (outlineVisible || outlinePreview != nil) {
                        outlinePane
                            .frame(width: outlineWidth)
                            .frame(width: outlinePreview ?? outlineWidth, alignment: .trailing).clipped()
                        WorkspaceDivider(color: palette.border, extent: outlineWidth, resize: {
                            outlineWidth = min(360, max(150, $0))
                        }) { outlineVisible.toggle() }
                    }
                    GeometryReader { geometry in
                        let dividerWidth = split ? DesignTokens.divider : 0
                        let availableWidth = max(0, geometry.size.width - dividerWidth)
                        let hideSource = pageViews.mode == .preview
                        let sourceWidth = hideSource ? 0 : split ? floor(availableWidth / 2) : availableWidth
                        HStack(alignment: .top, spacing: 0) {
                            sourcePanel(width: sourceWidth)
                                .frame(width: sourceWidth, height: geometry.size.height)
                                .clipped()
                                .opacity(hideSource ? 0 : 1)
                                .accessibilityHidden(hideSource)
                                .allowsHitTesting(!hideSource)
                            if split { Rectangle().fill(palette.border).frame(width: dividerWidth) }
                            if pageViews.mode != .source {
                                previewPanel(width: availableWidth - sourceWidth)
                                    .frame(width: availableWidth - sourceWidth, height: geometry.size.height)
                                    .clipped()
                            }
                        }
                    }
                }
            }
        }
        .background(settings.editor.customColors ? settings.editor.paper.color : palette.workspace)
        .background {
            PaneScrollMonitor(options: settings.gestures, target: { point, direction in
                guard point.x < (outlineVisible ? outlineWidth + 6 : CGFloat(settings.gestures.edge)),
                      outlineVisible ? direction == .left : direction == .right else { return nil }
                return PaneSwipeTarget(pane: .navigation, isOpen: outlineVisible, extent: outlineWidth)
            }, update: { target, distance in
                guard !reduceMotion else { return }
                outlinePreview = max(0, min(outlineWidth + 16, target.isOpen ? outlineWidth - distance : distance))
            }, finish: { _, toggle in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                    outlinePreview = nil
                    if toggle { outlineVisible.toggle() }
                }
                if toggle, let window = NSApp.keyWindow {
                    NSAccessibility.post(element: window, notification: .announcementRequested,
                        userInfo: [.announcement: "Esquema \(outlineVisible ? "desplegado" : "plegado")",
                                   .priority: NSAccessibilityPriorityLevel.medium.rawValue])
                }
            })
        }
    }

    private var outlinePane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Esquema").uiFont(0, bold: true)
            if let previewView, previewVisible {
                Toggle("Miniaturas", isOn: $showPageThumbnails)
                if showPageThumbnails { PDFThumbnails(pdf: previewView).frame(minHeight: 125) }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(outlineEntries, id: \.offset) { entry in
                        Button(entry.title) {
                            sourceScroll = TextReveal(range: NSRange(location: entry.offset, length: 0))
                            if let rendered { previewTarget = PageDestination(index: rendered.pages.page(at: entry.offset)) }
                            else { continuousTarget = sourceScroll }
                        }.buttonStyle(.plain)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(10).frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var outlineEntries: [(offset: Int, title: String)] {
        MarkdownBlocks.lines(in: document.markdown, markdown: true).compactMap { line in
            guard !line.code, !line.fence,
                  let heading = line.text.prefixMatch(of: /^ {0,3}#{1,6}[ \t]+(.+)$/) else { return nil }
            return (line.start, String(heading.1))
        }
    }

    private func writingHeader(width: CGFloat, docked: Bool) -> some View {
        let mode = Binding<WritingViewMode>(get: { pageViews.mode }, set: { mode in
            // Split view always starts with the preview at the editor's scale.
            if mode == .split { previewZoom = 1 }
            changeViews { $0.mode = mode }
        })
        return HStack {
            TextField("Sin título", text: binding(\.title))
                .font(settings.font(5, bold: true)).textFieldStyle(.plain)
                .focused($titleFocused).accessibilityLabel("Título del texto")
                .disabled(document.trashedAt != nil)
            writingModes(mode)
            Rectangle().fill(palette.border).frame(width: DesignTokens.divider, height: 16).padding(.horizontal, 4)
                .accessibilityHidden(true)
            Button { outlineVisible.toggle() } label: { ChromeSymbol(name: "list.bullet.indent") }
                .buttonStyle(ChromeButtonStyle()).help("Mostrar u ocultar esquema").accessibilityLabel("Mostrar u ocultar esquema")
                .popover(isPresented: Binding(get: { !docked && outlineVisible },
                                              set: { if !docked { outlineVisible = $0 } })) {
                    outlinePane.frame(width: 230, height: 330)
                }
            Button { showPageSetup = true } label: { ChromeSymbol(name: "gearshape") }
                .buttonStyle(ChromeButtonStyle()).help("Configurar página").accessibilityLabel("Configurar página")
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
    }

    /// Editor, split and preview as three separate buttons (DEVONthink-style), the active one lit.
    private func writingModes(_ mode: Binding<WritingViewMode>) -> some View {
        HStack(spacing: 2) {
            ForEach([WritingViewMode.source, .split, .preview], id: \.self) { value in
                let active = mode.wrappedValue == value
                Button { mode.wrappedValue = value } label: { ChromeSymbol(name: value.symbol) }
                    .buttonStyle(ChromeButtonStyle(active: active))
                    .help(value.title).accessibilityLabel(value.title)
                    .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain).accessibilityLabel("Vista de escritura")
    }

    private func sourcePanel(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Editor").foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 2)
                if pageViews.editor {
                    sourceZoomTools(compact: width < 160)
                    if width >= 160 {
                        Button { showPageRulers.toggle() } label: { ChromeSymbol(name: "ruler") }
                            .buttonStyle(ChromeButtonStyle()).help("Mostrar u ocultar reglas")
                            .accessibilityLabel("Mostrar u ocultar reglas")
                    }
                }
                if document.plainText != true && document.richTextData == nil {
                    let hiding = settings.editor.hideMarkdown == true
                    Button { settings.editor.hideMarkdown = !hiding } label: { ChromeSymbol(name: "number") }
                        .buttonStyle(ChromeButtonStyle(active: hiding))
                        .help(hiding ? "Mostrar los signos de Markdown" : "Ocultar los signos de Markdown")
                        .accessibilityLabel("Ocultar los signos de Markdown")
                        .accessibilityValue(hiding ? "Activado" : "Desactivado")
                }
                pageToggle("Vista de página del editor", enabled: pageViews.editor) {
                    changeViews { $0.editor.toggle() }
                }
            }
            .font(settings.font(-1)).padding(.horizontal, 10).frame(height: DesignTokens.writingPanelHeaderHeight)
            Divider()
            MarkdownSurface(text: document.markdown, editable: document.trashedAt == nil && pageViews.mode != .preview,
                            taggable: document.trashedAt == nil, options: settings.editor, reveal: reveal,
                            scrollTo: sourceScroll, pageTarget: sourceTarget, insertion: insertion,
                            paper: pageViews.editor
                                ? SourcePaper(layout: pageLayout, metadata: pageInput.metadata, dark: darkPaper) : nil,
                            richTextData: document.richTextData, onRichEdit: { data, text in
                                store.update(document.id, deferWrite: true) { $0.richTextData = data; $0.markdown = text }
                            }, plain: document.plainText == true, showsRulers: showPageRulers,
                            allowsZoom: pageViews.mode == .source,
                            onMargins: { layout in store.update(document.id, touch: false) { $0.pageLayout = layout } },
                            onRulerHeight: { sourceRulerHeight = $0 },
                            onViewport: sourceMoved,
                            onEdit: { text, range, length in
                store.update(document.id, deferWrite: true) {
                    $0.editMarkdown(text, replaced: range, replacementLength: length)
                }
            }, onSelect: { selectedText = $0 }, fragmentAction: markdownFragment)
            .padding(.horizontal, pageViews.editor ? 0 : 20)
            .frame(maxWidth: pageViews.editor ? .infinity : CGFloat(settings.editor.columnWidth))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
    }

    private func previewPanel(width: CGFloat) -> some View {
        let thumbnailMode = width >= 235 && !outlineVisible
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Previsualización").foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                if pageViews.preview {
                    previewTools
                        .popover(isPresented: Binding(
                            get: { showPageThumbnails && !thumbnailMode && !outlineVisible && previewView != nil },
                            set: { showPageThumbnails = $0 }
                        )) {
                            if let previewView { PDFThumbnails(pdf: previewView).frame(width: 140, height: 320) }
                        }
                }
                if pageViews.preview {
                    previewZoomButton("Reducir", symbol: "minus.magnifyingglass", enabled: previewZoom > 0.5) {
                        previewZoom = max(0.5, (previewZoom / 1.25 * 100).rounded() / 100)
                    }
                    previewZoomButton("Ancho del editor", symbol: "1.magnifyingglass", enabled: previewZoom != 1) {
                        previewZoom = 1
                    }
                    previewZoomButton("Aumentar", symbol: "plus.magnifyingglass", enabled: previewZoom < 4) {
                        previewZoom = min(4, (previewZoom * 1.25 * 100).rounded() / 100)
                    }
                }
                pageToggle("Vista de página de la previsualización", enabled: pageViews.preview) {
                    changeViews { $0.preview.toggle() }
                }
            }
            .font(settings.font(-1)).padding(.horizontal, 10).frame(height: DesignTokens.writingPanelHeaderHeight)
            Divider()
            if pageViews.mode == .split, pageViews.editor, showPageRulers, sourceRulerHeight > 0 {
                Rectangle().fill(palette.sidebar).frame(height: sourceRulerHeight).accessibilityHidden(true)
            }
            if pageViews.preview {
                if let rendered {
                    HStack(spacing: 0) {
                        if showPageThumbnails && thumbnailMode, let previewView {
                            PDFThumbnails(pdf: previewView).frame(width: 105)
                            Divider()
                        }
                        PaginatedPreview(pages: rendered.pages, display: pageDisplay, zoom: previewZoom,
                                         allowsPinch: pageViews.mode == .preview,
                                         onZoom: { previewZoom = (($0 * 100).rounded()) / 100 },
                                         destination: previewTarget, onPage: previewMoved,
                                         onView: { previewView = $0 })
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ContinuousMarkdownPreview(input: MarkdownPageInput(source: pageInput.source, plain: pageInput.plain,
                    layout: pageLayout, metadata: pageInput.metadata, dark: scheme == .dark,
                    richTextData: document.richTextData, imageRoots: pageInput.imageRoots,
                    continuousWidth: max(0, width - 40), bodySize: pageInput.bodySize, bodyFont: pageInput.bodyFont,
                    lineSpacing: pageInput.lineSpacing, justified: pageInput.justified, hyphenated: pageInput.hyphenated),
                    sourceTarget: continuousTarget, onSource: continuousMoved) { url in
                    if let target = ItemDestination(url: url) { openDocument(target) }
                    else if ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }

    private func sourceZoomTools(compact: Bool) -> some View {
        Menu {
            Button("Ir a página…") { askForPage(preview: false) }
            if compact { Toggle("Mostrar reglas", isOn: $showPageRulers) }
        } label: { ChromeSymbol(name: "ellipsis") }
        .chromeMenu()
        .help("Opciones de página del editor").accessibilityLabel("Opciones de página del editor")
    }

    private var previewTools: some View {
        Menu {
            Picker("Disposición", selection: $pageDisplay) {
                ForEach(PageDisplay.allCases) { Text($0.rawValue).tag($0) }
            }
            Divider()
            Toggle("Mostrar miniaturas", isOn: $showPageThumbnails)
            Button("Ir a página…") { askForPage() }
        } label: { ChromeSymbol(name: "ellipsis") }
        .chromeMenu()
        .help("Disposición de la previsualización").accessibilityLabel("Disposición de la previsualización")
    }

    private func previewZoomButton(_ label: String, symbol: String, enabled: Bool,
                                   action: @escaping () -> Void) -> some View {
        Button(action: action) { ChromeSymbol(name: symbol) }
            .buttonStyle(ChromeButtonStyle(compact: true)).disabled(!enabled)
            .help(label).accessibilityLabel(label)
    }

    private func pageToggle(_ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { ChromeSymbol(name: enabled ? "doc.fill" : "doc") }
            .buttonStyle(ChromeButtonStyle()).help(label)
            .accessibilityLabel(label).accessibilityValue(enabled ? "Activada" : "Desactivada")
    }

    private func changeViews(_ change: (inout WritingPageViews) -> Void) {
        var next = pageViews
        change(&next)
        guard pageViews != next else { return }
        store.update(document.id, touch: false) { $0.pageViews = next }
    }

    private var previewVisible: Bool { pageViews.mode != .source && pageViews.preview }
    private var sourcePagesVisible: Bool { pageViews.mode != .preview && pageViews.editor }

    private func allowsPageCommand(_ command: LibraryCommand) -> Bool {
        settings.allowsPageCommand(command, for: document)
    }

    private func isPageCommandSelected(_ command: LibraryCommand) -> Bool {
        switch command {
        case .pageEditor: pageViews.editor && !pageViews.preview
        case .pagePreview: pageViews.preview && !pageViews.editor
        case .pageBoth: pageViews.editor && pageViews.preview
        case .pageNone: !pageViews.editor && !pageViews.preview
        case .pageOutline: outlineVisible
        default: false
        }
    }

    private func runPageCommand(_ command: LibraryCommand) {
        switch command {
        case .pageEditor, .pagePreview, .pageBoth, .pageNone:
            changeViews { views in
                views.editor = command == .pageEditor || command == .pageBoth
                views.preview = command == .pagePreview || command == .pageBoth
                if command == .pageBoth { views.mode = .split }
                if command == .pageEditor && views.mode == .preview { views.mode = .source }
                if command == .pagePreview && views.mode == .source { views.mode = .preview }
            }
        case .pageBreak:
            if pageViews.mode == .preview { changeViews { $0.mode = .split } }
            insertion = TextInsertion(text: document.richTextData == nil ? "\n\n" + WritingPageLayout.pageBreak + "\n" : "\u{000C}")
        case .pageOutline: outlineVisible.toggle()
        case .pageSetup: showPageSetup = true
        case .pageGo: askForPage()
        case .pagePDF, .pagePrint:
            if command == .pagePrint, document.attachment?.kind == .pdf, let url = store.attachmentURL(for: document) {
                _ = PDFDocument(url: url)?.printOperation(for: .shared, scalingMode: .pageScaleToFit, autoRotate: true)?.run()
            } else { outputPages(printing: command == .pagePrint) }
        default: break
        }
    }

    private func sourceMoved(_ page: Int, _ count: Int, _ offset: Int) {
        if onReaderState != nil, readerSourceOffset != offset { readerSourceOffset = offset }
        if activeSourcePage != page { activeSourcePage = page }
        if sourcePageCount != count { sourcePageCount = count }
        if pageViews.mode == .split, !pageViews.preview, settings.pages.synchronize {
            if let sourceSyncOffset {
                self.sourceSyncOffset = nil
                if abs(sourceSyncOffset - offset) < 200 { return }
            }
            continuousTarget = TextReveal(range: NSRange(location: offset, length: 0))
            return
        }
        guard pageViews.mode == .split, previewVisible, settings.pages.synchronize, let rendered,
              rendered.input.source == document.markdown else { return }
        if let sourceSyncOffset {
            self.sourceSyncOffset = nil
            if rendered.pages.page(at: offset) == rendered.pages.page(at: sourceSyncOffset) { return }
        }
        let index = rendered.pages.page(at: offset)
        if index != activePreviewPage {
            previewSyncPage = index
            previewTarget = PageDestination(index: index)
        }
    }

    private func continuousMoved(_ offset: Int) {
        if onReaderState != nil, readerPreviewOffset != offset { readerPreviewOffset = offset }
        guard pageViews.mode == .split, settings.pages.synchronize else { return }
        sourceSyncOffset = offset
        sourceScroll = TextReveal(range: NSRange(location: offset, length: 0))
    }

    private func previewMoved(_ index: Int) {
        activePreviewPage = index
        if let previewSyncPage {
            self.previewSyncPage = nil
            if previewSyncPage == index { return }
        }
        guard pageViews.mode == .split, settings.pages.synchronize, let rendered,
              rendered.input.source == document.markdown, rendered.pages.starts.indices.contains(index) else { return }
        let offset = rendered.pages.starts[index]
        sourceSyncOffset = offset
        sourceScroll = TextReveal(range: NSRange(location: offset, length: 0))
    }

    private var readingState: WritingReaderState {
        WritingReaderState(outline: outlineVisible, rulers: showPageRulers, thumbnails: showPageThumbnails,
            sourceZoom: sourceZoom, previewZoom: pageZoom, previewLayout: pageDisplay,
            sourceOffset: readerSourceOffset, previewOffset: readerPreviewOffset, previewPage: activePreviewPage)
    }

    private func restoreReading(_ state: WritingReaderState) {
        let length = document.markdown.utf16.count
        let sourceOffset = min(length, max(0, state.sourceOffset))
        let previewOffset = min(length, max(0, state.previewOffset))
        outlineVisible = state.outline
        showPageRulers = state.rulers
        showPageThumbnails = state.thumbnails
        sourceZoom = state.sourceZoom
        pageZoom = state.previewZoom
        pageDisplay = state.previewLayout
        readerSourceOffset = sourceOffset
        readerPreviewOffset = previewOffset
        sourceSyncOffset = sourceOffset
        previewSyncPage = state.previewPage
        sourceScroll = TextReveal(range: NSRange(location: sourceOffset, length: 0))
        continuousTarget = TextReveal(range: NSRange(location: previewOffset, length: 0))
        previewTarget = PageDestination(index: state.previewPage)
    }

    private func askForPage(preview: Bool? = nil) {
        jumpInPreview = preview ?? previewVisible
        pageNumber = String((jumpInPreview ? activePreviewPage : activeSourcePage) + 1)
        showPageJump = true
    }

    private func goToPage(_ index: Int) {
        if jumpInPreview && previewVisible { previewTarget = PageDestination(index: index) }
        else if sourcePagesVisible { sourceTarget = PageDestination(index: index) }
    }

    private func outputPages(printing: Bool) {
        let input = pageInput
        let pages = rendered.flatMap { $0.input == input ? $0.pages : nil } ?? MarkdownPagination.render(input)
        guard let pages else {
            store.actionError = "No se pudo componer el PDF."
            return
        }
        if printing {
            let info = NSPrintInfo.shared.copy() as? NSPrintInfo
            info?.paperSize = pageLayout.paperSize
            info?.topMargin = 0; info?.bottomMargin = 0; info?.leftMargin = 0; info?.rightMargin = 0
            guard let pdf = PDFDocument(data: pages.data),
                  let operation = pdf.printOperation(for: info, scalingMode: .pageScaleNone, autoRotate: false) else {
                store.actionError = "No se pudo abrir el cuadro de impresión."
                return
            }
            operation.showsPrintPanel = true
            operation.run()
        } else {
            let panel = NSSavePanel()
            panel.title = "Exportar a PDF"
            panel.allowedContentTypes = [.pdf]
            let name = document.displayTitle.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            panel.nameFieldStringValue = name + ".pdf"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do { try pages.data.write(to: url, options: .atomic) }
            catch { store.actionError = "No se pudo exportar el PDF. \(error.localizedDescription)" }
        }
    }

    @ViewBuilder private func attachmentContent(_ asset: DocumentAttachment) -> some View {
        switch asset.kind {
        case .canvas:
            CanvasEditor(store: store, document: document)
        case .pdf:
            if let url = store.attachmentURL(for: document) {
                PDFReader(store: store, item: document, url: url, jump: jump,
                          readerRestore: readerRestore, onReaderState: onReaderState, fragmentAction: handleFragment)
            }
        case .preview:
            if let url = store.attachmentURL(for: document) {
                VStack(spacing: 0) {
                    if let extracted = asset.searchText, !extracted.isEmpty {
                        ChromeSegmented(title: "Vista", selection: $showExtractedText,
                                        options: [(false, "Vista previa"), (true, "Texto")])
                            .frame(width: 230).padding(8)
                        if showExtractedText {
                            MarkdownSurface(text: extracted, editable: false, taggable: document.trashedAt == nil,
                                            options: settings.editor, reveal: reveal,
                                            onEdit: { _, _, _ in }, onSelect: { selectedText = $0 },
                                            fragmentAction: markdownFragment)
                                .padding(.horizontal, 20)
                                .background(settings.editor.customColors ? settings.editor.paper.color : palette.workspace)
                        } else { FilePreview(url: url) }
                    } else { FilePreview(url: url) }
                }
            }
        }
    }

    private var selectableText: String { document.attachment?.searchText ?? document.markdown }

    private func markdownFragment(_ range: NSRange, copy: Bool) {
        guard let anchor = TextAnchor(text: selectableText, range: range) else { return }
        handleFragment(DocumentFragment(quote: anchor.quote, location: .text(anchor)), copy: copy)
    }

    private func handleFragment(_ fragment: DocumentFragment, copy: Bool) {
        if copy {
            store.saveFragment(documentID: document.id, fragment: fragment, tags: [], copyLink: true)
        } else {
            tagFragment = fragment
        }
    }

    private var documentBar: some View {
        HStack(spacing: 14) {
            if document.trashedAt == nil {
                Button("Etiquetas", line: "tag") {
                    if let showInspector { showInspector(.details) } else { showingDetails.toggle() }
                }
                    .popover(isPresented: $showingDetails, arrowEdge: .top) {
                        DocumentDetails(store: store, document: document, openTag: openTag.map { reveal in
                            { tag in showingDetails = false; reveal(tag) }
                        }).padding(16).frame(width: 350)
                    }
                Button("Enlaces", line: "link") {
                    if let showInspector { showInspector(.links) } else { showingLinks.toggle() }
                }
                .popover(isPresented: $showingLinks, arrowEdge: .top) {
                    DocumentLinks(store: store, document: document) { destination in
                        showingLinks = false
                        openDocument(destination)
                    }.padding(15).frame(width: 280)
                }
                if selectedText.length > 0 && ((document.attachment == nil && pageViews.mode != .preview) || showExtractedText) {
                    Menu("Selección", systemImage: "text.cursor") {
                        Button("Etiquetar fragmento…") { markdownFragment(selectedText, copy: false) }
                        Button("Copiar enlace al fragmento") { markdownFragment(selectedText, copy: true) }
                    }.menuStyle(.button).buttonStyle(ChromeButtonStyle()).fixedSize()
                }
            } else {
                Button("Restaurar", line: "arrow.uturn.backward") { setTrashed(false) }
            }
            Spacer()
            if let asset = document.attachment {
                Text(asset.kind.label).foregroundStyle(.secondary)
            } else if settings.editor.showWordCount {
                let wordCount = document.markdown.split(whereSeparator: \.isWhitespace).count
                Text(wordCount == 1 ? "1 palabra" : "\(wordCount) palabras").foregroundStyle(.secondary)
            }
            if document.attachment == nil, sourcePagesVisible {
                Button("Editor \(activeSourcePage + 1)/\(sourcePageCount)") { askForPage(preview: false) }
                    .help("Página del editor")
            }
            if document.attachment == nil, previewVisible, let rendered {
                Button("Página \(activePreviewPage + 1) de \(rendered.pages.starts.count)") { askForPage() }
            }
            Menu {
                if document.attachment == nil {
                    Button("Exportar a PDF…", line: "doc") { outputPages(printing: false) }
                    Button("Imprimir…", line: "printer") { outputPages(printing: true) }
                }
                Button("Exportar…", line: "square.and.arrow.up") { store.exportDocument(document) }
                if document.trashedAt == nil {
                    Divider()
                    Button(LibraryCommand.moveToTrash.title, line: "trash") { setTrashed(true) }
                }
            } label: {
                ChromeSymbol(name: "ellipsis")
            }
            .menuStyle(.button).buttonStyle(ChromeButtonStyle())
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Acciones del texto")
        }
        .font(settings.font(-1))
        .buttonStyle(ChromeButtonStyle())
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 14)
        .frame(height: 36)
    }

    private func setTrashed(_ trashed: Bool) {
        if store.setTrashed(document.id, trashed) { onTrashChange() }
    }

    private func binding(_ keyPath: WritableKeyPath<WritingDocument, String>) -> Binding<String> {
        Binding(get: { store.document(document.id)?[keyPath: keyPath] ?? "" }, set: { value in
            store.update(document.id) { $0[keyPath: keyPath] = value }
        })
    }
}

struct DocumentLinks: View {
    @Environment(AppSettings.self) private var settings
    var store: LibraryStore
    var document: WritingDocument
    var openDocument: (ItemDestination) -> Void

    var body: some View {
        let active = store.library.activeDocuments.filter { $0.id != document.id }
        let outgoing = document.linkTargets.sorted { $0.url.absoluteString < $1.url.absoluteString }
        let incoming = active.filter { $0.linkedDocumentIDs.contains(document.id) }.map { ItemDestination($0.id) }
        return VStack(alignment: .leading, spacing: 10) {
            Button("Copiar enlace Markdown", line: "doc.on.doc") {
                copyText(store.destination(document.id).markdownLink(label: document.displayTitle))
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    linkSection("Enlaza a", documents: outgoing)
                    linkSection("Enlazado desde", documents: incoming)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 190)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .frame(width: 280)
    }

    private func linkSection(_ title: String, documents: [ItemDestination]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(settings.font(-1, bold: true)).foregroundStyle(.secondary)
            if documents.isEmpty {
                Text("Sin enlaces").foregroundStyle(.secondary)
            }
            ForEach(documents, id: \.self) { linked in
                let target = store.document(linked.documentID)
                let fragment = target?.fragments?.first { $0.id == linked.fragmentID }
                Button(fragment?.quote ?? target?.displayTitle ?? "Documento no disponible", systemImage: "arrow.up.right") { openDocument(linked) }
                .buttonStyle(.link)
            }
        }
    }

}

struct DocumentDetails: View {
    @Environment(AppSettings.self) private var settings
    var store: LibraryStore
    var document: WritingDocument
    var openTag: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Picker("Estado", selection: Binding(
                get: { document.stage }, set: { stage in store.update(document.id) { $0.stage = stage } }
            )) {
                ForEach(DraftStage.allCases, id: \.self) { stage in
                    Text(stage.title).tag(stage)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Etiquetas del documento").font(settings.font(-1, bold: true)).foregroundStyle(.secondary)
                TagEditor(tags: document.tags, suggestions: store.library.availableTags,
                          change: { store.setTags($0, at: ItemDestination(document.id)) }, reveal: openTag)
                let dynamic = store.library.effectiveTags(of: document).filter { !document.tags.contains($0) }
                if !dynamic.isEmpty {
                    Text("Dinámicas").font(settings.font(-1)).foregroundStyle(.secondary)
                    ForEach(dynamic, id: \.self) { tag in
                        if let openTag { Button(tag) { openTag(tag) }.buttonStyle(.link) }
                        else { Text(tag) }
                    }
                }
            }

            if !store.library.projects.isEmpty {
                Divider()
                Text("Grupos").font(settings.font(-1, bold: true)).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(store.library.projects) { project in
                            Toggle(store.library.groupPath(of: project.id), isOn: Binding(
                                get: { document.projectIDs.contains(project.id) }, set: { enabled in
                                    store.update(document.id) {
                                        if enabled { $0.projectIDs.insert(project.id) }
                                        else { $0.projectIDs.remove(project.id) }
                                    }
                                }
                            ))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
