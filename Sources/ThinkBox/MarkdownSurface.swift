import AppKit
import SwiftUI
import WritingLibrary

struct TextReveal: Equatable {
    let id = UUID()
    let range: NSRange
}

struct TextInsertion: Equatable {
    let id = UUID()
    let text: String
}

struct SourcePaper: Equatable {
    let layout: WritingPageLayout
    let metadata: PageMetadata
    let dark: Bool
}

struct MarkdownSurface: NSViewRepresentable {
    var text: String
    var editable: Bool
    var taggable: Bool
    var options: EditorOptions
    var reveal: TextReveal?
    var scrollTo: TextReveal? = nil
    var pageTarget: PageDestination? = nil
    var insertion: TextInsertion? = nil
    var paper: SourcePaper? = nil
    var richTextData: Data? = nil
    var onRichEdit: ((Data, String) -> Void)? = nil
    var plain = false
    var showsRulers = false
    var onMargins: ((WritingPageLayout) -> Void)? = nil
    var onRulerHeight: ((CGFloat) -> Void)? = nil
    var onViewport: ((Int, Int, Int) -> Void)? = nil
    var onEdit: (String, NSRange, Int) -> Void
    var onSelect: (NSRange) -> Void
    var fragmentAction: (NSRange, Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = SourceScrollView()
        scroll.clipsToBounds = true
        scroll.automaticallyAdjustsContentInsets = false
        scroll.minMagnification = 0.15
        scroll.maxMagnification = 4
        scroll.hasVerticalScroller = true
        if onRulerHeight != nil { scroll.scrollerStyle = .overlay }
        scroll.drawsBackground = false
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        storage.addLayoutManager(manager)
        let container = SourceTextContainer()
        manager.addTextContainer(container)
        let editor = Editor(frame: scroll.contentView.bounds, textContainer: container)
        // The scroll view retains the view and the view retains the TextKit stack.
        editor.storage = storage
        editor.pageFlow = PageFlow()
        manager.delegate = editor.pageFlow
        editor.usesFindBar = true
        scroll.contentView.postsBoundsChangedNotifications = true
        scroll.contentView.postsFrameChangedNotifications = true
        for notification in [NSView.boundsDidChangeNotification, NSView.frameDidChangeNotification] {
            NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.viewportChanged),
                                                   name: notification, object: scroll.contentView)
        }
        context.coordinator.scroll = scroll
        editor.autoresizingMask = [.width]
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.minSize = NSSize(width: 0, height: scroll.contentView.bounds.height)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: scroll.contentView.bounds.width, height: .greatestFiniteMagnitude)
        editor.textContainerInset = NSSize(width: 0, height: 12)
        editor.isRichText = richTextData != nil
        editor.importsGraphics = richTextData != nil
        editor.usesFontPanel = richTextData != nil
        editor.usesRuler = richTextData != nil
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.setAccessibilityLabel("Contenido en Markdown")
        editor.string = text
        if let richTextData, let attributed = try? NSAttributedString(data: richTextData,
            options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil) {
            storage.setAttributedString(attributed)
        }
        context.coordinator.lastRichData = richTextData
        applyOptions(to: editor, in: scroll)
        context.coordinator.appliedOptions = options
        editor.delegate = context.coordinator
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? Editor else { return }
        context.coordinator.parent = self
        // Dead keys and input methods own the marked range until composition commits.
        // Replacing text or applying attributes here cancels accents in progress.
        guard !editor.hasMarkedText() else { return }
        let paperChanged = editor.paper != paper
        let geometryChanged = editor.paper?.layout != paper?.layout || (editor.paper == nil) != (paper == nil)
        editor.paper = paper
        editor.pageFlow?.plain = plain
        if let sourceScroll = scroll as? SourceScrollView {
            sourceScroll.allowsMagnification = false
            if paper == nil && sourceScroll.magnification != 1 { sourceScroll.magnification = 1 }
        }
        editor.showsPageRulers = showsRulers
        editor.onMargins = onMargins
        if paper == nil { editor.updatePageRulers(in: scroll, page: 0) }
        editor.isEditable = editable
        editor.fragmentAction = taggable ? fragmentAction : nil
        if richTextData != context.coordinator.lastRichData, let richTextData,
           let attributed = try? NSAttributedString(data: richTextData,
            options: [.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil) {
            editor.textStorage?.setAttributedString(attributed)
            context.coordinator.synchronizedText = attributed.string
            context.coordinator.lastRichData = richTextData
        }
        let replacedText = context.coordinator.synchronizedText != text
        if replacedText {
            editor.string = text
            context.coordinator.synchronizedText = text
        }
        if let flow = editor.pageFlow, let manager = editor.layoutManager {
            let hides = options.hideMarkdown == true && !plain && richTextData == nil
            if hides == flow.hidesSyntax && replacedText { flow.reload(in: manager, caret: editor.selectedRange()) }
            flow.setHidesSyntax(hides, in: manager, caret: editor.selectedRange())
        }
        if replacedText || geometryChanged || context.coordinator.appliedOptions != options
            || context.coordinator.appliedDarkPaper != paper?.dark {
            applyOptions(to: editor, in: scroll)
            context.coordinator.appliedOptions = options
            context.coordinator.appliedDarkPaper = paper?.dark
        }
        if paperChanged { editor.needsDisplay = true }
        if let pageTarget, context.coordinator.lastPageTarget != pageTarget.id, let paper {
            context.coordinator.lastPageTarget = pageTarget.id
            editor.updatePaperFrame(in: scroll)
            let y = CGFloat(min(pageTarget.index, editor.pageCount - 1)) * (paper.layout.paperSize.height + Editor.pageGap)
            scroll.contentView.scroll(to: CGPoint(x: scroll.contentView.bounds.minX, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        if let scrollTo, context.coordinator.lastScroll != scrollTo.id {
            context.coordinator.lastScroll = scrollTo.id
            editor.scrollRangeToVisible(scrollTo.range)
        }
        if let insertion, context.coordinator.lastInsertion != insertion.id {
            context.coordinator.lastInsertion = insertion.id
            Task { @MainActor [weak editor] in
                guard let editor, editor.isEditable else { return }
                editor.window?.makeFirstResponder(editor)
                editor.insertText(insertion.text, replacementRange: editor.selectedRange())
            }
        }
        context.coordinator.schedulePageUpdate()
        if let reveal, context.coordinator.lastReveal != reveal.id {
            context.coordinator.lastReveal = reveal.id
            editor.window?.makeFirstResponder(editor)
            editor.setSelectedRange(reveal.range)
            editor.scrollRangeToVisible(reveal.range)
        }
    }

    private func applyOptions(to editor: Editor, in scroll: NSScrollView) {
        let font = AppFonts.editorFont(options.font, size: CGFloat(options.fontSize))
        let color: NSColor
        if let paper { color = paper.dark ? NSColor(white: 0.91, alpha: 1) : .black }
        else { color = options.customColors ? options.ink.native : .labelColor }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = CGFloat(options.lineSpacing)
        paragraph.lineBreakMode = (paper != nil || options.wrapLines) ? .byWordWrapping : .byClipping
        if options.justify == true { paragraph.alignment = .justified }
        if options.hyphenate == true { paragraph.hyphenationFactor = 1 }
        if richTextData == nil { editor.font = font; editor.textColor = color }
        editor.insertionPointColor = color
        editor.defaultParagraphStyle = paragraph
        if richTextData == nil { editor.typingAttributes = [.font: font, .paragraphStyle: paragraph, .foregroundColor: color] }
        if richTextData == nil, let storage = editor.textStorage, storage.length > 0 {
            storage.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: storage.length))
        }
        editor.pageFlow?.layout = paper?.layout
        if let paper {
            editor.drawsBackground = true
            editor.isVerticallyResizable = false
            editor.isHorizontallyResizable = false
            editor.autoresizingMask = []
            editor.textContainer?.widthTracksTextView = false
            editor.textContainer?.lineFragmentPadding = 0
            let size = paper.layout.contentRect(page: 0).size
            if let container = editor.textContainer as? SourceTextContainer {
                let normal = paper.layout.contentRect(page: 0)
                let mirrored = paper.layout.contentRect(page: 1)
                container.contentWidth = size.width
                container.size = NSSize(width: size.width + abs(normal.minX - mirrored.minX), height: .greatestFiniteMagnitude)
            }
            if let storage = editor.textStorage {
                editor.layoutManager?.invalidateLayout(forCharacterRange: NSRange(location: 0, length: storage.length),
                                                       actualCharacterRange: nil)
            }
            editor.updatePaperFrame(in: scroll)
        } else {
            editor.drawsBackground = false
            editor.isVerticallyResizable = true
            editor.textContainerInset = NSSize(width: 0, height: 12)
            editor.textContainer?.lineFragmentPadding = 5
            (editor.textContainer as? SourceTextContainer)?.contentWidth = nil
            scroll.hasHorizontalScroller = !options.wrapLines
            editor.isHorizontallyResizable = !options.wrapLines
            editor.autoresizingMask = options.wrapLines ? [.width] : []
            editor.minSize = NSSize(width: 0, height: scroll.contentSize.height)
            if options.wrapLines { editor.setFrameSize(NSSize(width: scroll.contentSize.width, height: editor.frame.height)) }
            editor.textContainer?.widthTracksTextView = options.wrapLines
            editor.textContainer?.size = NSSize(width: options.wrapLines ? scroll.contentSize.width : .greatestFiniteMagnitude,
                                                height: .greatestFiniteMagnitude)
            editor.sizeToFit()
        }
        editor.isContinuousSpellCheckingEnabled = options.spellCheck
        editor.isGrammarCheckingEnabled = options.spellCheck && options.grammarCheck
        editor.isAutomaticSpellingCorrectionEnabled = options.autoCorrect
        editor.isAutomaticQuoteSubstitutionEnabled = options.smartQuotes
        editor.isAutomaticDashSubstitutionEnabled = options.smartDashes
        editor.smartInsertDeleteEnabled = options.smartCopyPaste
        editor.isAutomaticTextReplacementEnabled = options.textReplacement
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownSurface
        var lastReveal: UUID?
        var appliedOptions: EditorOptions?
        var appliedDarkPaper: Bool?
        var lastScroll: UUID?
        var lastPageTarget: UUID?
        var lastInsertion: UUID?
        private var lastViewport: (Int, Int, Int)?
        private var lastRulerHeight: CGFloat?
        weak var scroll: NSScrollView?
        private var pageUpdateQueued = false
        private var settledPageTask: Task<Void, Never>?

        @objc func viewportChanged() { schedulePageUpdate() }

        func schedulePageUpdate() {
            guard parent.onViewport != nil, !pageUpdateQueued else { return }
            pageUpdateQueued = true
            Task { @MainActor [weak self] in
                guard let self else { return }
                pageUpdateQueued = false
                guard let scroll, let editor = scroll.documentView as? Editor,
                      let manager = editor.layoutManager, let container = editor.textContainer else { return }
                let visible = scroll.documentVisibleRect
                var page = 0
                if let paper = editor.paper {
                    let stride = paper.layout.paperSize.height + Editor.pageGap
                    page = min(editor.pageCount - 1, max(0, Int((visible.minY + 24) / stride)))
                    editor.activeRulerPage = page
                    let rulersChanged = scroll.rulersVisible != editor.showsPageRulers
                    editor.updatePageRulers(in: scroll, page: page)
                    editor.updatePaperFrame(in: scroll, refreshPageCount: settledPageTask == nil)
                    if rulersChanged {
                        scroll.contentView.scroll(to: visible.origin)
                        scroll.reflectScrolledClipView(scroll.contentView)
                    }
                }
                let ruler = scroll.horizontalRulerView
                let rulerHeight = scroll.rulersVisible ? max(ruler?.frame.height ?? 0, ruler?.requiredThickness ?? 0) : 0
                if lastRulerHeight != rulerHeight {
                    lastRulerHeight = rulerHeight
                    parent.onRulerHeight?(rulerHeight)
                }
                let origin = editor.textContainerOrigin
                let offset: Int
                if let length = editor.textStorage?.length, length > 0 {
                    let glyph = manager.glyphIndex(for: CGPoint(x: 0, y: max(0, visible.minY + 12 - origin.y)), in: container)
                    offset = manager.isValidGlyphIndex(glyph) ? manager.characterIndexForGlyph(at: glyph) : length
                } else { offset = 0 }
                let viewport = (page, editor.pageCount, offset)
                if let lastViewport, lastViewport == viewport { return }
                lastViewport = viewport
                parent.onViewport?(page, editor.pageCount, offset)
            }
        }
        var lastRichData: Data?
        var synchronizedText: String
        private var edit: (NSRange, Int)?

        init(_ parent: MarkdownSurface) {
            self.parent = parent
            synchronizedText = parent.text
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            edit = replacementString.map { (affectedCharRange, $0.utf16.count) }
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            guard !editor.hasMarkedText() else { edit = nil; return }
            if let flow = (editor as? Editor)?.pageFlow, let manager = editor.layoutManager {
                flow.textChanged(in: manager, caret: editor.selectedRange())
            }
            if (editor as? Editor)?.paper != nil { scheduleSettledPageCount() }
            let currentText = editor.string
            synchronizedText = currentText
            if parent.richTextData != nil, let storage = editor.textStorage,
               let data = try? storage.data(from: NSRange(location: 0, length: storage.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]) {
                lastRichData = data
                parent.onRichEdit?(data, currentText)
                edit = nil
                schedulePageUpdate()
                return
            }
            if let (range, length) = edit, range.location != NSNotFound,
               parent.text.utf16.count - range.length + length == editor.textStorage?.length {
                parent.onEdit(currentText, range, length)
            } else {
                let original = Array(parent.text.utf16)
                let updated = Array(currentText.utf16)
                let prefix = zip(original, updated).prefix { $0 == $1 }.count
                let suffix = zip(original.dropFirst(prefix).reversed(), updated.dropFirst(prefix).reversed())
                    .prefix { $0 == $1 }.count
                parent.onEdit(currentText, NSRange(location: prefix, length: original.count - prefix - suffix),
                              updated.count - prefix - suffix)
            }
            edit = nil
            schedulePageUpdate()
        }

        private func scheduleSettledPageCount() {
            settledPageTask?.cancel()
            settledPageTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .milliseconds(260)) }
                catch { return }
                self?.settledPageTask = nil
                self?.schedulePageUpdate()
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            if let editor = notification.object as? NSTextView {
                if let flow = (editor as? Editor)?.pageFlow, let manager = editor.layoutManager, !editor.hasMarkedText() {
                    flow.caretMoved(in: manager, caret: editor.selectedRange())
                }
                let range = editor.selectedRange()
                Task { @MainActor in parent.onSelect(range) }
            }
        }
    }

    final class Editor: NSTextView {
        nonisolated static let pageGap: CGFloat = 22
        var storage: NSTextStorage?
        var paper: SourcePaper?
        var pageFlow: PageFlow?
        var pageCount = 1
        var activeRulerPage = 0
        var showsPageRulers = false
        var onMargins: ((WritingPageLayout) -> Void)?

        func updatePaperFrame(in scroll: NSScrollView, refreshPageCount: Bool = true) {
            guard let paper, let layoutManager, let textContainer else { return }
            let size = paper.layout.paperSize
            let stride = size.height + Self.pageGap
            let clipSize = scroll.contentView.frame.size
            // F2-R08: the sheet always fills the panel width minus a ~3 mm border on each side.
            // There is no user zoom (F2-R07); saved zoom values are read but ignored.
            if clipSize.width > 80 && clipSize.height > 80 {
                let scale = max(0.05, (clipSize.width - DesignTokens.pageBorder * 2) / size.width)
                let adjusted = min(scroll.maxMagnification, max(scroll.minMagnification, scale))
                if abs(scroll.magnification - adjusted) > 0.002 { scroll.magnification = adjusted }
            }
            let viewport = scroll.contentView.bounds.size
            let width = max(viewport.width, size.width)
            let innerLeft = min(paper.layout.contentRect(page: 0).minX, paper.layout.contentRect(page: 1).minX)
            let left = (width - size.width) / 2 + innerLeft
            let inset = NSSize(width: left, height: Self.pageGap + paper.layout.contentRect(page: 0).minY)
            if textContainerInset != inset { textContainerInset = inset }
            let needsScroller = width > viewport.width + 2
            if scroll.hasHorizontalScroller != needsScroller { scroll.hasHorizontalScroller = needsScroller }
            let count: Int
            if refreshPageCount {
                layoutManager.ensureLayout(for: textContainer)
                let textBottom = max(layoutManager.usedRect(for: textContainer).maxY,
                                     layoutManager.extraLineFragmentRect.maxY)
                count = max(1, Int(ceil(textBottom / stride)))
            } else {
                // Keep space for the caret without reflowing the entire suffix while the user types.
                let visiblePage = Int(ceil(scroll.documentVisibleRect.maxY / stride))
                count = max(pageCount, min(visiblePage, pageCount + 1))
            }
            if count != pageCount { pageCount = count; needsDisplay = true }
            let floor = NSSize(width: width, height: max(viewport.height, CGFloat(count) * stride + Self.pageGap))
            if minSize != floor { minSize = floor }
            if frame.size != floor { setFrameSize(floor) }
        }

        func updatePageRulers(in scroll: NSScrollView, page: Int) {
            let displayed = showsPageRulers && paper != nil
            if !displayed {
                if scroll.rulersVisible { scroll.rulersVisible = false }
                return
            }
            guard let paper else { return }
            if !scroll.hasHorizontalRuler || !scroll.hasVerticalRuler {
                scroll.hasHorizontalRuler = true
                scroll.hasVerticalRuler = true
                for ruler in [scroll.horizontalRulerView, scroll.verticalRulerView].compactMap({ $0 }) {
                    ruler.clientView = self
                    ruler.measurementUnits = .centimeters
                    ruler.reservedThicknessForMarkers = 7
                }
            }
            if !scroll.rulersVisible { scroll.rulersVisible = true }
            let size = paper.layout.paperSize
            let rect = paper.layout.contentRect(page: page)
            let x = (bounds.width - size.width) / 2
            let y = Self.pageGap + CGFloat(page) * (size.height + Self.pageGap)
            var positions = [rect.minX, rect.maxX]
            var keys = ["left", "right"]
            if isRichText, let storage = textStorage, storage.length > 0 {
                let index = min(selectedRange().location, storage.length - 1)
                let paragraph = storage.attribute(.paragraphStyle, at: index, effectiveRange: nil) as? NSParagraphStyle ?? .default
                positions += [rect.minX + paragraph.headIndent, rect.minX + paragraph.firstLineHeadIndent]
                keys += ["indent", "firstIndent"]
                for (index, tab) in paragraph.tabStops.enumerated() {
                    positions.append(rect.minX + tab.location)
                    keys.append("tab:\(index)")
                }
            }
            placeMarkers(in: scroll.horizontalRulerView, at: x, positions: positions, keys: keys)
            placeMarkers(in: scroll.verticalRulerView, at: y, positions: [rect.minY, rect.maxY],
                         keys: ["top", "bottom"])
        }

        private func placeMarkers(in ruler: NSRulerView?, at origin: CGFloat, positions: [CGFloat], keys: [String]) {
            guard let ruler else { return }
            if ruler.originOffset != origin { ruler.originOffset = origin }
            if let markers = ruler.markers, markers.count == positions.count {
                for (marker, location) in zip(markers, positions) {
                    if marker.markerLocation != location + origin { marker.markerLocation = location + origin }
                }
                return
            }
            guard let image = NSImage(systemSymbolName: "diamond.fill", accessibilityDescription: "Margen") else { return }
            let mark = image.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 8, weight: .medium)) ?? image
            ruler.markers = zip(positions, keys).map { location, key in
                let marker = NSRulerMarker(rulerView: ruler, markerLocation: location + origin, image: mark,
                                           imageOrigin: NSPoint(x: mark.size.width / 2, y: mark.size.height / 2))
                marker.representedObject = key as NSString
                marker.isMovable = true
                marker.isRemovable = false
                return marker
            }
        }

        override func rulerView(_ ruler: NSRulerView, shouldMove marker: NSRulerMarker) -> Bool {
            onMargins != nil && paper != nil
        }

        override func rulerView(_ ruler: NSRulerView, willMove marker: NSRulerMarker, toLocation location: CGFloat) -> CGFloat {
            guard let paper else { return location }
            let size = paper.layout.paperSize
            let edge = marker.representedObject as? String
            let horizontal = ruler.orientation == .horizontalRuler
            let limit = horizontal ? size.width : size.height
            let minimum = 8 * 72 / 25.4
            let maxInset = (limit - (horizontal ? 144 : 96)) / 2
            let origin = ruler.originOffset
            if edge == "indent" || edge == "firstIndent" || edge?.hasPrefix("tab:") == true {
                let rect = paper.layout.contentRect(page: activeRulerPage)
                return origin + min(rect.maxX - 12, max(rect.minX, location - origin))
            }
            if edge == "right" || edge == "bottom" {
                return origin + min(limit - minimum, max(limit - maxInset, location - origin))
            }
            return origin + min(maxInset, max(minimum, location - origin))
        }

        override func rulerView(_ ruler: NSRulerView, didMove marker: NSRulerMarker) {
            guard var layout = paper?.layout, let edge = marker.representedObject as? String else { return }
            if edge == "indent" || edge == "firstIndent" || edge.hasPrefix("tab:") {
                guard let storage = textStorage, storage.length > 0 else { return }
                let range = (string as NSString).paragraphRange(for: selectedRange())
                let index = min(range.location, storage.length - 1)
                let previous = storage.attributedSubstring(from: range)
                let paragraph = (storage.attribute(.paragraphStyle, at: index, effectiveRange: nil) as? NSParagraphStyle ?? .default).mutableCopy() as! NSMutableParagraphStyle
                let value = marker.markerLocation - ruler.originOffset - layout.contentRect(page: activeRulerPage).minX
                if edge == "indent" { paragraph.headIndent = value }
                else if edge == "firstIndent" { paragraph.firstLineHeadIndent = value }
                else if let tabIndex = Int(edge.dropFirst(4)), (paragraph.tabStops ?? []).indices.contains(tabIndex) {
                    var stops = paragraph.tabStops ?? []
                    stops[tabIndex] = NSTextTab(textAlignment: stops[tabIndex].alignment, location: value, options: stops[tabIndex].options)
                    paragraph.tabStops = stops.sorted { $0.location < $1.location }
                }
                guard shouldChangeText(in: range, replacementString: nil) else { return }
                undoManager?.registerUndo(withTarget: self) { target in
                    target.textStorage?.replaceCharacters(in: range, with: previous)
                    target.didChangeText()
                }
                storage.addAttribute(.paragraphStyle, value: paragraph, range: range)
                didChangeText()
                return
            }
            let mm = 25.4 / 72.0
            let location = marker.markerLocation - ruler.originOffset
            let size = layout.paperSize
            let page = activeRulerPage
            let rect = layout.contentRect(page: page)
            var insets = PageInsets()
            insets.left = rect.minX * mm
            insets.right = (size.width - rect.maxX) * mm
            insets.top = rect.minY * mm
            insets.bottom = (size.height - rect.maxY) * mm
            switch edge {
            case "left": insets.left = location * mm
            case "right": insets.right = (size.width - location) * mm
            case "top": insets.top = location * mm
            case "bottom": insets.bottom = (size.height - location) * mm
            default: return
            }
            layout.margins = .custom
            layout.customInsets = insets
            onMargins?(layout)
        }

        override func drawBackground(in rect: NSRect) {
            guard let paper else { super.drawBackground(in: rect); return }
            NSColor.windowBackgroundColor.blended(withFraction: 0.08, of: .black)?.setFill()
            rect.fill()
            let size = paper.layout.paperSize
            let stride = size.height + Self.pageGap
            let left = (bounds.width - size.width) / 2
            let first = max(0, Int(rect.minY / stride))
            let last = min(pageCount - 1, Int(rect.maxY / stride))
            guard first <= last else { return }
            for page in first...last {
                let sheet = NSRect(x: left, y: Self.pageGap + CGFloat(page) * stride, width: size.width, height: size.height)
                NSGraphicsContext.saveGraphicsState()
                let shadow = NSShadow()
                shadow.shadowBlurRadius = 5
                shadow.shadowOffset = NSSize(width: 0, height: -1)
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
                shadow.set()
                (paper.dark ? NSColor(white: 0.13, alpha: 1) : .white).setFill()
                sheet.fill()
                NSGraphicsContext.restoreGraphicsState()
                NSGraphicsContext.saveGraphicsState()
                let transform = NSAffineTransform()
                transform.translateX(by: sheet.minX, yBy: sheet.minY)
                transform.concat()
                MarkdownPagination.drawLabels(layout: paper.layout, metadata: paper.metadata, page: page,
                                              total: pageCount, dark: paper.dark)
                NSGraphicsContext.restoreGraphicsState()
            }
        }

        var fragmentAction: ((NSRange, Bool) -> Void)?

        override func menu(for event: NSEvent) -> NSMenu? {
            let menu = super.menu(for: event)
            guard selectedRange().length > 0, fragmentAction != nil else { return menu }
            let result = menu ?? NSMenu()
            for (name, action) in [("Etiquetar selección…", #selector(tagFragment)),
                                   ("Copiar enlace a la selección", #selector(copyFragment))] {
                let item = NSMenuItem(title: name, action: action, keyEquivalent: "")
                item.target = self
                result.insertItem(item, at: 0)
            }
            return result
        }

        @objc private func tagFragment() { fragmentAction?(selectedRange(), false) }
        @objc private func copyFragment() { fragmentAction?(selectedRange(), true) }
    }
}

