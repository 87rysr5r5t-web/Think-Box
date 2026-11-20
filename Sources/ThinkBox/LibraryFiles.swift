import AppKit
import PDFKit
import UniformTypeIdentifiers
import WritingLibrary

extension LibraryStore {
    private var filesFolder: URL { fileURL.deletingPathExtension().appendingPathExtension("assets") }

    private func assetFolder(_ id: UUID) -> URL {
        filesFolder.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    func attachmentURL(for document: WritingDocument) -> URL? {
        guard let name = document.attachment?.filename, name == (name as NSString).lastPathComponent,
              name != ".", name != "..", !name.isEmpty else { return nil }
        return assetFolder(document.id).appending(path: name, directoryHint: .notDirectory)
    }

    func importDocuments(in scope: LibraryScope) -> UUID? {
        let panel = NSOpenPanel()
        panel.title = "Importar archivos"
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return nil }
        let projects: Set<UUID>
        if case .project(let id) = scope { projects = [id] } else { projects = [] }
        var copiedAssets: [URL] = []
        var imported: [WritingDocument] = []
        do {
            for url in panel.urls {
                var document = WritingDocument(title: url.deletingPathExtension().lastPathComponent, projectIDs: projects)
                let values = try url.resourceValues(forKeys: [.tagNamesKey, .contentTypeKey, .isDirectoryKey, .isPackageKey])
                if values.isDirectory == true && values.isPackage != true { throw FileIssue.unsupported }
                if library.tagging.finderTags { document.tags = TagPath.unique(values.tagNames ?? []) }
                let ext = url.pathExtension.lowercased()
                switch ext {
                case "md", "markdown", "txt", "text":
                    var encoding = String.Encoding.utf8
                    document.markdown = try String(contentsOf: url, usedEncoding: &encoding)
                case "canvas":
                    let data = try Data(contentsOf: url)
                    let board = try CanvasBoard(data: data)
                    var asset = DocumentAttachment(filename: url.lastPathComponent, kind: .canvas,
                        sourceFolder: canvasRoot(for: url), searchText: board.searchText)
                    asset.canvasData = data
                    document.attachment = asset
                default:
                    let isPDF = ext == "pdf" || values.contentType?.conforms(to: .pdf) == true
                    let pdf = isPDF ? PDFDocument(url: url) : nil
                    if isPDF && pdf == nil { throw FileIssue.invalidPDF }
                    let body = isPDF ? pdf?.string : previewText(at: url, type: values.contentType)
                    document.attachment = DocumentAttachment(filename: url.lastPathComponent,
                        kind: isPDF ? .pdf : .preview, searchText: body)
                    if library.tagging.pdfKeywords, let keywords = pdf?.documentAttributes?[PDFDocumentAttribute.keywordsAttribute] {
                        let values = (keywords as? [String]) ?? (keywords as? String).map(TagPath.list) ?? []
                        document.tags = TagPath.unique(document.tags + values)
                    }
                    if let destination = attachmentURL(for: document) {
                        let folder = assetFolder(document.id)
                        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        copiedAssets.append(folder)
                        try FileManager.default.copyItem(at: url.resolvingSymlinksInPath(), to: destination)
                    }
                }
                imported.append(document)
            }
            if commit({ $0.documents.append(contentsOf: imported) }) { return imported.first?.id }
        } catch {
            actionError = "No se pudo importar la selección. \(error.localizedDescription)"
        }
        for folder in copiedAssets { try? FileManager.default.removeItem(at: folder) }
        return nil
    }

    private func previewText(at url: URL, type: UTType?) -> String? {
        let documentType: NSAttributedString.DocumentType?
        switch url.pathExtension.lowercased() {
        case "rtf": documentType = .rtf
        case "rtfd": documentType = .rtfd
        case "doc": documentType = .docFormat
        case "docx": documentType = .officeOpenXML
        default: documentType = nil
        }
        if let documentType {
            return try? NSAttributedString(url: url, options: [.documentType: documentType], documentAttributes: nil).string
        }
        if type?.conforms(to: .plainText) == true || type?.conforms(to: .json) == true {
            var encoding = String.Encoding.utf8
            return try? String(contentsOf: url, usedEncoding: &encoding)
        }
        return nil
    }

