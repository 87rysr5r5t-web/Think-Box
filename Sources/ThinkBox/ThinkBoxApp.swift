import AppKit
import SwiftUI
import WritingLibrary

// The standalone macOS command-line SDK exposes the property wrapper without the SwiftUI macro plugin.
typealias ViewState<Value> = State<Value>

@main
struct ThinkBoxApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: LibraryAppDelegate
    @ViewState private var databases = LibraryDatabases()
    @ViewState private var settings = AppSettings()

    init() {
        AppAccent.install()
        AppFonts.register()
    }

    var body: some Scene {
        Window("Think Box", id: "library") {
            LibraryView(databases: databases)
                .task {
                    appDelegate.databases = databases
                    await Task.yield()
                    LibraryMenuCommands.orderNativeMenus()
                }
                .frame(minWidth: 930, minHeight: 540)
                .environment(settings)
                .font(settings.font())
                .symbolRenderingMode(.monochrome)
                .themedWindow()
                .preferredColorScheme(settings.appearance.theme.colorScheme)
                .environment(\.locale, Locale(identifier: "es_ES"))
        }
        .defaultSize(width: 1200, height: 760)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            LibraryMenuCommands()
            ToolbarCommands()
        }

        WindowGroup("Documento", id: "document", for: ItemDestination.self) { destination in
            StandaloneDocument(databases: databases, destination: destination.wrappedValue)
                .task { appDelegate.databases = databases }
                .frame(minWidth: 600, minHeight: 450)
                .environment(settings)
                .font(settings.font())
                .symbolRenderingMode(.monochrome)
                .themedWindow()
                .preferredColorScheme(settings.appearance.theme.colorScheme)
                .environment(\.locale, Locale(identifier: "es_ES"))
        }.defaultSize(width: 850, height: 700)

        Settings {
            SettingsView(settings: settings, store: databases.activeStore)
                .environment(settings)
                .themedWindow()
                .preferredColorScheme(settings.appearance.theme.colorScheme)
                .environment(\.locale, Locale(identifier: "es_ES"))
        }
    }
}

@MainActor
final class LibraryAppDelegate: NSObject, NSApplicationDelegate {
    weak var databases: LibraryDatabases?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard databases?.flushEdits() == false else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Hay cambios pendientes de guardar"
        alert.informativeText = "Think Box sigue abierto para que puedas resolver el problema de escritura y volver a guardar."
        alert.addButton(withTitle: "Volver a Think Box")
        alert.runModal()
        return .terminateCancel
    }
}
