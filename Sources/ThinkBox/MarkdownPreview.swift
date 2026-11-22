import AppKit
import PDFKit
import SwiftUI
import WritingLibrary

enum PageDisplay: String, CaseIterable, Identifiable, Codable {
    case continuous = "Continua"
    case single = "Página a página"
    case spreads = "Páginas enfrentadas"

    var id: Self { self }
    var mode: PDFDisplayMode {
        switch self {
        case .continuous: .singlePageContinuous
        case .single: .singlePage
        case .spreads: .twoUpContinuous
        }
    }
}

enum PageZoom: Equatable, Codable {
    case width, fit, percent(Int)
}

struct PageDestination: Equatable {
    let id = UUID()
    let index: Int
}

struct PaginatedPreview: NSViewRepresentable {
    let pages: MarkdownPages
    let display: PageDisplay
    let zoom: PageZoom
    let destination: PageDestination?
    let onPage: (Int) -> Void
    let onZoom: (PageZoom) -> Void
    let onView: (PDFView) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> PDFView {
        let view = PreviewView()
        view.coordinator = context.coordinator
        Task { @MainActor [weak view] in if let view { onView(view) } }
        view.setAccessibilityLabel("Previsualización paginada")
        view.backgroundColor = NSColor.windowBackgroundColor.blended(withFraction: 0.1, of: .black) ?? .windowBackgroundColor
        view.displaysPageBreaks = true
        view.pageBreakMargins = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        view.minScaleFactor = 0.15
        view.maxScaleFactor = 4
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.pageChanged(_:)),
                                               name: .PDFViewPageChanged, object: view)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.updating = true
        defer {
            coordinator.updating = false
            coordinator.reportPage(view)
        }
        let previous = view.currentPage.flatMap { view.document?.index(for: $0) } ?? 0
        let changedData = coordinator.data != pages.data
        let changedDisplay = view.displayMode != display.mode
        if changedDisplay {
            view.displayMode = display.mode
            view.displaysAsBook = display == .spreads
        }
        if changedData {
            coordinator.data = pages.data
            view.document = PDFDocument(data: pages.data)
        }
        if changedData || changedDisplay || zoom != coordinator.zoom {
            coordinator.zoom = zoom
            coordinator.applyZoom(view)
        }
        if let destination, destination.id != coordinator.destination {
            coordinator.destination = destination.id
            coordinator.go(destination.index, in: view)
        } else if changedData || changedDisplay {
            coordinator.go(previous, in: view)
        }
    }

    final class PreviewView: PDFView {
        weak var coordinator: Coordinator?

        override func layout() {
            super.layout()
            guard let coordinator, !coordinator.updating, coordinator.zoom == .width || coordinator.zoom == .fit else { return }
            coordinator.applyZoom(self)
        }

        override func magnify(with event: NSEvent) {
            let value = min(400, max(50, Int(scaleFactor * (1 + event.magnification) * 100)))
            autoScales = false
            scaleFactor = CGFloat(value) / 100
            coordinator?.parent.onZoom(.percent(value))
        }
    }

    @MainActor final class Coordinator: NSObject {
        var parent: PaginatedPreview
        var data: Data?
        var destination: UUID?
        var zoom: PageZoom?
        var updating = false
        private var lastPage: Int?

        init(_ parent: PaginatedPreview) { self.parent = parent }

        @objc func pageChanged(_ notification: Notification) {
            if let view = notification.object as? PDFView, !updating { reportPage(view) }
        }

        func reportPage(_ view: PDFView) {
            guard let page = view.currentPage, let document = view.document else { return }
            let index = document.index(for: page)
            guard index != lastPage else { return }
            lastPage = index
            Task { @MainActor [weak self] in self?.parent.onPage(index) }
        }

        func go(_ page: Int, in view: PDFView) {
            if let document = view.document, document.pageCount > 0,
               let target = document.page(at: max(0, min(page, document.pageCount - 1))),
               view.currentPage !== target {
                view.go(to: target)
            }
        }

        func applyZoom(_ view: PDFView) {
            switch zoom {
            case .fit, .width:
                guard let size = view.document?.page(at: 0)?.bounds(for: .mediaBox).size,
                      size.width > 0, size.height > 0, view.bounds.width > 60, view.bounds.height > 50 else { return }
                let shownPages: CGFloat = parent.display == .spreads ? 2 : 1
                let width = (view.bounds.width - 28 * shownPages) / (size.width * shownPages)
                let height = (view.bounds.height - 28) / size.height
                let fit = max(view.minScaleFactor, min(view.maxScaleFactor, zoom == .fit ? min(width, height) : width))
                if view.autoScales { view.autoScales = false }
                if abs(view.scaleFactor - fit) > 0.002 { view.scaleFactor = fit }
            case .percent(let value):
                if view.autoScales { view.autoScales = false }
                view.scaleFactor = CGFloat(value) / 100
            case nil: break
            }
        }
    }
}

