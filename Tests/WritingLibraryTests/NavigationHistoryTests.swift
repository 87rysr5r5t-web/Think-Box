import Testing
import WritingLibrary

@Test func historyTravelsBothWaysAndClearsTheForwardBranch() {
    var history = NavigationHistory<String>()
    history.record(from: "Biblioteca", to: "Entrada")
    history.record(from: "Entrada", to: "Documento")
    history.record(from: "Documento", to: "Documento")
    #expect(history.back(from: "Documento") == "Entrada")
    #expect(history.back(from: "Entrada") == "Biblioteca")
    #expect(!history.canGoBack)
    #expect(history.forward(from: "Biblioteca") == "Entrada")
    history.record(from: "Entrada", to: "Papelera")
    #expect(!history.canGoForward)
    #expect(history.back(from: "Papelera") == "Entrada")
}
