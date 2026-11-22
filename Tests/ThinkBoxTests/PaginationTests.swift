import AppKit
import PDFKit
import Testing
import WritingLibrary
@testable import ThinkBox

@MainActor private func input(_ text: String, plain: Bool = false) -> MarkdownPageInput {
    MarkdownPageInput(source: text, plain: plain, layout: WritingPageLayout(),
        metadata: PageMetadata(title: "Prueba", date: Date(timeIntervalSince1970: 0), library: "Base", group: "Grupo", author: "Autor"), dark: false)
}

@Test @MainActor func manualBreakProducesMatchingPDFPages() throws {
    let source = "# Primera\n\nContenido\n" + WritingPageLayout.pageBreak + "\n# Segunda\n\nFinal"
    let pages = try #require(MarkdownPagination.render(input(source)))
    let pdf = try #require(PDFDocument(data: pages.data))
    #expect(pdf.pageCount == 2)
    #expect(pages.starts.count == pdf.pageCount)
    #expect(pdf.page(at: 0)?.string?.contains("Primera") == true)
    #expect(pdf.page(at: 1)?.string?.contains("Segunda") == true)
    #expect(pages.page(at: source.utf16.count) == 1)
}

@Test @MainActor func fencedManualBreakIsLiteral() throws {
    let pages = try #require(MarkdownPagination.render(input("```html\n" + WritingPageLayout.pageBreak + "\n```")))
    #expect(PDFDocument(data: pages.data)?.pageCount == 1)
}

@Test @MainActor func backgroundPreviewUsesTheSameCompositionAsExport() async throws {
    let request = input("# Encabezado\n\nTexto **importante**.[^a]\n\n[^a]: Una nota")
    let output = try #require(MarkdownPagination.render(request))
    let preview = await MarkdownPagination.renderPreview(request)
    let rendered = try #require(preview)
    #expect(rendered.starts == output.starts)
    #expect(PDFDocument(data: rendered.data)?.string == PDFDocument(data: output.data)?.string)
}

@Test @MainActor func continuousPreviewCarriesSourcePositions() throws {
    let rendered = MarkdownPagination.continuous(input("# Título\n\nÚltimo párrafo"))
    #expect(rendered.string.contains("Último párrafo"))
    let range = (rendered.string as NSString).range(of: "Último")
    #expect(rendered.attribute(MarkdownPagination.sourcePosition, at: range.location, effectiveRange: nil) as? Int == 10)
}

