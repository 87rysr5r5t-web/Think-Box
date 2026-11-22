import Foundation
import Testing
import WritingLibrary
@testable import ThinkBox

@Test @MainActor func databasesKeepExistingGroupAssignmentsAndIsolateTrash() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let suite = "ThinkBoxTest-\(UUID())"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let mainURL = folder.appending(path: "Biblioteca.json")
    let otherURL = folder.appending(path: "Investigación.json")
    var group = Project(name: "Archivo")
    group.tags = ["Fuentes"]
    let document = WritingDocument(title: "Original", markdown: "Texto principal", projectIDs: [group.id])
    var legacy = WritingLibrary()
    legacy.formatVersion = 1
    legacy.projects = [group]
    legacy.documents = [document]
    var tagging = TagSettings()
    tagging.inheritProjectTags = true
    legacy.tagSettings = tagging
    try legacy.write(to: mainURL)

    let catalog = LibraryDatabases(defaultURL: mainURL, defaults: preferences)
    let main = try #require(catalog.store(for: nil))
    let otherID = try catalog.register(otherURL, creating: true)
    let other = try #require(catalog.store(for: otherID))
    var copy = document
    copy.title = "Copia distinta"
    copy.projectIDs = []
    #expect(other.commit { $0.documents.append(copy) })
    #expect(try catalog.register(otherURL) == otherID)
    #expect(throws: (any Error).self) { try catalog.register(otherURL, creating: true) }
    #expect(main.library.documents(in: .project(group.id), matching: "tag:Fuentes") == [document])
    #expect(other.library.documents(in: .all, matching: "principal") == [copy])

    let qualified = other.destination(copy.id)
    #expect(ItemDestination(url: qualified.url) == qualified)
    #expect(catalog.resolve(qualified, preferred: main.databaseID) === other)
    #expect(catalog.resolve(ItemDestination(document.id), preferred: main.databaseID) === main)
    #expect(other.setTrashed(copy.id, true))
    #expect(other.library.documents(in: .trash).map(\.id) == [copy.id])
    #expect(main.library.documents(in: .trash).isEmpty)
    #expect(main.library.documents(in: .all).map(\.id) == [document.id])
    #expect(other.setTrashed(copy.id, false))
    #expect(try WritingLibrary.read(from: otherURL).activeDocuments.map(\.title) == ["Copia distinta"])

    let reopened = LibraryDatabases(defaultURL: mainURL, defaults: preferences)
    #expect(reopened.entry(for: otherID)?.name == "Investigación")
    #expect(reopened.resolve(qualified, preferred: nil)?.document(copy.id)?.title == copy.title)
}

@Test @MainActor func deferredEditsSurviveTrashAndOrderedWrites() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appending(path: "Prueba.json")
    let store = LibraryStore(fileURL: url)
    let id = try #require(store.createDocument(in: .all))
    #expect(store.update(id, deferWrite: true) { $0.markdown = "Versión anterior" })
    try await Task.sleep(for: .milliseconds(100))
    #expect(store.update(id, deferWrite: true) { $0.markdown = "Versión más reciente" })
    #expect(store.setTrashed(id, true))
    try await Task.sleep(for: .milliseconds(160))
    let saved = try #require(WritingLibrary.read(from: url).documents.first)
    #expect(saved.markdown == "Versión más reciente")
    #expect(saved.trashedAt != nil)
}
