import AppKit
import Observation
import WritingLibrary

@MainActor @Observable
final class LibraryStore {
    @ObservationIgnored private var storedLibrary = WritingLibrary()
    private(set) var library: WritingLibrary {
        get {
            access(keyPath: \.library)
            return storedLibrary
        }
        set {
            withMutation(keyPath: \.library) { storedLibrary = newValue }
        }
    }
    private(set) var openError: String?
    var actionError: String?
    let fileURL: URL
    let databaseID: UUID?
    private let writeQueue = DispatchQueue(label: "ThinkBox.library-write", qos: .utility)
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var persistedRevision = 0
    @ObservationIgnored private var scheduledWrite: Task<Void, Never>?

    static var defaultFileURL: URL {
        if let path = ProcessInfo.processInfo.environment["THINKBOX_LIBRARY_PATH"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        } else {
            return URL.applicationSupportDirectory.appending(path: "Think Box/Biblioteca.json")
        }
    }

    init(fileURL: URL = LibraryStore.defaultFileURL, databaseID: UUID? = nil, requiresExistingFile: Bool = false) {
        self.fileURL = fileURL
        self.databaseID = databaseID
        do {
            library = try WritingLibrary.read(from: fileURL, requiresExistingFile: requiresExistingFile)
            migrateRichTextAttachments()
        } catch {
            openError = error.localizedDescription
        }
    }

    @discardableResult
    func commit(deferWrite: Bool = false, _ change: (inout WritingLibrary) -> Void) -> Bool {
        guard openError == nil else { return false }
        var updated = library
        change(&updated)
        if deferWrite {
            // The editor sends committed changes, so skip whole-document equality checks here.
            revision += 1
            library = updated
            scheduleWrite()
            return true
        }
        guard updated != library else { return true }
        let snapshot = updated
        do {
            try writeQueue.sync { try snapshot.write(to: fileURL) }
            revision += 1
            persistedRevision = revision
            library = snapshot
            return true
        } catch {
            actionError = "No se pudieron guardar los cambios. \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func flushEdits() -> Bool {
        guard persistedRevision < revision else { return true }
        let snapshot = library
        do {
            try writeQueue.sync { try snapshot.write(to: fileURL) }
            persistedRevision = revision
            return true
        } catch {
            actionError = "No se pudieron guardar los cambios. \(error.localizedDescription)"
            return false
        }
    }

    private func scheduleWrite() {
        guard scheduledWrite == nil else { return }
        scheduledWrite = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            await self?.writeEdits()
        }
    }

    private func writeEdits() async {
        let version = revision
        defer {
            scheduledWrite = nil
            if version < revision && persistedRevision < revision { scheduleWrite() }
        }
        guard persistedRevision < version else { return }
        let snapshot = library
        let destination = fileURL
        let error: String? = await withCheckedContinuation { result in
            writeQueue.async {
                do {
                    try snapshot.write(to: destination)
                    result.resume(returning: nil)
                } catch {
                    result.resume(returning: error.localizedDescription)
                }
            }
        }
        if let error {
            if persistedRevision < version { actionError = "No se pudieron guardar los cambios. \(error)" }
        } else {
            persistedRevision = max(persistedRevision, version)
        }
    }

    func createDocument(in scope: LibraryScope) -> UUID? {
        let projectIDs: Set<UUID>
        if case .project(let id) = scope { projectIDs = [id] } else { projectIDs = [] }
        let document = WritingDocument(title: "", projectIDs: projectIDs)
        return commit { $0.documents.append(document) } ? document.id : nil
    }

    func createProject(_ name: String, parent: UUID? = nil) -> UUID? {
        let project = Project(name: name, parentID: parent)
        return commit { $0.projects.append(project) } ? project.id : nil
    }

    func createSavedSearch(name: String, query: String) -> UUID? {
        let search = SavedSearch(name: name, query: query)
        return commit { $0.savedSearches.append(search) } ? search.id : nil
    }

    func document(_ id: UUID) -> WritingDocument? {
        library.documents.first { $0.id == id }
    }

    func destination(_ id: UUID, fragmentID: UUID? = nil) -> ItemDestination {
        ItemDestination(id, fragmentID: fragmentID, databaseID: databaseID)
    }

    @discardableResult
    func setTrashed(_ id: UUID, _ trashed: Bool) -> Bool {
        guard let document = document(id), (document.trashedAt != nil) != trashed else { return false }
        return update(id) { $0.trashedAt = trashed ? .now : nil }
    }

    @discardableResult
    func update(_ id: UUID, touch: Bool = true, deferWrite: Bool = false,
                _ change: (inout WritingDocument) -> Void) -> Bool {
        guard let index = library.documents.firstIndex(where: { $0.id == id }) else { return false }
        return commit(deferWrite: deferWrite) {
            let original = $0.documents[index]
            change(&$0.documents[index])
            if touch && (deferWrite || original != $0.documents[index]) { $0.documents[index].modifiedAt = .now }
        }
    }

    func saveFragment(documentID: UUID, fragment: DocumentFragment, tags: [String], copyLink: Bool) {
        guard let document = document(documentID), document.trashedAt == nil else { return }
        var saved = (document.fragments ?? []).first(where: { $0.location == fragment.location }) ?? fragment
        saved.tags = TagPath.unique(saved.tags + tags)
        guard update(documentID, { document in
            var fragments = document.fragments ?? []
            if let index = fragments.firstIndex(where: { $0.id == saved.id }) {
                fragments[index] = saved
            } else {
                fragments.append(saved)
            }
            document.fragments = fragments
        }) else { return }
        if copyLink { copyText(destination(documentID, fragmentID: saved.id).url.absoluteString) }
    }

    func setTags(_ tags: [String], at destination: ItemDestination) {
        update(destination.documentID) { document in
            if let fragmentID = destination.fragmentID {
                guard let index = document.fragments?.firstIndex(where: { $0.id == fragmentID }) else { return }
                document.fragments?[index].tags = tags
            } else {
                document.tags = tags
            }
        }
    }
}

@MainActor
func copyText(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
