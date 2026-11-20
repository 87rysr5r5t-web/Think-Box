import AppKit
import SwiftUI

struct TextReveal: Equatable {
    let id = UUID()
    let range: NSRange
}

struct MarkdownSurface: NSViewRepresentable {
    var text: String
    var editable: Bool
    var taggable: Bool
    var options: EditorOptions
    var reveal: TextReveal?
    var onEdit: (String, NSRange, Int) -> Void
    var onSelect: (NSRange) -> Void
    var fragmentAction: (NSRange, Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let editor = Editor(frame: scroll.contentView.bounds)
        editor.autoresizingMask = [.width]
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.minSize = NSSize(width: 0, height: scroll.contentView.bounds.height)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: scroll.contentView.bounds.width, height: .greatestFiniteMagnitude)
        editor.textContainerInset = NSSize(width: 0, height: 12)
        editor.isRichText = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.setAccessibilityLabel("Contenido en Markdown")
        editor.string = text
        applyOptions(to: editor, in: scroll)
        context.coordinator.appliedOptions = options
        editor.delegate = context.coordinator
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? Editor else { return }
        context.coordinator.parent = self
        editor.isEditable = editable
        editor.fragmentAction = taggable ? fragmentAction : nil
        let replacedText = editor.string != text
        if replacedText { editor.string = text }
        if replacedText || context.coordinator.appliedOptions != options {
            applyOptions(to: editor, in: scroll)
            context.coordinator.appliedOptions = options
        }
        if let reveal, context.coordinator.lastReveal != reveal.id {
            context.coordinator.lastReveal = reveal.id
            editor.window?.makeFirstResponder(editor)
            editor.setSelectedRange(reveal.range)
            editor.scrollRangeToVisible(reveal.range)
        }
    }

    private func applyOptions(to editor: NSTextView, in scroll: NSScrollView) {
        let font = AppFonts.editorFont(options.font, size: CGFloat(options.fontSize))
        let color = options.customColors ? options.ink.native : .labelColor
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = CGFloat(options.lineSpacing)
        paragraph.lineBreakMode = options.wrapLines ? .byWordWrapping : .byClipping
        editor.font = font
        editor.textColor = color
        editor.insertionPointColor = color
        editor.defaultParagraphStyle = paragraph
        editor.typingAttributes = [.font: font, .paragraphStyle: paragraph, .foregroundColor: color]
        if let storage = editor.textStorage, storage.length > 0 {
            storage.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: storage.length))
        }
        scroll.hasHorizontalScroller = !options.wrapLines
        editor.isHorizontallyResizable = !options.wrapLines
        editor.autoresizingMask = options.wrapLines ? [.width] : []
        if options.wrapLines { editor.setFrameSize(NSSize(width: scroll.contentSize.width, height: editor.frame.height)) }
        editor.textContainer?.widthTracksTextView = options.wrapLines
        editor.textContainer?.containerSize = NSSize(width: options.wrapLines ? scroll.contentSize.width : .greatestFiniteMagnitude,
                                                     height: .greatestFiniteMagnitude)
        editor.isContinuousSpellCheckingEnabled = options.spellCheck
        editor.isGrammarCheckingEnabled = options.spellCheck && options.grammarCheck
        editor.isAutomaticSpellingCorrectionEnabled = options.autoCorrect
        editor.isAutomaticQuoteSubstitutionEnabled = options.smartQuotes
        editor.isAutomaticDashSubstitutionEnabled = options.smartDashes
        editor.smartInsertDeleteEnabled = options.smartCopyPaste
        editor.isAutomaticTextReplacementEnabled = options.textReplacement
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownSurface
        var lastReveal: UUID?
        var appliedOptions: EditorOptions?
        private var edit: (NSRange, Int)?

        init(_ parent: MarkdownSurface) { self.parent = parent }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            edit = replacementString.map { (affectedCharRange, $0.utf16.count) }
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            if let (range, length) = edit, range.location != NSNotFound,
               parent.text.utf16.count - range.length + length == editor.string.utf16.count {
                parent.onEdit(editor.string, range, length)
            } else {
                let original = Array(parent.text.utf16)
                let updated = Array(editor.string.utf16)
                let prefix = zip(original, updated).prefix { $0 == $1 }.count
                let suffix = zip(original.dropFirst(prefix).reversed(), updated.dropFirst(prefix).reversed())
                    .prefix { $0 == $1 }.count
                parent.onEdit(editor.string, NSRange(location: prefix, length: original.count - prefix - suffix),
                              updated.count - prefix - suffix)
            }
            edit = nil
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            if let editor = notification.object as? NSTextView {
                let range = editor.selectedRange()
                Task { @MainActor in parent.onSelect(range) }
            }
        }
    }

    final class Editor: NSTextView {
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
