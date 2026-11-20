import AppKit
import Observation
import WritingLibrary

@MainActor @Observable
final class LibraryStore {
    private(set) var library = WritingLibrary()
    private(set) var openError: String?
    var actionError: String?
    let fileURL: URL

    init() {
        if let path = ProcessInfo.processInfo.environment["THINKBOX_LIBRARY_PATH"], !path.isEmpty {
            fileURL = URL(fileURLWithPath: path)
        } else {
            fileURL = URL.applicationSupportDirectory.appending(path: "Think Box/Biblioteca.json")
        }
        do {
            library = try WritingLibrary.read(from: fileURL)
        } catch {
            openError = error.localizedDescription
        }
    }

    @discardableResult
    func commit(_ change: (inout WritingLibrary) -> Void) -> Bool {
        guard openError == nil else { return false }
        var updated = library
        change(&updated)
        guard updated != library else { return true }
        do {
            try updated.write(to: fileURL)
            library = updated
            return true
        } catch {
            actionError = "No se pudieron guardar los cambios. \(error.localizedDescription)"
            return false
        }
    }

    func createDocument(in scope: LibraryScope) -> UUID? {
        let projectIDs: Set<UUID>
        if case .project(let id) = scope { projectIDs = [id] } else { projectIDs = [] }
        let document = WritingDocument(title: "", projectIDs: projectIDs)
        return commit { $0.documents.append(document) } ? document.id : nil
    }

    func createProject(_ name: String) -> UUID? {
        let project = Project(name: name)
        return commit { $0.projects.append(project) } ? project.id : nil
    }

    func createSavedSearch(name: String, query: String) -> UUID? {
        let search = SavedSearch(name: name, query: query)
        return commit { $0.savedSearches.append(search) } ? search.id : nil
    }

    func document(_ id: UUID) -> WritingDocument? {
        library.documents.first { $0.id == id }
    }

    @discardableResult
    func update(_ id: UUID, _ change: (inout WritingDocument) -> Void) -> Bool {
        guard let index = library.documents.firstIndex(where: { $0.id == id }) else { return false }
        return commit {
            let original = $0.documents[index]
            change(&$0.documents[index])
            if original != $0.documents[index] { $0.documents[index].modifiedAt = .now }
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
        if copyLink { copyText(ItemDestination(documentID, fragmentID: saved.id).url.absoluteString) }
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