@Test @MainActor func richTextSurvivesPaginationAndStorage() throws {
    let value = NSAttributedString(string: "Texto enriquecido", attributes: [.font: NSFont.boldSystemFont(ofSize: 18)])
    let data = try value.data(from: NSRange(location: 0, length: value.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
    var request = input(value.string)
    request.richTextData = data
    let pages = try #require(MarkdownPagination.render(request))
    #expect(PDFDocument(data: pages.data)?.string?.contains(value.string) == true)
    var document = WritingDocument(markdown: value.string)
    document.richTextData = data
    #expect(try JSONDecoder().decode(WritingDocument.self, from: JSONEncoder().encode(document)).richTextData == data)
}

@Test @MainActor func workspaceRoundTripKeepsTabsAndPanels() throws {
    let panels = TabPanels(sidebarVisible: false, sidebarWidth: 280, listVisible: true,
        listWidth: 210, listHeight: 180, inspectorVisible: true, inspectorWidth: 300)
    let base = UUID()
    let target = ItemDestination(UUID(), databaseID: base)
    let tab = LibraryTab(location: LibraryLocation(scope: .tag("Uno/Dos"), selection: target,
                                                  query: "consulta", databaseID: base), panels: panels)
    let reader = DocumentReaderState.writing(WritingReaderState(outline: true, rulers: true, thumbnails: false,
        sourceZoom: .percent(125), previewZoom: .fit, previewLayout: .spreads, sourceOffset: 30,
        previewOffset: 0, previewPage: 2))
    let window = SavedDocumentWindow(destination: target, x: 21, y: 25, width: 800, height: 640,
                                     inspectorVisible: true, inspectorWidth: 280, minimized: false, reader: reader)
    let workspace = SavedWorkspace(name: "Escritura", tabs: [tab], activeTab: 0, layouts: Data(), inspector: .links,
                                   documentWindows: [window], mainFrame: SavedWindowFrame(CGRect(x: 2, y: 5, width: 940, height: 680)))
    let restored = try JSONDecoder().decode(SavedWorkspace.self, from: JSONEncoder().encode(workspace))
    #expect(restored.tabs.first?.location == tab.location)
    #expect(restored.tabs.first?.panels?.sidebarVisible == false)
    #expect(restored.tabs.first?.panels?.inspectorWidth == 300)
    #expect(restored.documentWindows?.first?.reader == reader)
    #expect(restored.documentWindows?.first?.destination == target)
    #expect(restored.mainFrame?.width == 940)
}

@Test @MainActor func longDocumentPaginatesWithoutLosingTheEnd() throws {
    let text = (0..<1200).map { "Párrafo \($0). Texto de referencia para comprobar paginación y continuidad.\n" }.joined()
    let pages = try #require(MarkdownPagination.render(input(text, plain: true)))
    let pdf = try #require(PDFDocument(data: pages.data))
    #expect(pdf.pageCount > 20)
    #expect(pdf.page(at: pdf.pageCount - 1)?.string?.contains("1199") == true)
    #expect(pages.starts == pages.starts.sorted())
}

@Test @MainActor func paginatedTablesAndFootnotesKeepTheirContentAndPage() throws {
    let tableRows = (0..<67).map { "| Fila\($0)Z | Celda \($0) |" }.joined(separator: "\n")
    let text = """
    Referencia inicial[^primera].

    | Producto | Importe |
    | --- | ---: |
    \(tableRows)

    \(WritingPageLayout.pageBreak)
    Una referencia independiente[^segunda].

    [^primera]: Nota exclusiva de la primera página.
    [^segunda]: Nota propia del último folio.
        Sigue en otra línea.
    """
    let pages = try #require(MarkdownPagination.render(input(text)))
    let pdf = try #require(PDFDocument(data: pages.data))
    #expect(pdf.pageCount >= 3)
    #expect(pdf.page(at: 0)?.string?.contains("Nota exclusiva") == true)
    #expect(pdf.page(at: 0)?.string?.contains("Nota propia") == false)
    #expect(pdf.page(at: pdf.pageCount - 1)?.string?.contains("Sigue en otra línea") == true)
    let output = try #require(pdf.string)
    for number in 0..<67 { #expect(output.components(separatedBy: "Fila\(number)Z").count == 2) }
    #expect(!output.contains("[^"))
    #expect(pages.starts == pages.starts.sorted())
}

@Test @MainActor func aLocalImageFitsTheColumnAndAppearsInTheComposedPDF() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let image = NSImage(size: CGSize(width: 840, height: 700), flipped: false) { rect in
        NSColor.red.setFill()
        NSBezierPath(rect: rect).fill()
        return true
    }
    let tiff = try #require(image.tiffRepresentation)
    try tiff.write(to: folder.appending(path: "una imagen.tiff"))
    let source = "![Muestra](una%20imagen.tiff)\n\nFin."
    var request = input(source)
    request.imageRoots = [folder]
    let rendered = MarkdownPagination.continuous(request)
    let attachment = try #require(rendered.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment)
    #expect(attachment.image?.size.width ?? 0 > 0)
    #expect(attachment.image?.size.width ?? 0 <= request.layout.contentRect(page: 0).width)
    let pages = try #require(MarkdownPagination.render(request))
    let pdf = try #require(PDFDocument(data: pages.data))
    let page = try #require(pdf.page(at: 0))
    let thumbnail = page.thumbnail(of: CGSize(width: 220, height: 312), for: .mediaBox)
    let thumbnailData = try #require(thumbnail.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: thumbnailData))
    var redPixels = 0
    for y in stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
        for x in stride(from: 0, to: bitmap.pixelsWide, by: 4) {
            if let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
               pixel.redComponent > 0.8, pixel.greenComponent < 0.3 { redPixels += 1 }
        }
    }
    #expect(redPixels > 300)
    #expect(pdf.string?.contains("Fin.") == true)
}

@Test @MainActor func editAndLayoutBenchmarkForAtLeast300Pages() throws {
    let storeURL = FileManager.default.temporaryDirectory.appending(path: "ThinkBox-long-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: storeURL) }
    let store = LibraryStore(fileURL: storeURL)
    let text = (0..<18_000).map { "Línea \($0): selección, acentos y edición.\n" }.joined()
    let document = WritingDocument(title: "Medición", markdown: text)
    #expect(store.commit { $0.documents.append(document) })

    let layout = WritingPageLayout()
    let metadata = input(text).metadata
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 680, height: 580))
    let storage = NSTextStorage(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13)])
    let manager = NSLayoutManager()
    storage.addLayoutManager(manager)
    let rect = layout.contentRect(page: 0)
    let container = NSTextContainer(size: NSSize(width: rect.width, height: .greatestFiniteMagnitude))
    manager.addTextContainer(container)
    let flow = PageFlow()
    flow.layout = layout
    manager.delegate = flow
    let editor = MarkdownSurface.Editor(frame: scroll.bounds, textContainer: container)
    editor.storage = storage
    editor.isVerticallyResizable = false
    editor.paper = SourcePaper(layout: layout, metadata: metadata, dark: false)
    scroll.documentView = editor
    editor.updatePaperFrame(in: scroll)
    #expect(editor.pageCount >= 300)

    let clock = ContinuousClock()
    var durations: [Double] = []
    var inserts: [Double] = []
    var saves: [Double] = []
    func milliseconds(_ duration: Duration) -> Double {
        let elapsed = duration.components
        return Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
    }
    for offset in [10, storage.length / 2, storage.length - 25] {
        for _ in 0..<7 {
            let start = clock.now
            editor.insertText("á", replacementRange: NSRange(location: offset, length: 0))
            let afterInsert = clock.now
            inserts.append(milliseconds(start.duration(to: afterInsert)))
            #expect(store.update(document.id, deferWrite: true) {
                $0.editMarkdown(editor.string, replaced: NSRange(location: offset, length: 0), replacementLength: 1)
            })
            saves.append(milliseconds(afterInsert.duration(to: clock.now)))
            editor.updatePaperFrame(in: scroll, refreshPageCount: false)
            durations.append(milliseconds(start.duration(to: clock.now)))
        }
    }
    let sorted = durations.sorted()
    let beforeRefresh = clock.now
    editor.updatePaperFrame(in: scroll)
    let refreshMS = milliseconds(beforeRefresh.duration(to: clock.now))
    print("Benchmark edición TextKit + JSON, \(editor.pageCount) páginas: mediana \(sorted[10]) ms; p95 \(sorted[19]) ms; recuento diferido \(refreshMS) ms.")
    print("Medianas parciales: inserción \(inserts.sorted()[10]) ms; actualización de biblioteca \(saves.sorted()[10]) ms.")
    #expect(store.flushEdits())
    #expect(try WritingLibrary.read(from: storeURL).activeDocuments.first?.markdown == editor.string)
}