// One container preserves AppKit's native cursor, selection, find and undo across sheets.
final class PageFlow: NSObject, NSLayoutManagerDelegate {
    var layout: WritingPageLayout? {
        didSet {
            guard layout != oldValue else { return }
            geometry = layout.map { layout in
                let first = layout.contentRect(page: 0)
                let second = layout.contentRect(page: 1)
                let left = min(first.minX, second.minX)
                return (layout.paperSize.height + MarkdownSurface.Editor.pageGap, first.height,
                        first.minX - left, second.minX - left)
            }
        }
    }
    private var geometry: (stride: CGFloat, height: CGFloat, oddX: CGFloat, evenX: CGFloat)?
    var plain = false

    // MARK: Hidden Markdown punctuation

    private(set) var hidesSyntax = false
    /// Character offsets of Markdown punctuation, recomputed after each edit.
    private var syntax = IndexSet()
    /// Paragraph holding the caret: its punctuation stays visible so it can be edited.
    private var revealed = NSRange(location: NSNotFound, length: 0)

    func setHidesSyntax(_ hides: Bool, in manager: NSLayoutManager, caret: NSRange) {
        guard hides != hidesSyntax else { return }
        hidesSyntax = hides
        guard let storage = manager.textStorage else { return }
        syntax = hides ? MarkdownSyntax.punctuation(in: storage.string) : IndexSet()
        revealed = hides ? paragraph(of: caret, in: storage) : NSRange(location: NSNotFound, length: 0)
        manager.invalidateGlyphs(forCharacterRange: NSRange(location: 0, length: storage.length), changeInLength: 0,
                                 actualCharacterRange: nil)
    }