struct ContinuousMarkdownPreview: NSViewRepresentable {
    let input: MarkdownPageInput
    var sourceTarget: TextReveal? = nil
    var onSource: ((Int) -> Void)? = nil
    let open: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.scrollerStyle = .overlay
        scroll.contentView.postsBoundsChangedNotifications = true
        context.coordinator.scroll = scroll
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.moved),
            name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        if let view = scroll.documentView as? NSTextView {
            view.drawsBackground = false
            view.isEditable = false
            view.textContainerInset = NSSize(width: 20, height: 14)
            view.delegate = context.coordinator
            view.setAccessibilityLabel("Previsualización continua")
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.open = open
        coordinator.onSource = onSource
        guard let view = scroll.documentView as? NSTextView else { return }
        coordinator.target = sourceTarget
        if input != coordinator.input {
            coordinator.render(input, in: view)
        }
        coordinator.followSource(in: view)
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var input: MarkdownPageInput?
        var open: ((URL) -> Void)?
        var onSource: ((Int) -> Void)?
        weak var scroll: NSScrollView?
        private var renderTask: Task<Void, Never>?
        private var positions: [(source: Int, rendered: Int)] = []
        var target: TextReveal?
        var lastTarget: UUID?
        var programmatic = false
        var lastOffset: Int?

        func render(_ input: MarkdownPageInput, in view: NSTextView) {
            let delayed = self.input != nil || input.source.utf8.count > 128_000
            self.input = input
            renderTask?.cancel()
            if delayed {
                renderTask = Task { @MainActor [weak self, weak view] in
                    do { try await Task.sleep(for: .milliseconds(180)) }
                    catch { return }
                    if let view { self?.apply(input, to: view) }
                }
            } else {
                apply(input, to: view)
            }
        }

        private func apply(_ input: MarkdownPageInput, to view: NSTextView) {
            guard let storage = view.textStorage else { return }
            let visible = scroll?.documentVisibleRect.origin
            programmatic = true
            storage.setAttributedString(MarkdownPagination.continuous(input))
            positions.removeAll(keepingCapacity: true)
            storage.enumerateAttribute(MarkdownPagination.sourcePosition,
                in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                if let source = value as? Int { positions.append((source, range.location)) }
            }
            if target == nil, let visible, let scroll {
                scroll.contentView.scroll(to: visible)
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            programmatic = false
            lastTarget = nil
            followSource(in: view)
        }

        func followSource(in view: NSTextView) {
            guard let target, lastTarget != target.id, !positions.isEmpty else { return }
            lastTarget = target.id
            var low = 0
            var high = positions.count
            while low < high {
                let middle = (low + high) / 2
                if positions[middle].source <= target.range.location { low = middle + 1 }
                else { high = middle }
            }
            programmatic = true
            view.scrollRangeToVisible(NSRange(location: positions[max(0, low - 1)].rendered, length: 0))
            programmatic = false
        }

        @objc func moved() {
            guard !programmatic, let scroll, let view = scroll.documentView as? NSTextView,
                  let manager = view.layoutManager, let container = view.textContainer,
                  let storage = view.textStorage, storage.length > 0 else { return }
            let point = CGPoint(x: 0, y: max(0, scroll.documentVisibleRect.minY - view.textContainerOrigin.y))
            let glyph = manager.glyphIndex(for: point, in: container)
            guard glyph < manager.numberOfGlyphs else { return }
            let character = manager.characterIndexForGlyph(at: glyph)
            guard let offset = storage.attribute(MarkdownPagination.sourcePosition, at: character, effectiveRange: nil) as? Int,
                  offset != lastOffset else { return }
            lastOffset = offset
            Task { @MainActor [weak self] in self?.onSource?(offset) }
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = link as? URL else { return false }
            open?(url)
            return true
        }
    }
}
