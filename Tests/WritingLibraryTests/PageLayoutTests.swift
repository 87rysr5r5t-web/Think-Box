import Foundation
import Testing
@testable import WritingLibrary

@Test func pagePreferencesSurviveReopeningAnExistingDocument() throws {
    let source = """
        {"id":"9B659B72-A04F-455C-A7CD-6E90F6EE35B0","title":"Nota","markdown":"Texto",
        "stage":"draft","modifiedAt":0,"tags":[],"projectIDs":[]}
        """
    var document = try JSONDecoder().decode(WritingDocument.self, from: Data(source.utf8))
    #expect(document.pageLayout == nil && document.pageViews == nil)
    var layout = WritingPageLayout()
    layout.paper = .a5
    layout.landscape = true
    layout.margins = .mirrored
    layout.firstNumber = 7
    layout.labels.footer = "{pagina} / {paginas}"
    document.pageLayout = layout
    var views = WritingPageViews()
    views.mode = .split
    views.editor = true
    views.preview = false
    document.pageViews = views
    let saved = try JSONEncoder().encode(document)
    #expect(try JSONDecoder().decode(WritingDocument.self, from: saved) == document)
    #expect(layout.paperSize.width > layout.paperSize.height)
    #expect(layout.contentRect(page: 0).minX > layout.contentRect(page: 1).minX)
    #expect(layout.contentRect(page: 0).size == layout.contentRect(page: 1).size)
    #expect(layout.pageNumber(2) == 9)
}