    /// After the whole text is replaced (another document, an external change).
    func reload(in manager: NSLayoutManager, caret: NSRange) {
        guard hidesSyntax else { return }
        hidesSyntax = false
        setHidesSyntax(true, in: manager, caret: caret)
    }

    func textChanged(in manager: NSLayoutManager, caret: NSRange) {
        guard hidesSyntax, let storage = manager.textStorage else { return }
        syntax = MarkdownSyntax.punctuation(in: storage.string)
        revealed = paragraph(of: caret, in: storage)
        manager.invalidateGlyphs(forCharacterRange: revealed, changeInLength: 0, actualCharacterRange: nil)
    }

    func caretMoved(in manager: NSLayoutManager, caret: NSRange) {
        guard hidesSyntax, let storage = manager.textStorage else { return }
        let next = paragraph(of: caret, in: storage)
        guard next != revealed else { return }
        let previous = revealed
        revealed = next
        for range in [previous, next] where range.location != NSNotFound && NSMaxRange(range) <= storage.length {
            manager.invalidateGlyphs(forCharacterRange: range, changeInLength: 0, actualCharacterRange: nil)
        }
    }

    private func paragraph(of caret: NSRange, in storage: NSTextStorage) -> NSRange {
        guard caret.location != NSNotFound, caret.location <= storage.length else { return NSRange(location: NSNotFound, length: 0) }
        return (storage.string as NSString).paragraphRange(for: caret)
    }

