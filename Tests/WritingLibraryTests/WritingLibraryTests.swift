import Foundation
import Testing
import WritingLibrary

@Test func oneDocumentCanAppearInTwoProjects() throws {
    let first = Project(name: "Ensayo")
    let second = Project(name: "Cuaderno")
    var library = WritingLibrary()
    library.projects = [first, second]
    library.documents = [WritingDocument(title: "Una idea", projectIDs: [first.id, second.id])]
    let originalID = try #require(library.documents.first?.id)

    library.documents[0].markdown = "Un párrafo nuevo."
    #expect(library.documents(in: .all).count == 1)
    for project in library.projects {
        let document = try #require(library.documents(in: .project(project.id)).first)
        #expect(document.id == originalID)
        #expect(document.markdown == "Un párrafo nuevo.")
    }

    #expect(library.documents(in: .inbox).isEmpty)
    library.documents[0].projectIDs.removeAll()
    #expect(library.documents(in: .inbox).map(\.id) == [originalID])
}

@Test func savedSearchReflectsEditsAndExcludesTrash() {
    let search = SavedSearch(name: "Voces del mar", query: "oceano entrevista")
    var document = WritingDocument(title: "El océano")
    document.tags = ["Entrevista"]
    var library = WritingLibrary()
    library.documents = [document]
    library.savedSearches = [search]

    #expect(library.documents(in: .savedSearch(search.id)).count == 1)
    #expect(library.documents(in: .savedSearch(search.id), matching: "montaña").isEmpty)
    library.documents[0].tags = []
    #expect(library.documents(in: .savedSearch(search.id)).isEmpty)
    library.documents[0].markdown = "Una entrevista pendiente."
    #expect(library.documents(in: .savedSearch(search.id)).count == 1)
    library.documents[0].trashedAt = .now
    #expect(library.documents(in: .savedSearch(search.id)).isEmpty)
    #expect(library.documents(in: .trash, matching: "océano").map(\.id) == [document.id])
}

@Test func documentIdentityAndMarkdownSurviveRenameAndReopen() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let url = directory.appending(path: "library.json")
    defer { try? FileManager.default.removeItem(at: directory) }
    var library = try WritingLibrary.read(from: url)
    var target = WritingDocument(title: "Notas [I]")
    let source = WritingDocument(title: "Capítulo", markdown: "# Investigación\n\n\(target.markdownLink)\n")
    #expect(source.markdown.contains("\\[I\\]"))
    library.documents = [source, target]
    try library.write(to: url)

    target.title = "Notas corregidas"
    library.documents[1] = target
    try library.write(to: url)
    let reopened = try WritingLibrary.read(from: url)
    #expect(reopened == library)
    #expect(reopened.documents[0].linkedDocumentIDs == [target.id])
    #expect(WritingDocument.documentID(for: target.url) == target.id)
}

@Test func malformedLibraryIsReported() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("{invalid JSON".utf8).write(to: url)
    #expect(throws: DecodingError.self) { try WritingLibrary.read(from: url) }
}
