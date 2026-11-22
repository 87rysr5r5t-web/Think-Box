import AppKit
import Observation
import UniformTypeIdentifiers
import WritingLibrary

struct LibraryDatabase: Codable, Identifiable, Equatable {
    let id: UUID
    let fileURL: URL

    var name: String { fileURL.deletingPathExtension().lastPathComponent }
}

@MainActor @Observable
final class LibraryDatabases {
    static let defaultID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let defaults: UserDefaults
    private let catalogKey: String
    private(set) var entries: [LibraryDatabase]
    @ObservationIgnored private var stores: [UUID: LibraryStore] = [:]
    private var storeGeneration = 0
    var activeID = defaultID
    var actionError: String?

    init(defaultURL: URL = LibraryStore.defaultFileURL, defaults: UserDefaults? = nil) {
        let preferences = defaults ?? .standard
        self.defaults = preferences
        let main = LibraryDatabase(id: Self.defaultID, fileURL: Self.canonical(defaultURL))
        // An explicitly supplied library path should only see its own database catalog.
        if main.fileURL != Self.canonical(URL.applicationSupportDirectory.appending(path: "Think Box/Biblioteca.json")) {
            catalogKey = "library.databases." + main.fileURL.path
        } else {
            catalogKey = "library.databases"
        }
        let saved = preferences.data(forKey: catalogKey)
            .flatMap { try? JSONDecoder().decode([LibraryDatabase].self, from: $0) } ?? []
        entries = [main] + saved.filter { $0.id != main.id && $0.fileURL != main.fileURL }
    }

    var activeStore: LibraryStore { store(for: activeID) ?? store(for: Self.defaultID)! }

    func flushEdits() -> Bool {
        var saved = true
        for store in stores.values {
            if !store.flushEdits() { saved = false }
        }
        return saved
    }

    func entry(for id: UUID?) -> LibraryDatabase? {
        entries.first { $0.id == (id ?? Self.defaultID) }
    }

    func store(for id: UUID?) -> LibraryStore? {
        guard let database = entry(for: id) else { return nil }
        _ = storeGeneration
        if let cached = stores[database.id] { return cached }
        let store = LibraryStore(fileURL: database.fileURL, databaseID: database.id,
                                 requiresExistingFile: database.id != Self.defaultID)
        stores[database.id] = store
        return store
    }

    func resolve(_ destination: ItemDestination, preferred: UUID?) -> LibraryStore? {
        if let id = destination.databaseID {
            return store(for: id).flatMap { $0.document(destination.documentID) == nil ? nil : $0 }
        }
        let primary = preferred ?? Self.defaultID
        let ids = [primary] + entries.map(\.id).filter { $0 != primary }
        for id in ids {
            if let store = store(for: id), store.document(destination.documentID) != nil { return store }
        }
        return nil
    }

    func chooseDatabase(creating: Bool) -> UUID? {
        let panel: NSSavePanel
        if creating {
            panel = NSSavePanel()
            panel.title = "Nueva base de datos"
            panel.nameFieldStringValue = "Nueva base.json"
            panel.canCreateDirectories = true
        } else {
            panel = NSOpenPanel()
            panel.title = "Abrir base de datos"
            panel.prompt = "Abrir"
        }
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            return try register(url, creating: creating)
        } catch {
            actionError = error.localizedDescription
            return nil
        }
    }

    func register(_ url: URL, creating: Bool = false) throws -> UUID {
        let url = Self.canonical(url)
        if creating {
            let data = try JSONEncoder().encode(WritingLibrary())
            try data.write(to: url, options: .withoutOverwriting)
        } else {
            // Opening a DB validates both the file and the schema before it joins the list.
            _ = try WritingLibrary.read(from: url, requiresExistingFile: true)
        }
        if let database = entries.first(where: { $0.fileURL == url }) {
            if stores[database.id]?.openError != nil {
                stores[database.id] = nil
                storeGeneration += 1
            }
            return database.id
        }
        let database = LibraryDatabase(id: UUID(), fileURL: url)
        let added = entries + [database]
        defaults.set(try JSONEncoder().encode(Array(added.dropFirst())), forKey: catalogKey)
        entries = added
        return database.id
    }

    private static func canonical(_ url: URL) -> URL { url.standardizedFileURL.resolvingSymlinksInPath() }
}