    func layoutManager(_ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties: UnsafePointer<NSLayoutManager.GlyphProperty>,
                       characterIndexes: UnsafePointer<Int>, font: NSFont, forGlyphRange glyphRange: NSRange) -> Int {
        guard hidesSyntax, !syntax.isEmpty else { return 0 }
        let count = glyphRange.length
        var changed = false
        var adjusted = [NSLayoutManager.GlyphProperty](UnsafeBufferPointer(start: properties, count: count))
        for index in 0..<count {
            let character = characterIndexes[index]
            if syntax.contains(character) && !NSLocationInRange(character, revealed) {
                adjusted[index] = .null
                changed = true
            }
        }
        guard changed else { return 0 }
        adjusted.withUnsafeBufferPointer { buffer in
            layoutManager.setGlyphs(glyphs, properties: buffer.baseAddress!, characterIndexes: characterIndexes,
                                    font: font, forGlyphRange: glyphRange)
        }
        return count
    }

    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldSetLineFragmentRect fragment: UnsafeMutablePointer<NSRect>,
                       lineFragmentUsedRect used: UnsafeMutablePointer<NSRect>,
                       baselineOffset: UnsafeMutablePointer<CGFloat>,
                       in textContainer: NSTextContainer, forGlyphRange glyphRange: NSRange) -> Bool {
        guard let geometry else { return false }
        let stride = geometry.stride
        let y = fragment.pointee.minY
        let current = Int(y / stride)
        let start = layoutManager.characterIndexForGlyph(at: glyphRange.location)
        let force = followsManualBreak(start, in: layoutManager.textStorage)
        let overflow = fragment.pointee.maxY > CGFloat(current) * stride + geometry.height
        let next = force || overflow ? current + 1 : current
        let dy = next == current ? 0 : CGFloat(next) * stride - y
        let dx = (next.isMultiple(of: 2) ? geometry.oddX : geometry.evenX) - fragment.pointee.minX
        guard dx != 0 || dy != 0 else { return false }
        fragment.pointee.origin.x += dx
        used.pointee.origin.x += dx
        fragment.pointee.origin.y += dy
        used.pointee.origin.y += dy
        return true
    }

    private func followsManualBreak(_ offset: Int, in storage: NSTextStorage?) -> Bool {
        guard offset > 0, let storage else { return false }
        if storage.mutableString.character(at: offset - 1) == 12 { return true }
        guard offset > 1 else { return false }
        let source = storage.mutableString
        let newline = source.character(at: offset - 1)
        guard newline == 10 || newline == 13 else { return false }
        let terminator = newline == 10 && source.character(at: offset - 2) == 13 ? 2 : 1
        guard offset > terminator, source.character(at: offset - terminator - 1) == 62 else { return false }
        let previous = source.lineRange(for: NSRange(location: offset - terminator - 1, length: 0))
        let line = source.substring(with: previous).trimmingCharacters(in: .whitespacesAndNewlines)
        guard line == WritingPageLayout.pageBreak else { return false }
        if plain { return true }
        let prefix = source.substring(to: previous.location)
        var fence: Character?
        for line in prefix.split(whereSeparator: \.isNewline) {
            let trimmed = line.drop(while: \.isWhitespace)
            guard let marker = trimmed.first, marker == "`" || marker == "~",
                  trimmed.prefix(while: { $0 == marker }).count >= 3 else { continue }
            if fence == nil { fence = marker }
            else if fence == marker { fence = nil }
        }
        return fence == nil
    }
}


