import PDFKit
import SwiftUI
import UniformTypeIdentifiers
import Vision
import WritingLibrary

struct PDFReader: View {
    @Environment(AppSettings.self) private var settings
    var store: LibraryStore
    var item: WritingDocument
    var url: URL
    var jump: JumpRequest?
    var readerRestore: DocumentReaderRestore? = nil
    var onReaderState: ((DocumentReaderState) -> Void)? = nil
    var fragmentAction: (DocumentFragment, Bool) -> Void

    @ViewState private var pdfView: PDFView?
    @ViewState private var pageNumber = 1
    @ViewState private var pageInput = "1"
    @ViewState private var selectionAvailable = false
    @ViewState private var find = ""
    @ViewState private var matches: [PDFSelection] = []
    @ViewState private var matchIndex = 0
    @ViewState private var inspector: Inspector?
    @ViewState private var editingNote = false
    @ViewState private var note = ""
    @ViewState private var revision = 0
    @ViewState private var recognitionRunning = false
    @ViewState private var recognitionMessage: String?
    @ViewState private var password = ""

    private enum Inspector: String { case thumbnails = "Miniaturas", outline = "Índice", annotations = "Anotaciones" }

    var body: some View {
        Group {
            if let pdfView, let pdf = pdfView.document {
                if pdf.isLocked {
                    VStack(spacing: 12) {
                        Label("PDF protegido", line: "lock")
                        SecureField("Contraseña del PDF", text: $password).onSubmit(unlock).frame(width: 220)
                        Button("Abrir PDF", action: unlock)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        toolbar
                        Divider()
                        HStack(spacing: 0) {
                            if let inspector {
                                inspectorBody(inspector, pdf: pdf).frame(width: 170)
                                Divider()
                            }
                            PDFSurface(pdf: pdfView)
                                .accessibilityLabel("Visor PDF")
                                .onAppear {
                                    if readerRestore == nil { revealFragment() } else { restoreReading() }
                                }
                        }
                        findBar
                    }
                }
            } else {
                ContentUnavailableView("No se pudo abrir el PDF", systemImage: "doc.badge.ellipsis")
            }
        }
        .onAppear(perform: load)
        .onChange(of: jump) {
            if readerRestore == nil { revealFragment() }
        }
        .onChange(of: readerRestore) { restoreReading() }
        .onChange(of: settings.reader.pdfLayout) { setDisplay(settings.reader.pdfLayout.displayMode) }
        .onChange(of: settings.reader.pdfSidebar) { inspector = initialInspector }
        .onChange(of: inspector) { reportReading() }
        .onChange(of: settings.reader.pdfZoom) { if let pdfView { applyZoom(to: pdfView) } }
        .onChange(of: settings.reader.pdfBackground) { if let pdfView { applyBackground(to: pdfView) } }
        .onReceive(NotificationCenter.default.publisher(for: .PDFViewPageChanged)) { event in
            if event.object as? PDFView === pdfView { updatePage() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .PDFViewScaleChanged)) { event in
            if event.object as? PDFView === pdfView { reportReading() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .PDFViewSelectionChanged)) { event in
            if event.object as? PDFView === pdfView { selectionAvailable = pdfView?.currentSelection?.string?.isEmpty == false }
        }
        .sheet(isPresented: $editingNote) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Nota en la página \(pageNumber)").font(.headline)
                TextEditor(text: $note).frame(width: 350, height: 110)
                HStack {
                    Spacer()
                    Button("Cancelar") { editingNote = false }
                    Button("Guardar nota") { insertNote(); editingNote = false }
                        .keyboardShortcut(.defaultAction).disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(20)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Menu("Paneles del PDF", line: "sidebar.left") {
                Button("Cerrar panel") { inspector = nil }
                Divider()
                Button("Miniaturas") { inspector = .thumbnails }
                Button("Índice") { inspector = .outline }
                Button("Anotaciones") { inspector = .annotations }
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).labelStyle(.iconOnly).fixedSize()
            Button("Página anterior", line: "chevron.up") { goTo(pageNumber - 1) }.disabled(pageNumber <= 1)
            TextField("Página", text: $pageInput).frame(width: 39).onSubmit {
                goTo(Int(pageInput) ?? pageNumber)
                updatePage()
            }.accessibilityLabel("Página")
            Text("/ \(pdfView?.document?.pageCount ?? 0)").font(.caption).foregroundStyle(.secondary)
            Button("Página siguiente", line: "chevron.down") { goTo(pageNumber + 1) }
                .disabled(pageNumber >= (pdfView?.document?.pageCount ?? 0))
            Divider().frame(height: 16)
            Button("Alejar", line: "minus.magnifyingglass") { pdfView?.zoomOut(nil) }
            Button("Acercar", line: "plus.magnifyingglass") { pdfView?.zoomIn(nil) }
            Button("Ajustar zoom", line: "arrow.up.left.and.arrow.down.right") { pdfView?.autoScales = true }
            Spacer(minLength: 2)
            Menu("Marcado PDF", systemImage: "highlighter") {
                Button("Resaltar") { markup(.highlight, color: .systemYellow) }.disabled(!selectionAvailable)
                Button("Subrayar") { markup(.underline, color: .systemTeal) }.disabled(!selectionAvailable)
                Button("Tachar") { markup(.strikeOut, color: .systemRed) }.disabled(!selectionAvailable)
                Button("Añadir nota…") { note = ""; editingNote = true }
                Divider()
                Button("Girar página a la izquierda") { rotate(-90) }
                Button("Girar página a la derecha") { rotate(90) }
                Button("Guardar anotaciones y formulario") { _ = savePDF() }
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).labelStyle(.iconOnly).fixedSize()
                .disabled(item.trashedAt != nil || pdfView?.document?.isEncrypted == true)
            Menu("Selección y enlaces", line: "link") {
                Button("Copiar enlace a esta página") { pageAction(copy: true, selection: false) }
                Button("Etiquetar página…") { pageAction(copy: false, selection: false) }
                Divider()
                Button("Copiar enlace a la selección") { pageAction(copy: true, selection: true) }.disabled(!selectionAvailable)
                Button("Etiquetar selección…") { pageAction(copy: false, selection: true) }.disabled(!selectionAvailable)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).labelStyle(.iconOnly).fixedSize().disabled(item.trashedAt != nil)
            Menu("Más herramientas PDF", line: "ellipsis") {
                Button("Página individual") { setDisplay(.singlePage) }
                Button("Desplazamiento continuo") { setDisplay(.singlePageContinuous) }
                Button("Doble página") { setDisplay(.twoUpContinuous) }
                Divider()
                Button("Exportar página actual…", action: exportPage)
                Button("Reconocer texto para la biblioteca (OCR)", action: recognize).disabled(recognitionRunning || item.trashedAt != nil)
                Button("Imprimir…") { _ = pdfView?.document?.printOperation(for: NSPrintInfo.shared, scalingMode: .pageScaleToFit, autoRotate: true)?.run() }
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).labelStyle(.iconOnly).fixedSize()
        }
        .labelStyle(.iconOnly).buttonStyle(ChromeButtonStyle())
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private var findBar: some View {
        HStack(spacing: 7) {
            ChromeSymbol(name: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Buscar en el PDF", text: $find).onSubmit(search)
            Button("Buscar", action: search)
            if !matches.isEmpty {
                Text("\(matchIndex + 1) de \(matches.count)").monospacedDigit().font(.caption)
                Button("Coincidencia anterior", line: "chevron.up") { showMatch(matchIndex - 1) }.labelStyle(.iconOnly)
                    .buttonStyle(ChromeButtonStyle())
                Button("Coincidencia siguiente", line: "chevron.down") { showMatch(matchIndex + 1) }.labelStyle(.iconOnly)
                    .buttonStyle(ChromeButtonStyle())
            }
            if recognitionRunning { ProgressView().controlSize(.small) }
            if let recognitionMessage { Text(recognitionMessage).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
        }.padding(.horizontal, 12).padding(.vertical, 6)
            .onChange(of: find) { matches = []; pdfView?.highlightedSelections = nil }
    }

    @ViewBuilder private func inspectorBody(_ pane: Inspector, pdf: PDFDocument) -> some View {
        switch pane {
        case .thumbnails:
            if let pdfView { PDFThumbnails(pdf: pdfView).id(revision) }
        case .outline:
            let entries = (pdf.outlineRoot.map(outlineChildren)) ?? []
            if entries.isEmpty {
                Text("Sin índice").foregroundStyle(.secondary).padding()
            } else {
                List {
                    SwipeTree(nodes: entries, children: { $0.children }) { entry in
                        Button(entry.title) { if let destination = entry.outline.destination { pdfView?.go(to: destination) } }
                            .buttonStyle(.plain)
                    }
                }
            }
        case .annotations:
            let annotations = annotationEntries(pdf)
            if annotations.isEmpty { Text("Sin anotaciones").foregroundStyle(.secondary).padding() }
            else {
                List(annotations) { entry in
                    Button {
                        if let page = entry.annotation.page { pdfView?.go(to: entry.annotation.bounds, on: page) }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(entry.annotation.contents ?? entry.annotation.type ?? "Marca").lineLimit(2)
                            Text("Página \(entry.page + 1)").font(.caption).foregroundStyle(.secondary)
                        }
                    }.buttonStyle(.plain)
                        .contextMenu {
                            Button("Copiar enlace a la anotación") { annotationAction(entry, copy: true) }
                                .disabled(item.trashedAt != nil)
                            Button("Etiquetar anotación…") { annotationAction(entry, copy: false) }
                                .disabled(item.trashedAt != nil)
                            Button("Quitar anotación", role: .destructive) {
                                if let page = entry.annotation.page {
                                    page.removeAnnotation(entry.annotation)
                                    if !savePDF() { page.addAnnotation(entry.annotation) }
                                }
                            }.disabled(item.trashedAt != nil || pdf.isEncrypted)
                        }
                }.id(revision)
            }
        }
    }

    private func load() {
        guard pdfView == nil, let document = PDFDocument(url: url) else { return }
        let view = PDFView()
        view.displayMode = settings.reader.pdfLayout.displayMode
        view.document = document
        applyZoom(to: view)
        applyBackground(to: view)
        inspector = initialInspector
        pdfView = view
        restoreReading()
        updatePage()
    }

    private func setDisplay(_ mode: PDFDisplayMode) {
        pdfView?.displayMode = mode
        reportReading()
    }

    private func reportReading() {
        guard let onReaderState, let view = pdfView, let document = view.document, !document.isLocked else { return }
        let page = view.currentPage.map { document.index(for: $0) + 1 } ?? pageNumber
        onReaderState(.pdf(PDFReaderState(page: page, scale: view.scaleFactor, autoScale: view.autoScales,
            display: view.displayMode.rawValue, inspector: inspector?.rawValue)))
    }

    private func restoreReading() {
        guard case .pdf(let snapshot) = readerRestore?.state, let view = pdfView,
              let document = view.document, !document.isLocked else { return }
        inspector = snapshot.inspector.flatMap(Inspector.init(rawValue:))
        if let mode = PDFDisplayMode(rawValue: snapshot.display) { view.displayMode = mode }
        view.autoScales = snapshot.autoScale
        if !snapshot.autoScale, snapshot.scale > 0 { view.scaleFactor = snapshot.scale }
        goTo(min(snapshot.page, document.pageCount))
        updatePage()
    }

    private var initialInspector: Inspector? {
        switch settings.reader.pdfSidebar {
        case .closed: nil
        case .thumbnails: .thumbnails
        case .outline: .outline
        }
    }

    private func applyZoom(to view: PDFView) {
        view.autoScales = settings.reader.pdfZoom == .fit
        if !view.autoScales { view.scaleFactor = 1 }
    }

    private func applyBackground(to view: PDFView) {
        switch settings.reader.pdfBackground {
        case .system: view.backgroundColor = .windowBackgroundColor
        case .light: view.backgroundColor = NSColor(white: 0.91, alpha: 1)
        case .dark: view.backgroundColor = NSColor(white: 0.12, alpha: 1)
        }
    }

    private func unlock() {
        if pdfView?.document?.unlock(withPassword: password) == true {
            updatePage()
            password = ""
            revision += 1
            if readerRestore == nil { revealFragment() } else { restoreReading() }
        } else { store.actionError = "Contraseña incorrecta." }
    }

    private func updatePage() {
        if let view = pdfView, let pdf = view.document, let page = view.currentPage {
            pageNumber = pdf.index(for: page) + 1
            pageInput = String(pageNumber)
        }
        reportReading()
    }

    private func goTo(_ number: Int) {
        if let view = pdfView, let pdf = view.document, (1...max(1, pdf.pageCount)).contains(number),
           let page = pdf.page(at: number - 1) { view.go(to: page) }
    }

    private func search() {
        guard let view = pdfView, let pdf = view.document, !find.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        matches = pdf.findString(find, withOptions: [.caseInsensitive, .diacriticInsensitive])
        view.highlightedSelections = matches
        if matches.isEmpty { store.actionError = "Sin coincidencias en la capa de texto del PDF." }
        else { showMatch(0) }
    }

    private func showMatch(_ index: Int) {
        guard !matches.isEmpty, let view = pdfView else { return }
        matchIndex = (index + matches.count) % matches.count
        view.setCurrentSelection(matches[matchIndex], animate: true)
        view.go(to: matches[matchIndex])
    }

    private func pageAction(copy: Bool, selection: Bool) {
        guard let view = pdfView, let pdf = view.document, let current = view.currentPage else { return }
        if selection {
            guard let selected = view.currentSelection, let quote = selected.string, !quote.isEmpty,
                  let first = selected.pages.first else { return }
            let spans = selected.pages.flatMap { page -> [PDFTextSpan] in
                guard let text = page.string else { return [] }
                let index = pdf.index(for: page)
                return (0..<selected.numberOfTextRanges(on: page)).compactMap { part in
                    TextAnchor(text: text, range: selected.range(at: part, on: page)).map { PDFTextSpan(page: index, anchor: $0) }
                }
            }
            guard !spans.isEmpty else { store.actionError = "No se pudo localizar esta selección en la capa de texto."; return }
            fragmentAction(DocumentFragment(quote: quote, location: .pdf(page: pdf.index(for: first), spans: spans)), copy)
        } else {
            let index = pdf.index(for: current)
            fragmentAction(DocumentFragment(quote: "Página \(index + 1)", location: .pdf(page: index, spans: [])), copy)
        }
    }

    private func revealFragment() {
        guard let id = jump?.destination.fragmentID, let view = pdfView, let pdf = view.document, !pdf.isLocked,
              let fragment = item.fragments?.first(where: { $0.id == id }) else { return }
        if case .pdfArea(let page, let rect) = fragment.location {
            if (0..<pdf.pageCount).contains(page), let destination = pdf.page(at: page) {
                view.clearSelection()
                view.go(to: rect, on: destination)
            } else { store.actionError = "La página enlazada no está disponible." }
            return
        }
        guard case .pdf(let pageIndex, let spans) = fragment.location else { return }
        guard pageIndex >= 0, pageIndex < pdf.pageCount, let page = pdf.page(at: pageIndex) else {
            store.actionError = "La página enlazada no está disponible."
            return
        }
        view.go(to: page)
        let parts = spans.compactMap { span -> PDFSelection? in
            guard span.page >= 0, span.page < pdf.pageCount, let page = pdf.page(at: span.page),
                  let text = page.string, let range = span.anchor.resolve(in: text) else { return nil }
            return page.selection(for: range)
        }
        if let first = parts.first, parts.count == spans.count {
            first.add(Array(parts.dropFirst()))
            view.setCurrentSelection(first, animate: true)
            view.go(to: first)
        } else if !spans.isEmpty {
            store.actionError = "La selección enlazada ya no se encuentra en el PDF."
        } else { view.clearSelection() }
    }

    private func annotationAction(_ entry: PDFAnnotationEntry, copy: Bool) {
        let annotation = entry.annotation
        let quote = annotation.contents ?? "Anotación de la página \(entry.page + 1)"
        fragmentAction(DocumentFragment(quote: quote, location: .pdfArea(page: entry.page, bounds: annotation.bounds)), copy)
    }

    private func exportPage() {
        guard let page = pdfView?.currentPage, let data = page.dataRepresentation else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Página \(pageNumber).pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try data.write(to: url, options: .atomic) }
        catch { store.actionError = error.localizedDescription }
    }

    private func markup(_ type: PDFAnnotationSubtype, color: NSColor) {
        guard let lines = pdfView?.currentSelection?.selectionsByLine() else { return }
        var added: [(PDFPage, PDFAnnotation)] = []
        for line in lines {
            for page in line.pages {
                let bounds = line.bounds(for: page)
                guard !bounds.isEmpty else { continue }
                let annotation = PDFAnnotation(bounds: bounds, forType: type, withProperties: nil)
                annotation.color = color
                annotation.contents = line.string
                setAuthor(of: annotation)
                page.addAnnotation(annotation)
                added.append((page, annotation))
            }
        }
        guard !added.isEmpty else { return }
        if !savePDF() { for (page, annotation) in added { page.removeAnnotation(annotation) } }
        pdfView?.clearSelection()
    }

    private func insertNote() {
        guard let page = pdfView?.currentPage else { return }
        let bounds = page.bounds(for: .cropBox)
        let selection = pdfView?.currentSelection?.bounds(for: page)
        let point = selection.flatMap { $0.isEmpty ? nil : $0.origin }
            ?? CGPoint(x: bounds.minX + 30, y: bounds.maxY - 46 - CGFloat(page.annotations.count % 12) * 22)
        let annotation = PDFAnnotation(bounds: CGRect(origin: point, size: CGSize(width: 21, height: 21)),
                                       forType: .text, withProperties: nil)
        annotation.contents = note
        annotation.color = .systemYellow
        setAuthor(of: annotation)
        page.addAnnotation(annotation)
        if !savePDF() { page.removeAnnotation(annotation) }
    }

    private func setAuthor(of annotation: PDFAnnotation) {
        let author = settings.reader.author.trimmingCharacters(in: .whitespacesAndNewlines)
        if !author.isEmpty { annotation.userName = author }
    }

    private func rotate(_ degrees: Int) {
        guard let page = pdfView?.currentPage else { return }
        let old = page.rotation
        page.rotation = (old + degrees + 360) % 360
        if !savePDF() { page.rotation = old }
        pdfView?.layoutDocumentView()
    }

    private func savePDF() -> Bool {
        guard let data = pdfView?.document?.dataRepresentation() else { store.actionError = "No se pudo generar el PDF."; return false }
        do {
            try data.write(to: url, options: .atomic)
            revision += 1
            pdfView?.needsDisplay = true
            return true
        } catch { store.actionError = error.localizedDescription; return false }
    }

    private func recognize() {
        recognitionRunning = true
        recognitionMessage = nil
        Task { @MainActor in
            defer { recognitionRunning = false }
            do {
                let output = try await Task.detached(priority: .userInitiated) { try recognizePDF(at: url) }.value
                if output.isEmpty { recognitionMessage = "OCR: sin texto reconocido" }
                else if store.update(item.id, { $0.attachment?.searchText = output }) { recognitionMessage = "OCR añadido a la búsqueda" }
            } catch { store.actionError = "Error de OCR. \(error.localizedDescription)" }
        }
    }
}

private extension PDFLayout {
    var displayMode: PDFDisplayMode {
        switch self {
        case .continuous: .singlePageContinuous
        case .single: .singlePage
        case .facing: .twoUpContinuous
        }
    }
}

private nonisolated func recognizePDF(at url: URL) throws -> String {
    guard let document = PDFDocument(url: url), !document.isLocked else { throw CocoaError(.fileReadNoPermission) }
    var text: [String] = []
    for index in 0..<document.pageCount {
        guard let page = document.page(at: index) else { continue }
        let existing = page.string ?? ""
        var bounds = CGRect(x: 0, y: 0, width: 1800, height: 1800)
        let thumbnail = page.thumbnail(of: bounds.size, for: .cropBox)
        guard let image = thumbnail.cgImage(forProposedRect: &bounds, context: nil, hints: nil) else {
            text.append(existing)
            continue
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["es-ES", "en-US"]
        try VNImageRequestHandler(cgImage: image).perform([request])
        let recognized = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        text.append(existing + "\n" + recognized)
    }
    return text.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
}

private struct PDFSurface: NSViewRepresentable {
    let pdf: PDFView
    func makeNSView(context: Context) -> PDFView { pdf }
    func updateNSView(_ view: PDFView, context: Context) {}
}

struct PDFThumbnails: NSViewRepresentable {
    let pdf: PDFView
    func makeNSView(context: Context) -> PDFThumbnailView {
        let view = PDFThumbnailView()
        view.pdfView = pdf
        view.maximumNumberOfColumns = 1
        view.thumbnailSize = CGSize(width: 115, height: 140)
        return view
    }
    func updateNSView(_ view: PDFThumbnailView, context: Context) {
        if view.pdfView !== pdf { view.pdfView = pdf }
    }
}

private struct PDFOutlineEntry: Identifiable {
    var id: ObjectIdentifier { ObjectIdentifier(outline) }
    let outline: PDFOutline
    var title: String { outline.label ?? "Sección" }
    var children: [Self]? { let entries = outlineChildren(outline); return entries.isEmpty ? nil : entries }
}

private func outlineChildren(_ outline: PDFOutline) -> [PDFOutlineEntry] {
    (0..<outline.numberOfChildren).compactMap { outline.child(at: $0).map(PDFOutlineEntry.init(outline:)) }
}

private struct PDFAnnotationEntry: Identifiable {
    var id: ObjectIdentifier { ObjectIdentifier(annotation) }
    let page: Int
    let annotation: PDFAnnotation
}

private func annotationEntries(_ pdf: PDFDocument) -> [PDFAnnotationEntry] {
    (0..<pdf.pageCount).flatMap { index in
        (pdf.page(at: index)?.annotations ?? []).filter { $0.type != "Widget" && $0.type != "Link" }
            .map { PDFAnnotationEntry(page: index, annotation: $0) }
    }
}