    func createCanvas(in scope: LibraryScope) -> UUID? {
        let projects: Set<UUID>
        if case .project(let id) = scope { projects = [id] } else { projects = [] }
        var document = WritingDocument(title: "Lienzo sin título", projectIDs: projects)
        document.attachment = DocumentAttachment(filename: "Lienzo.canvas", kind: .canvas)
        document.attachment?.canvasData = Data("{}".utf8)
        return commit { $0.documents.append(document) } ? document.id : nil
    }

    func saveCanvas(_ board: CanvasBoard, documentID: UUID) -> Bool {
        do {
            let data = try board.data()
            return update(documentID) {
                $0.attachment?.canvasData = data
                $0.attachment?.searchText = board.searchText
            }
        } catch {
            actionError = error.localizedDescription
            return false
        }
    }

    private func canvasRoot(for url: URL) -> URL {
        let folder = url.deletingLastPathComponent()
        var ancestor = folder
        while !ancestor.path.isEmpty && ancestor.path != "/" {
            if FileManager.default.fileExists(atPath: ancestor.appending(path: ".obsidian", directoryHint: .isDirectory).path) {
                return ancestor
            }
            ancestor.deleteLastPathComponent()
        }
        return folder
    }

    func canvasFile(_ path: String, in folder: URL?) -> URL? {
        guard let folder, !path.isEmpty, !(path as NSString).isAbsolutePath else { return nil }
        let root = folder.resolvingSymlinksInPath().standardizedFileURL
        let url = root.appending(path: path).resolvingSymlinksInPath().standardizedFileURL
        guard url.path.hasPrefix(root.path == "/" ? "/" : root.path + "/"),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    func exportDocument(_ document: WritingDocument) {
        let panel = NSSavePanel()
        panel.title = "Exportar archivo"
        let ext = document.attachment.map { ($0.filename as NSString).pathExtension } ?? "md"
        if let type = UTType(filenameExtension: ext) { panel.allowedContentTypes = [type] }
        let name = document.displayTitle.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = ext.isEmpty ? name : "\(name).\(ext)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if let data = document.attachment?.canvasData {
                try data.write(to: url, options: .atomic)
            } else if let source = attachmentURL(for: document) {
                if try source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                    if FileManager.default.fileExists(atPath: url.path) {
                        let folder = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                                appropriateFor: url, create: true)
                        defer { try? FileManager.default.removeItem(at: folder) }
                        let copy = folder.appending(path: url.lastPathComponent)
                        try FileManager.default.copyItem(at: source, to: copy)
                        _ = try FileManager.default.replaceItemAt(url, withItemAt: copy)
                    } else {
                        try FileManager.default.copyItem(at: source, to: url)
                    }
                } else {
                    try Data(contentsOf: source, options: .mappedIfSafe).write(to: url, options: .atomic)
                }
            } else {
                try document.markdown.write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            actionError = "Error al exportar. \(error.localizedDescription)"
            return
        }
        if library.tagging.finderTags, !document.tags.isEmpty {
            let tags = document.tags
            Task { @MainActor in
                do {
                    try await Task.detached(priority: .utility) {
                        try (url as NSURL).setResourceValue(tags, forKey: .tagNamesKey)
                    }.value
                } catch {
                    actionError = "Se exportó el archivo. Finder no pudo guardar sus etiquetas. \(error.localizedDescription)"
                }
            }
        }
    }
}

private enum FileIssue: LocalizedError {
    case unsupported, invalidPDF
    var errorDescription: String? {
        switch self {
        case .unsupported: "Selecciona archivos individuales."
        case .invalidPDF: "Uno de los PDF no se pudo abrir."
        }
    }
}
