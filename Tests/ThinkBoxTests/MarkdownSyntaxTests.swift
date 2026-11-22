import Foundation
import Testing
@testable import ThinkBox

/// What remains visible once the punctuation is removed.
private func visible(_ text: String) -> String {
    let hidden = MarkdownSyntax.punctuation(in: text)
    let units = Array(text.utf16).enumerated().filter { !hidden.contains($0.offset) }.map(\.element)
    return String(utf16CodeUnits: units, count: units.count)
}

@Test func hidesHeadingEmphasisCodeAndLinkPunctuation() {
    #expect(visible("## Título") == "Título")
    #expect(visible("> Cita") == "Cita")
    #expect(visible("Un **fuerte**, una *cursiva* y _otra_.") == "Un fuerte, una cursiva y otra.")
    #expect(visible("Usa `código` y ~~tachado~~.") == "Usa código y tachado.")
    #expect(visible("Ver [la fuente](https://example.com).") == "Ver la fuente.")
}

@Test func keepsListMarkersFencedCodeAndLoneSymbols() {
    #expect(visible("* elemento\n- otro\n1. tercero") == "* elemento\n- otro\n1. tercero")
    #expect(visible("```\n# no es título\n```") == "```\n# no es título\n```")
    #expect(visible("2 * 3 = 6 y snake_case_name") == "2 * 3 = 6 y snake_case_name")
}