@Test @MainActor func editorCommitsAccentsWithoutSavingMarkedText() throws {
    var surface = MarkdownSurface(text: "", editable: true, taggable: false, options: EditorOptions(),
        reveal: nil, onEdit: { _, _, _ in }, onSelect: { _ in }, fragmentAction: { _, _ in })
    let storage = NSTextStorage()
    let manager = NSLayoutManager()
    storage.addLayoutManager(manager)
    let container = NSTextContainer(size: NSSize(width: 400, height: 1000))
    manager.addTextContainer(container)
    let editor = MarkdownSurface.Editor(frame: NSRect(x: 0, y: 0, width: 400, height: 400), textContainer: container)
    editor.storage = storage
    let coordinator = surface.makeCoordinator()
    editor.delegate = coordinator
    editor.setMarkedText("´", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
    #expect(editor.hasMarkedText())
    var edits: [String] = []
    surface.onEdit = { text, _, _ in edits.append(text) }
    coordinator.parent = surface
    coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
    #expect(edits.isEmpty)
    editor.insertText("á", replacementRange: editor.markedRange())
    coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
    #expect(editor.string == "á")
    #expect(edits.last == "á")
}

@Test @MainActor func paginatedEditorKeepsUndoAndSelectionAcrossPages() throws {
    let storage = NSTextStorage(string: String(repeating: "Línea de texto con acentos: áéíóú.\n", count: 1800), attributes: [.font: NSFont.systemFont(ofSize: 12)])
    let manager = NSLayoutManager()
    storage.addLayoutManager(manager)
    let container = NSTextContainer(size: NSSize(width: 450, height: 1_000_000))
    manager.addTextContainer(container)
    let flow = PageFlow()
    flow.layout = WritingPageLayout()
    manager.delegate = flow
    let editor = MarkdownSurface.Editor(frame: NSRect(x: 0, y: 0, width: 600, height: 600), textContainer: container)
    editor.storage = storage
    editor.allowsUndo = true
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = editor
    window.makeFirstResponder(editor)
    manager.ensureLayout(for: container)
    #expect(manager.usedRect(for: container).height > WritingPageLayout().paperSize.height * 20)
    let original = editor.string
    let position = original.utf16.count / 2
    editor.setSelectedRange(NSRange(location: position, length: 0))
    editor.insertText("Árbol", replacementRange: editor.selectedRange())
    #expect(editor.selectedRange().location == position + 5)
    #expect(editor.string.utf16.count == original.utf16.count + 5)
    editor.undoManager?.undo()
    #expect(editor.string == original)
    window.contentView = nil
}

/// Cuenta las líneas de cada párrafo `p{i}w{k}` en cada página del PDF compuesto.
@MainActor private func paragraphLines(in pdf: PDFDocument) -> [Int: [(page: Int, lines: Int)]] {
    var result: [Int: [(page: Int, lines: Int)]] = [:]
    for page in 0..<pdf.pageCount {
        for line in (pdf.page(at: page)?.string ?? "").split(whereSeparator: \.isNewline) {
            let ids = Set(line.split(separator: " ").compactMap { token -> Int? in
                guard token.hasPrefix("p"), let marker = token.firstIndex(of: "w") else { return nil }
                return Int(token[token.index(after: token.startIndex)..<marker])
            })
            for id in ids {
                if var parts = result[id], parts.last?.page == page {
                    parts[parts.count - 1].lines += 1
                    result[id] = parts
                } else {
                    result[id, default: []].append((page, 1))
                }
            }
        }
    }
    return result
}

@Test @MainActor func paragraphsNeverLeaveASingleLineAtEitherPageEdge() throws {
    for words in [35, 45, 60] {
        for lead in 0..<45 {
            var source = (0..<lead).map { "filler\($0)" }.joined(separator: "\n\n") + (lead > 0 ? "\n\n" : "")
            for index in 0..<12 { source += (0..<words).map { "p\(index)w\($0)" }.joined(separator: " ") + "\n\n" }
            let pages = try #require(MarkdownPagination.render(input(source)))
            let pdf = try #require(PDFDocument(data: pages.data))
            for (id, parts) in paragraphLines(in: pdf) where parts.count > 1 {
                #expect(parts.allSatisfy { $0.lines >= 2 }, "p\(id) con \(words) palabras y \(lead) párrafos previos: \(parts.map(\.lines))")
            }
        }
    }
}

@Test @MainActor func aHeadingIsNeverLeftAloneAtTheEndOfAPage() throws {
    for lead in 0..<60 {
        var source = (0..<lead).map { "filler\($0)" }.joined(separator: "\n\n") + "\n\n"
        for index in 0..<6 {
            source += "## Titulo\(index)\n\n" + (0..<40).map { "p\(index)w\($0)" }.joined(separator: " ") + "\n\n"
        }
        let pages = try #require(MarkdownPagination.render(input(source)))
        let pdf = try #require(PDFDocument(data: pages.data))
        #expect(pages.starts.count == pdf.pageCount)
        var text = ""
        for page in 0..<pdf.pageCount {
            let body = (pdf.page(at: page)?.string ?? "").split(whereSeparator: \.isNewline).dropLast()
            text += body.joined(separator: "\n") + "\n"
            if page < pdf.pageCount - 1 {
                #expect(body.last?.hasPrefix("Titulo") != true, "Título solo al final de la página \(page) con \(lead) párrafos previos")
            }
        }
        for index in 0..<6 { #expect(text.contains("Titulo\(index)") && text.contains("p\(index)w39")) }
    }
}
