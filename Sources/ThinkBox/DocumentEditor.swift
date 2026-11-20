import AppKit
import SwiftUI
import WritingLibrary

struct JumpRequest: Equatable {
    let id = UUID()
    let destination: ItemDestination
}

struct DocumentEditor: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var scheme
    var store: LibraryStore
    var document: WritingDocument
    var openDocument: (ItemDestination) -> Void
    var openTag: ((String) -> Void)?
    var onTrashChange: () -> Void
    var focusTitle: Bool
    var jump: JumpRequest?
    var showInspector: ((InspectorSection) -> Void)?

    @FocusState private var titleFocused: Bool
    @ViewState private var showingDetails = false
    @ViewState private var showingLinks = false
    @ViewState private var selectedText = NSRange(location: 0, length: 0)
    @ViewState private var reveal: TextReveal?
    @ViewState private var tagFragment: DocumentFragment?
    @ViewState private var showExtractedText = false

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
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Sin título", text: binding(\.title))
                        .font(settings.font(13, bold: true))
                        .textFieldStyle(.plain)
                        .focused($titleFocused)
                        .accessibilityLabel("Título del texto")
                        .disabled(document.trashedAt != nil)
                        .foregroundStyle(settings.editor.customColors ? settings.editor.ink.color : .primary)
                        .padding(.leading, 5)
                    Rectangle().fill(palette.border).frame(height: 1)
                    MarkdownSurface(text: document.markdown, editable: document.trashedAt == nil,
                                    taggable: document.trashedAt == nil, options: settings.editor, reveal: reveal,
                                    onEdit: { text, range, length in
                        store.update(document.id) { $0.editMarkdown(text, replaced: range, replacementLength: length) }
                    }, onSelect: { selectedText = $0 }, fragmentAction: markdownFragment)
                }
                .padding(.horizontal, 32)
                .padding(.top, 38)
                .frame(maxWidth: CGFloat(settings.editor.columnWidth), maxHeight: .infinity)
                .frame(maxWidth: .infinity)
                .background(settings.editor.customColors ? settings.editor.paper.color : palette.workspace)
            }

            Rectangle().fill(palette.border).frame(height: 1)
            documentBar
        }
        .onAppear { titleFocused = focusTitle }
        .onChange(of: jump, initial: true) {
            guard let target = jump?.destination.fragmentID,
                  let fragment = (document.fragments ?? []).first(where: { $0.id == target }),
                  case .text(let anchor) = fragment.location else { return }
            if let range = anchor.resolve(in: selectableText) {
                if document.attachment?.kind == .preview { showExtractedText = true }
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

    @ViewBuilder private func attachmentContent(_ asset: DocumentAttachment) -> some View {
        switch asset.kind {
        case .canvas:
            CanvasEditor(store: store, document: document)
        case .pdf:
            if let url = store.attachmentURL(for: document) {
                PDFReader(store: store, item: document, url: url, jump: jump, fragmentAction: handleFragment)
            }
        case .preview:
            if let url = store.attachmentURL(for: document) {
                VStack(spacing: 0) {
                    if let extracted = asset.searchText, !extracted.isEmpty {
                        Picker("Vista", selection: $showExtractedText) {
                            Text("Vista previa").tag(false)
                            Text("Texto").tag(true)
                        }.pickerStyle(.segmented).labelsHidden().frame(width: 230).padding(8)
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
                Button("Etiquetas", systemImage: "tag") {
                    if let showInspector { showInspector(.details) } else { showingDetails.toggle() }
                }
                    .popover(isPresented: $showingDetails, arrowEdge: .top) {
                        DocumentDetails(store: store, document: document, openTag: openTag.map { reveal in
                            { tag in showingDetails = false; reveal(tag) }
                        }).padding(16).frame(width: 350)
                    }
                Button("Enlaces", systemImage: "link") {
                    if let showInspector { showInspector(.links) } else { showingLinks.toggle() }
                }
                .popover(isPresented: $showingLinks, arrowEdge: .top) {
                    DocumentLinks(store: store, document: document) { destination in
                        showingLinks = false
                        openDocument(destination)
                    }.padding(15).frame(width: 280)
                }
                if selectedText.length > 0 && (document.attachment == nil || showExtractedText) {
                    Menu("Selección", systemImage: "text.cursor") {
                        Button("Etiquetar fragmento…") { markdownFragment(selectedText, copy: false) }
                        Button("Copiar enlace al fragmento") { markdownFragment(selectedText, copy: true) }
                    }.menuStyle(.borderlessButton).fixedSize()
                }
            } else {
                Button("Restaurar", systemImage: "arrow.uturn.backward") { setTrashed(false) }
            }
            Spacer()
            if let asset = document.attachment {
                Text(asset.kind.label).foregroundStyle(.secondary)
            } else if settings.editor.showWordCount {
                let wordCount = document.markdown.split(whereSeparator: \.isWhitespace).count
                Text(wordCount == 1 ? "1 palabra" : "\(wordCount) palabras").foregroundStyle(.secondary)
            }
            Menu {
                Button("Exportar…", systemImage: "square.and.arrow.up") { store.exportDocument(document) }
                if document.trashedAt == nil {
                    Divider()
                    Button("Mover a la papelera", systemImage: "trash") { setTrashed(true) }
                }
            } label: {
                ChromeSymbol(name: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Acciones del texto")
        }
        .font(settings.font(-1))
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
    }

    private func setTrashed(_ trashed: Bool) {
        store.update(document.id) { $0.trashedAt = trashed ? .now : nil }
        if (store.document(document.id)?.trashedAt != nil) == trashed { onTrashChange() }
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
            Button("Copiar enlace Markdown", systemImage: "doc.on.doc") {
                copyText(document.markdownLink)
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
                Text("Proyectos").font(settings.font(-1, bold: true)).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(store.library.projects) { project in
                            Toggle(project.name, isOn: Binding(
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
