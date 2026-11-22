import WritingLibrary
import AppKit
import CoreText
import SwiftUI

protocol PreferenceChoice: RawRepresentable, CaseIterable, Hashable, Codable where RawValue == String {
    var title: String { get }
}

enum WindowTheme: String, PreferenceChoice {
    case system, light, dark

    var title: String {
        switch self { case .system: "Sistema"; case .light: "Claro"; case .dark: "Oscuro" }
    }

    var colorScheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
}

enum DocumentOrder: String, PreferenceChoice {
    case recent, title
    var title: String { self == .recent ? "Fecha de modificación" : "Título" }
}

enum PDFLayout: String, PreferenceChoice {
    case continuous, single, facing

    var title: String {
        switch self { case .continuous: "Continuo"; case .single: "Página individual"; case .facing: "Doble página" }
    }
}

enum PDFSidebar: String, PreferenceChoice {
    case closed, thumbnails, outline

    var title: String {
        switch self { case .closed: "Cerrado"; case .thumbnails: "Miniaturas"; case .outline: "Índice" }
    }
}

enum PDFZoom: String, PreferenceChoice {
    case fit, actual
    var title: String { self == .fit ? "Ajustar a la ventana" : "Tamaño real" }
}

struct RGBColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double

    init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init?(_ color: Color) {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        self.init(rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
    }

    var native: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
    var color: Color { Color(nsColor: native) }
}

struct AppearanceOptions: Codable {
    var theme = WindowTheme.dark
    var font = AppFonts.quattro
    var fontSize = 13
    var listSize = 13
    var sidebarWidth = 294
    var showSidebar = true
    var compactRows = false
}

struct EditorOptions: Codable, Equatable {
    var font = AppFonts.jetbrainsLight
    var fontSize = 17
    var lineSpacing = 7
    var columnWidth = 780
    var wrapLines = true
    var showWordCount = true
    var spellCheck = false
    var grammarCheck = false
    var autoCorrect = false
    var smartQuotes = false
    var smartDashes = false
    var smartCopyPaste = false
    var textReplacement = false
    var customColors = false
    var paper = RGBColor(0.985, 0.981, 0.973)
    var ink = RGBColor(0.13, 0.14, 0.16)
}

struct ListOptions: Codable {
    var order = DocumentOrder.recent
    var showDates = true
    var showDetails = true
    var showTags = true
    var showExtensions = false
}

struct ReadingOptions: Codable {
    var pdfLayout = PDFLayout.continuous
    var pdfSidebar = PDFSidebar.closed
    var pdfZoom = PDFZoom.fit
    var pdfBackground = WindowTheme.system
    var author = ""
    var canvasGrid = true
    var fitCanvas = true
}

struct GestureOptions: Codable {
    var enabled = true
    var reverse = false
    var cascade = true
    var threshold = 0.40
    var edge = 24
    // Optional so settings saved before this control retain their other values.
    var sensitivity: SwipeSensitivity? = nil
    var horizontalWheel: Bool? = nil
    var foldNodes: Bool? = nil
}

struct PageViewOptions: Codable {
    var markdown = WritingPageViews()
    var plainText = WritingPageViews()
    var richText: WritingPageViews?
    var html: WritingPageViews?
    var layout = WritingPageLayout()
    var darkPaper = false
    var synchronize = true
}

@MainActor @Observable
final class AppSettings {
    var appearance: AppearanceOptions { didSet { save(appearance, as: "appearance") } }
    var editor: EditorOptions { didSet { save(editor, as: "editor") } }
    var list: ListOptions { didSet { save(list, as: "list") } }
    var reader: ReadingOptions { didSet { save(reader, as: "reading") } }
    var gestures: GestureOptions { didSet { save(gestures, as: "gestures") } }
    var pages: PageViewOptions { didSet { save(pages, as: "pages") } }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = Self.load("appearance", from: defaults, or: AppearanceOptions())
        editor = Self.load("editor", from: defaults, or: EditorOptions())
        list = Self.load("list", from: defaults, or: ListOptions())
        reader = Self.load("reading", from: defaults, or: ReadingOptions())
        gestures = Self.load("gestures", from: defaults, or: GestureOptions())
        pages = Self.load("pages", from: defaults, or: PageViewOptions())
    }

    func font(_ offset: Int = 0, bold: Bool = false, list: Bool = false) -> Font {
        let size = CGFloat(max(9, (list ? appearance.listSize : appearance.fontSize) + offset))
        let name = appearance.font
        if name == AppFonts.quattro && bold && NSFont(name: AppFonts.quattroBold, size: size) != nil {
            return .custom(AppFonts.quattroBold, fixedSize: size)
        }
        guard name != AppFonts.system, NSFont(name: name, size: size) != nil else {
            return .system(size: size, weight: bold ? .semibold : .regular)
        }
        let font = Font.custom(name, fixedSize: size)
        return bold ? font.weight(.semibold) : font
    }

    private static func load<T: Codable>(_ key: String, from defaults: UserDefaults, or fallback: T) -> T {
        guard let data = defaults.data(forKey: "ThinkBox.preferences.\(key)") else { return fallback }
        return (try? JSONDecoder().decode(T.self, from: data)) ?? fallback
    }

    private func save<T: Codable>(_ value: T, as key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: "ThinkBox.preferences.\(key)") }
    }
}

enum AppFonts {
    static let system = "system"
    static let quattro = "iAWriterQuattroS-Regular"
    static let quattroBold = "iAWriterQuattroS-Bold"
    static let jetbrainsLight = "JetBrainsMono-Light"

    static func register() {
        let packaged = Bundle.main.resourceURL?.appending(path: "Fonts", directoryHint: .isDirectory)
        let directory: URL?
        if let packaged, FileManager.default.fileExists(atPath: packaged.path) {
            directory = packaged
        } else {
            directory = Bundle.module.url(forResource: "Fonts", withExtension: nil)
        }
        guard let directory else { return }
        for name in [quattro, quattroBold, jetbrainsLight] {
            CTFontManagerRegisterFontsForURL(directory.appending(path: name + ".ttf") as CFURL, .process, nil)
        }
    }

    static func label(_ name: String) -> String {
        switch name {
        case system: "Fuente del sistema"
        case quattro: "iA Writer Quattro"
        case quattroBold: "iA Writer Quattro Bold"
        case jetbrainsLight: "JetBrains Mono Light"
        default: NSFont(name: name, size: 13)?.displayName ?? name
        }
    }

    static func editorFont(_ name: String, size: CGFloat) -> NSFont {
        if name == system { return .systemFont(ofSize: size) }
        return NSFont(name: name, size: size) ?? .monospacedSystemFont(ofSize: size, weight: .light)
    }
}