private final class SourceTextContainer: NSTextContainer {
    var contentWidth: CGFloat?

    override func lineFragmentRect(forProposedRect proposedRect: NSRect, at characterIndex: Int,
                                   writingDirection baseWritingDirection: NSWritingDirection,
                                   remaining remainingRect: UnsafeMutablePointer<NSRect>?) -> NSRect {
        var proposed = proposedRect
        if let contentWidth { proposed.size.width = min(contentWidth, proposed.width) }
        return super.lineFragmentRect(forProposedRect: proposed, at: characterIndex,
                                      writingDirection: baseWritingDirection, remaining: remainingRect)
    }
}


private final class SourceScrollView: NSScrollView {
    /// Pinch does nothing: the sheet scale is fixed by the panel width (F2-R07).
    override func magnify(with event: NSEvent) {}
    override func smartMagnify(with event: NSEvent) {}
}


/// Finds the punctuation the editor hides when «Ocultar signos de Markdown» is on: heading and
/// quote markers, emphasis and code delimiters, and link or image syntax around the visible
/// text. Lists keep their markers (they are content), and fenced code blocks are left alone.
enum MarkdownSyntax {
    static func punctuation(in text: String) -> IndexSet {
        let source = text as NSString
        var result = IndexSet()
        var fence: String?
        source.enumerateSubstrings(in: NSRange(location: 0, length: source.length), options: [.byLines, .substringNotRequired]) { _, line, _, _ in
            let value = source.substring(with: line)
            let trimmed = value.drop(while: { $0 == " " || $0 == "\t" })
            if let marker = trimmed.first, marker == "`" || marker == "~",
               trimmed.prefix(while: { $0 == marker }).count >= 3 {
                let token = String(trimmed.prefix(while: { $0 == marker }))
                if fence == nil { fence = token } else if token.hasPrefix(fence!) { fence = nil }
                return
            }
            guard fence == nil else { return }
            for (pattern, groups) in rules {
                for match in pattern.matches(in: value, range: NSRange(location: 0, length: (value as NSString).length)) {
                    for group in groups {
                        let range = match.range(at: group)
                        guard range.location != NSNotFound, range.length > 0 else { continue }
                        result.insert(integersIn: (line.location + range.location)..<(line.location + NSMaxRange(range)))
                    }
                }
            }
        }
        return result
    }

    /// Each rule lists the capture groups that are punctuation.
    private static let rules: [(NSRegularExpression, [Int])] = [
        (#"^( {0,3}#{1,6}[ \t]+)"#, [1]),
        (#"^( {0,3}>[ \t]?)"#, [1]),
        (#"(!?\[)[^\]\n]+(\]\([^)\n]*\))"#, [1, 2]),
        (#"(`)[^`\n]+(`)"#, [1, 2]),
        (#"(\*\*|__)(?=\S)[^\n]*?(?<=\S)(\1)"#, [1, 2]),
        (#"(~~)(?=\S)[^\n]*?(?<=\S)(~~)"#, [1, 2]),
        (#"(?<![\*\w])(\*)(?=[^\s\*])[^\n\*]*?(?<=[^\s\*])(\*)(?!\*)"#, [1, 2]),
        (#"(?<![_\w])(_)(?=[^\s_])[^\n_]*?(?<=[^\s_])(_)(?![_\w])"#, [1, 2]),
    ].map { (try! NSRegularExpression(pattern: $0.0, options: [.anchorsMatchLines]), $0.1) }
}
