import AppKit
import SwiftUI
import WritingLibrary

// The standalone macOS command-line SDK exposes the property wrapper without the SwiftUI macro plugin.
typealias ViewState<Value> = State<Value>

@main
struct ThinkBoxApp: App {
    @ViewState private var store = LibraryStore()
    @ViewState private var settings = AppSettings()

    init() { AppFonts.register() }

    var body: some Scene {
        Window("Think Box", id: "library") {
            LibraryView(store: store)
                .frame(minWidth: 930, minHeight: 540)
                .environment(settings)
                .font(settings.font())
                .symbolRenderingMode(.monochrome)
                .preferredColorScheme(settings.appearance.theme.colorScheme)
                .environment(\.locale, Locale(identifier: "es_ES"))
        }
        .defaultSize(width: 1200, height: 760)
        .windowStyle(.hiddenTitleBar)
        .commands { LibraryMenuCommands() }

        WindowGroup("Documento", id: "document", for: ItemDestination.self) { destination in
            StandaloneDocument(store: store, destination: destination.wrappedValue)
                .frame(minWidth: 600, minHeight: 450)
                .environment(settings)
                .font(settings.font())
                .symbolRenderingMode(.monochrome)
                .preferredColorScheme(settings.appearance.theme.colorScheme)
                .environment(\.locale, Locale(identifier: "es_ES"))
        }.defaultSize(width: 850, height: 700)

        Settings {
            SettingsView(settings: settings, store: store)
                .preferredColorScheme(settings.appearance.theme.colorScheme)
                .environment(\.locale, Locale(identifier: "es_ES"))
        }
    }
}
