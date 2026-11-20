import Foundation
import Testing
import WritingLibrary

@Test func hierarchicalTagsFindTheFragmentWithoutCreatingAnotherDocument() throws {
    let text = "Una línea.\n\n🌊 La orilla estaba vacía.\n\nOtra línea."
    let range = (text as NSString).range(of: "🌊 La orilla estaba vacía.")
    let anchor = try #require(TextAnchor(text: text, range: range))
    let fragment = DocumentFragment(quote: anchor.quote, location: .text(anchor), tags: ["Trabajo de campo/Litoral", "Citas"])
    var document = WritingDocument(title: "Cuaderno", markdown: text)
    document.fragments = [fragment]
    var library = WritingLibrary()
    library.documents = [document]

    let destination = ItemDestination(document.id, fragmentID: fragment.id)
    #expect(library.results(in: .tag("Trabajo de campo")).map(\.id) == [destination])
    #expect(library.results(in: .all, matching: #"tag:"Trabajo de campo" tag:Citas orilla"#).map(\.id) == [destination])
    #expect(library.documents(in: .all).count == 1)
    #expect(ItemDestination(url: destination.url) == destination)
    #expect(WritingDocument(markdown: destination.url.absoluteString).linkTargets == [destination])

    library.replaceTag("Trabajo de campo", with: "Investigación")
    #expect(library.results(in: .tag("Investigación/Litoral")).map(\.id) == [destination])
    #expect(library.results(in: .tag("Trabajo de campo")).isEmpty)
}

@Test func textSelectionTracksEditsAndDoesNotJumpToAnotherCopy() throws {
    let quote = "el océano"
    let source = "A \(quote) 1\nB \(quote) 2"
    let range = (source as NSString).range(of: quote, options: .backwards)
    let anchor = try #require(TextAnchor(text: source, range: range))
    let prefix = "🙂 Inicio\n"
    let updated = prefix + source
    var document = WritingDocument(markdown: source)
    document.fragments = [DocumentFragment(quote: quote, location: .text(anchor))]
    document.editMarkdown(updated, replaced: NSRange(location: 0, length: 0), replacementLength: prefix.utf16.count)
    let moved = try #require(document.fragments?.first?.location)
    guard case .text(let adjusted) = moved else { Issue.record("Expected text anchor"); return }
    let newRange = try #require(adjusted.resolve(in: updated))
    #expect(newRange.location == range.location + prefix.utf16.count)
    let removed = (updated as NSString).replacingCharacters(in: newRange, with: "")
    document.editMarkdown(removed, replaced: newRange, replacementLength: 0)
    if case .text(let invalid) = document.fragments?.first?.location { #expect(invalid.resolve(in: removed) == nil) }
    else { Issue.record("Expected text anchor") }
}

@Test func automaticTagsFollowProjectMembershipAndHashtagChanges() {
    var project = Project(name: "Crónicas")
    project.tags = ["Publicaciones/Ensayo"]
    var library = WritingLibrary()
    library.projects = [project]
    var options = TagSettings()
    options.inheritProjectTags = true
    options.projectNames = true
    options.hashtags = true
    library.tagSettings = options
    let document = WritingDocument(markdown: "#cabecera\nTexto #inline\n#Tema/Olivos #Tierra", projectIDs: [project.id])
    library.documents = [document]
    #expect(library.effectiveTags(of: document) == ["Crónicas", "Publicaciones/Ensayo", "cabecera", "Tema/Olivos", "Tierra"])
    #expect(library.results(in: .tag("Publicaciones")).count == 1)
    library.projects[0].excludedFromTagging = true
    #expect(library.results(in: .tag("Publicaciones")).isEmpty)
    library.documents[0].markdown = "Sin etiquetas"
    #expect(library.results(in: .tag("Tema")).isEmpty)
}

@Test func readsTheOriginalLibraryWithoutDiscardingNotesOrTags() throws {
    let sample = Data(#"""
    {"formatVersion":1,"projects":[],"savedSearches":[],"documents":[
       {"id":"68F27B7D-AC28-4A5F-9F2F-E5AB0FBADC30","title":"Legado","markdown":"Texto de la biblioteca anterior",
        "stage":"draft","projectIDs":[],"tags":["Original"],"modifiedAt":0}
    ]}
    """#.utf8)
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try sample.write(to: url)
    let library = try WritingLibrary.read(from: url)
    #expect(library.formatVersion == 2)
    #expect(library.documents(in: .tag("Original")).first?.markdown == "Texto de la biblioteca anterior")
    #expect(try Data(contentsOf: url) == sample)
}
