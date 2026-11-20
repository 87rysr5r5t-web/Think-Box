import Testing
import WritingLibrary

@Test func paletteFindsAbbreviationsAndIgnoresAccents() {
    #expect(FuzzyTitleQuery("pl cmd").matches("Paleta de comandos"))
    #expect(FuzzyTitleQuery("PAPELERA").matches("Ir a Papelera"))
    #expect(FuzzyTitleQuery("etiqueta").matches("Nueva etiqueta"))
    #expect(FuzzyTitleQuery("anotacion").matches("Anotación"))
    #expect(!FuzzyTitleQuery("cba").matches("abc"))
    #expect(FuzzyTitleQuery("   ").matches("Documento"))
}
