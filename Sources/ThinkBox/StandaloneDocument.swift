import SwiftUI
import WritingLibrary

struct StandaloneDocument: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    var store: LibraryStore
    var destination: ItemDestination?
    @ViewState private var jump: JumpRequest?

    var body: some View {
        Group {
            if let destination, let document = store.document(destination.documentID) {
                DocumentEditor(store: store, document: document, openDocument: { openWindow(id: "document", value: $0) },
                               openTag: nil, onTrashChange: { dismissWindow() }, focusTitle: false, jump: jump)
                    .navigationTitle(document.displayTitle)
                    .task(id: destination) { jump = JumpRequest(destination: destination) }
            } else {
                ContentUnavailableView("Documento no disponible", systemImage: "doc")
            }
        }
    }
}
