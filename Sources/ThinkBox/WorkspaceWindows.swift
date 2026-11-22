import AppKit
import SwiftUI
import WritingLibrary

struct SavedWindowFrame: Codable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ frame: NSRect) {
        x = frame.minX
        y = frame.minY
        width = frame.width
        height = frame.height
    }

    /// Frame guardado ajustado al área visible dada, respetando el tamaño mínimo mientras quepa.
    func fitted(to visible: NSRect, minimum: NSSize) -> NSRect {
        let width = min(max(minimum.width, self.width), visible.width)
        let height = min(max(minimum.height, self.height), visible.height)
        return NSRect(x: min(max(x, visible.minX), visible.maxX - width),
                      y: min(max(y, visible.minY), visible.maxY - height),
                      width: width, height: height)
    }

    @MainActor func apply(to window: NSWindow) {
        let proposed = NSRect(x: x, y: y, width: width, height: height)
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(proposed) } ?? NSScreen.main
        window.setFrame(fitted(to: screen?.visibleFrame ?? proposed, minimum: window.minSize), display: true)
    }
}

struct SavedDocumentWindow: Codable {
    var destination: ItemDestination
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var inspectorVisible: Bool?
    var inspectorWidth: Double?
    var minimized: Bool?
    var reader: DocumentReaderState?
}

enum DocumentReaderState: Equatable, Codable {
    case writing(WritingReaderState)
    case pdf(PDFReaderState)
}

struct WritingReaderState: Equatable, Codable {
    var outline: Bool
    var rulers: Bool
    var thumbnails: Bool
    var sourceZoom: PageZoom
    var previewZoom: PageZoom
    var previewLayout: PageDisplay
    var sourceOffset: Int
    var previewOffset: Int
    var previewPage: Int
}

struct PDFReaderState: Equatable, Codable {
    var page: Int
    var scale: CGFloat
    var autoScale: Bool
    var display: Int
    var inspector: String?
}

struct DocumentReaderRestore: Equatable {
    let id = UUID()
    let state: DocumentReaderState
}

@MainActor final class WorkspaceWindows {
    static let shared = WorkspaceWindows()
    struct Entry {
        weak var window: NSWindow?
        var destination: ItemDestination
        var inspectorVisible: Bool
        var inspectorWidth: Double
        var reader: DocumentReaderState?
        var applyState: (Bool, Double, DocumentReaderState?) -> Void
    }
    var entries: [ObjectIdentifier: Entry] = [:]
    var pending: [ItemDestination: SavedDocumentWindow] = [:]
    weak var mainWindow: NSWindow?

    var mainFrame: SavedWindowFrame? { mainWindow.map { SavedWindowFrame($0.frame) } }

    func snapshot() -> [SavedDocumentWindow] {
        entries = entries.filter { $0.value.window != nil }
        return entries.values.compactMap { entry in
            guard let window = entry.window, window.isVisible || window.isMiniaturized else { return nil }
            let frame = window.frame
            return SavedDocumentWindow(destination: entry.destination, x: frame.minX, y: frame.minY,
                width: frame.width, height: frame.height, inspectorVisible: entry.inspectorVisible,
                inspectorWidth: entry.inspectorWidth, minimized: window.isMiniaturized, reader: entry.reader)
        }
    }

    func restore(_ windows: [SavedDocumentWindow], open: (ItemDestination) -> Void) {
        let destinations = Set(windows.map(\.destination))
        pending.removeAll()
        let existing = entries.values.filter { $0.window != nil }
        for entry in existing where !destinations.contains(entry.destination) {
            if let window = entry.window, window.isVisible || window.isMiniaturized { window.close() }
        }
        for saved in windows {
            if let entry = existing.first(where: {
                $0.destination == saved.destination && ($0.window?.isVisible == true || $0.window?.isMiniaturized == true)
            }) {
                apply(saved, to: entry)
            } else {
                pending[saved.destination] = saved
                open(saved.destination)
            }
        }
    }

    func register(_ window: NSWindow, destination: ItemDestination, inspectorVisible: Bool,
                  inspectorWidth: Double, reader: DocumentReaderState?,
                  applyState: @escaping (Bool, Double, DocumentReaderState?) -> Void) {
        let entry = Entry(window: window, destination: destination, inspectorVisible: inspectorVisible,
                          inspectorWidth: inspectorWidth, reader: reader, applyState: applyState)
        entries[ObjectIdentifier(window)] = entry
        if let saved = pending.removeValue(forKey: destination) {
            DispatchQueue.main.async { self.apply(saved, to: entry) }
        }
    }

    private func apply(_ saved: SavedDocumentWindow, to entry: Entry) {
        if let window = entry.window {
            SavedWindowFrame(NSRect(x: saved.x, y: saved.y, width: saved.width, height: saved.height)).apply(to: window)
            entry.applyState(saved.inspectorVisible ?? entry.inspectorVisible,
                             saved.inspectorWidth ?? entry.inspectorWidth, saved.reader)
            if saved.minimized == true && !window.isMiniaturized { window.miniaturize(nil) }
            if saved.minimized == false && window.isMiniaturized { window.deminiaturize(nil) }
        }
    }
}

struct MainWindowTracker: NSViewRepresentable {
    func makeNSView(context: Context) -> Tracker { Tracker() }
    func updateNSView(_ view: Tracker, context: Context) {}

    final class Tracker: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            WorkspaceWindows.shared.mainWindow = window
            // Toolbar and title bar take the panel surface colour instead of the system material.
            window.titlebarAppearsTransparent = true
            window.backgroundColor = WindowPalette.nativeSurface
            window.titleVisibility = .hidden
        }
    }
}

struct WorkspaceWindowTracker: NSViewRepresentable {
    var destination: ItemDestination
    @Binding var inspectorVisible: Bool
    @Binding var inspectorWidth: Double
    var reader: DocumentReaderState?
    var restoreReader: (DocumentReaderState) -> Void
    func makeNSView(context: Context) -> Tracker { Tracker() }
    func updateNSView(_ view: Tracker, context: Context) {
        view.register = { window in
            WorkspaceWindows.shared.register(window, destination: destination, inspectorVisible: inspectorVisible,
                inspectorWidth: inspectorWidth, reader: reader, applyState: { visible, width, reader in
                    inspectorVisible = visible
                    inspectorWidth = width
                    if let reader { restoreReader(reader) }
                })
        }
        if let window = view.window { view.register?(window) }
    }
    final class Tracker: NSView {
        var register: ((NSWindow) -> Void)?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { register?(window) }
        }
    }
}
