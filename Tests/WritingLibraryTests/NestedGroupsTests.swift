import Foundation
import Testing
@testable import WritingLibrary

@Test func groupsNestAndReadAsATree() {
    var library = WritingLibrary()
    let thesis = Project(name: "Tesis")
    let chapters = Project(name: "Capítulos", parentID: thesis.id)
    let first = Project(name: "Uno", parentID: chapters.id)
    library.projects = [thesis, chapters, first, Project(name: "Lecturas")]

    let tree = library.groupTree
    #expect(tree.map(\.project.name) == ["Tesis", "Lecturas"])
    #expect(tree[0].children?.map(\.project.name) == ["Capítulos"])
    #expect(tree[0].children?[0].children?.map(\.project.name) == ["Uno"])
    #expect(library.groupPath(of: first.id) == "Tesis › Capítulos › Uno")
}

@Test func movingAGroupRefusesItsOwnDescendants() {
    var library = WritingLibrary()
    let parent = Project(name: "Padre")
    let child = Project(name: "Hijo", parentID: parent.id)
    library.projects = [parent, child]

    let intoChild = library.moveGroup(parent.id, into: child.id)
    let intoItself = library.moveGroup(parent.id, into: parent.id)
    let toTop = library.moveGroup(child.id, into: nil)
    #expect(!intoChild)
    #expect(!intoItself)
    #expect(toTop)
    #expect(library.groupTree.count == 2)
}

@Test func groupsSavedBeforeNestingStayAtTopLevel() throws {
    let json = #"{"formatVersion":2,"projects":[{"id":"9C1B4E7A-1111-4C1D-8E5F-000000000001","name":"Antiguo"}],"documents":[],"savedSearches":[]}"#
    let library = try JSONDecoder().decode(WritingLibrary.self, from: Data(json.utf8))
    #expect(library.projects.first?.parentID == nil)
    #expect(library.groupTree.map(\.project.name) == ["Antiguo"])
}

@Test func aCycleNeverHidesItsGroups() {
    var library = WritingLibrary()
    var a = Project(name: "A")
    var b = Project(name: "B")
    a.parentID = b.id
    b.parentID = a.id
    library.projects = [a, b]
    #expect(Set(library.groupTree.map(\.project.name)) == ["A", "B"])
}
