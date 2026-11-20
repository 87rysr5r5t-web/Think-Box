import Foundation
import Testing
import WritingLibrary

@Test func canvasEditsPreserveTypesAndExtensionFields() throws {
    let original = Data(#"""
    {"plugin":{"keep":true},"nodes":[
      {"id":"group","type":"group","label":"Esquema","background":"images/map.png","backgroundStyle":"repeat","x":-80,"y":-60,"width":920,"height":540},
      {"id":"a","type":"text","x":0,"y":0,"width":240,"height":90,"text":"**Hola**","extra":{"x":1234567890123456789}},
      {"id":"b","type":"file","x":300,"y":25,"width":300,"height":120,"file":"Notas/Tema.md","subpath":"#Sección"},
      {"id":"c","type":"link","x":600,"y":75,"width":200,"height":90,"url":"https://example.org","color":"#226644"}],
      "edges":[{"id":"e","fromNode":"a","fromSide":"right","fromEnd":"none","toNode":"b","toSide":"top","toEnd":"arrow","label":"referencia"}]}
    """#.utf8)
    var board = try CanvasBoard(data: original)
    board.nodes[1].x = -210
    board.nodes[1]["text"] = "Visita al bosque"
    let exported = try board.data()
    let reopened = try CanvasBoard(data: exported)
    #expect(reopened.nodes == board.nodes)
    #expect(reopened.edges == board.edges)
    #expect(reopened.searchText.contains("Visita al bosque"))
    let formatted = String(decoding: exported, as: UTF8.self)
    #expect(formatted.contains("1234567890123456789"))
    #expect(formatted.contains("plugin"))
    board.removeNode("b")
    #expect(board.edges.isEmpty)
}

@Test func invalidCanvasLeavesRoomForAnExplicitError() {
    #expect(throws: (any Error).self) { try CanvasBoard(data: Data(#"{"nodes":true}"#.utf8)) }
}
