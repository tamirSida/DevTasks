import SwiftUI
import AppKit

// A small NSTextView-based field:
//  - Enter submits, Shift+Enter (or Option+Enter) inserts a new line
//  - grows vertically with its content
//  - "inline" mode shows URLs as short clickable links until you click to edit
//  - optional @-token autocomplete driven by a FieldController

final class FieldController: ObservableObject {
    weak var textView: LinkTextView?
    /// The @word currently under the cursor, e.g. "@to".
    @Published var token: String?
    @Published var selected = 0
    var tokenRange = NSRange(location: NSNotFound, length: 0)

    func focus() {
        DispatchQueue.main.async { [weak self] in
            guard let tv = self?.textView, let w = tv.window else { return }
            if tv.inline { tv.enterEditing() }
            w.makeFirstResponder(tv)
            tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
        }
    }

    func complete(_ replacement: String) {
        guard let tv = textView, tokenRange.location != NSNotFound,
              NSMaxRange(tokenRange) <= (tv.string as NSString).length else { return }
        tv.window?.makeFirstResponder(tv)
        tv.insertText(replacement + " ", replacementRange: tokenRange)
    }
}

final class LinkTextView: NSTextView {
    var inline = false
    /// Display only (done items): links open, other clicks do nothing.
    var readOnly = false
    private(set) var editingMode = true
    var fullText = ""
    var baseAttributes: [NSAttributedString.Key: Any] = [:]
    var onFocusChange: ((Bool) -> Void)?

    func showDisplay() {
        editingMode = false
        isEditable = false
        textStorage?.setAttributedString(LinkFormat.display(fullText, base: baseAttributes))
        invalidateIntrinsicContentSize()
    }

    func enterEditing() {
        guard !editingMode else { return }
        editingMode = true
        isEditable = true
        textStorage?.setAttributedString(NSAttributedString(string: fullText, attributes: baseAttributes))
        typingAttributes = baseAttributes
        invalidateIntrinsicContentSize()
    }

    override func mouseDown(with event: NSEvent) {
        guard inline, !editingMode, let lm = layoutManager, let tc = textContainer else {
            super.mouseDown(with: event)
            return
        }
        let p = convert(event.locationInWindow, from: nil)
        let pt = NSPoint(x: p.x - textContainerOrigin.x, y: p.y - textContainerOrigin.y)
        var frac: CGFloat = 0
        let g = lm.glyphIndex(for: pt, in: tc, fractionOfDistanceThroughGlyph: &frac)
        let onGlyph = lm.boundingRect(forGlyphRange: NSRange(location: g, length: 1), in: tc).contains(pt)
        let idx = lm.characterIndexForGlyph(at: g)
        if onGlyph, idx < (textStorage?.length ?? 0), textStorage?.attribute(.link, at: idx, effectiveRange: nil) != nil {
            super.mouseDown(with: event) // opens the link
            return
        }
        if readOnly { return }
        let samePositions = (textStorage?.string ?? "") == fullText
        enterEditing()
        window?.makeFirstResponder(self)
        let len = (string as NSString).length
        var caret = len
        if samePositions && onGlyph { caret = min(idx + (frac > 0.5 ? 1 : 0), len) }
        setSelectedRange(NSRange(location: caret, length: 0))
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok && editingMode { onFocusChange?(true) }
        return ok
    }

    /// Rich paste: embedded links (Azure DevOps titles, Teams, browsers) become [text](url).
    override func paste(_ sender: Any?) {
        if editingMode, let md = LinkFormat.fromPasteboard() {
            insertText(md, replacementRange: selectedRange())
            return
        }
        super.paste(sender)
    }

    /// Copying text with links puts real embedded links on the clipboard.
    override func copy(_ sender: Any?) {
        let sel = selectedRange()
        guard sel.length > 0, let ts = textStorage else { return super.copy(sender) }
        if editingMode {
            LinkFormat.copy((string as NSString).substring(with: sel))
        } else if let md = LinkFormat.markdown(from: ts.attributedSubstring(from: sel)) {
            LinkFormat.copy(md)
        } else {
            super.copy(sender)
        }
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok {
            if inline && editingMode { showDisplay() }
            onFocusChange?(false)
        }
        return ok
    }
}

struct RichField: NSViewRepresentable {
    @Binding var text: String
    var size: CGFloat = 13
    var color: Color
    var accent: Color
    /// Show short clickable links when not editing (task titles). Off for input bars.
    var inline = false
    var readOnly = false
    var strike = false
    var controller: FieldController? = nil
    /// Autocomplete options for the current @token (empty hides the menu).
    var suggestions: [String] = []
    /// Drop focus after Enter (titles) vs keep typing (input bars).
    var endsOnSubmit = true
    var onSubmit: (() -> Void)? = nil
    var onFocus: ((Bool) -> Void)? = nil

    private var font: NSFont { .monospacedSystemFont(ofSize: size * UIScale.factor, weight: .regular) }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> LinkTextView {
        let tv = LinkTextView(usingTextLayoutManager: false)
        tv.delegate = context.coordinator
        tv.drawsBackground = false
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = true
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable = false
        tv.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tv.inline = inline || readOnly
        tv.readOnly = readOnly
        tv.fullText = text
        applyStyle(tv, context.coordinator)
        if inline || readOnly { tv.showDisplay() } else { tv.string = text }
        tv.onFocusChange = { [weak coordinator = context.coordinator] f in coordinator?.parent.onFocus?(f) }
        controller?.textView = tv
        return tv
    }

    func updateNSView(_ tv: LinkTextView, context: Context) {
        context.coordinator.parent = self
        controller?.textView = tv
        let restyle = applyStyle(tv, context.coordinator)
        if tv.editingMode {
            if tv.string != text {
                tv.string = text
                tv.fullText = text
                tv.invalidateIntrinsicContentSize()
            } else if restyle, let ts = tv.textStorage {
                ts.setAttributes(tv.baseAttributes, range: NSRange(location: 0, length: ts.length))
            }
        } else if tv.fullText != text || restyle {
            tv.fullText = text
            tv.showDisplay()
        }
    }

    /// Returns true when colors/size changed and existing text needs restyling.
    @discardableResult
    private func applyStyle(_ tv: LinkTextView, _ c: Coordinator) -> Bool {
        let key = "\(color)|\(accent)|\(font.pointSize)|\(strike)"
        guard key != c.styleKey else { return false }
        c.styleKey = key
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 2
        var base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(color), .paragraphStyle: para]
        if strike {
            base[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            base[.strikethroughColor] = NSColor(color)
        }
        tv.baseAttributes = base
        tv.typingAttributes = base
        tv.font = font
        tv.insertionPointColor = NSColor(accent)
        tv.selectedTextAttributes = [.backgroundColor: NSColor(accent).withAlphaComponent(0.28)]
        tv.linkTextAttributes = [
            .foregroundColor: NSColor(accent),
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ]
        return true
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView tv: LinkTextView, context: Context) -> CGSize? {
        guard let lm = tv.layoutManager, let tc = tv.textContainer else { return nil }
        let w = proposal.width ?? .infinity
        let target = w.isFinite ? max(w, 1) : 100_000
        tc.containerSize = NSSize(width: target, height: .greatestFiniteMagnitude)
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc)
        let lineH = lm.defaultLineHeight(for: font)
        tc.containerSize = NSSize(width: tv.bounds.width > 0 ? tv.bounds.width : target, height: .greatestFiniteMagnitude)
        let width = w.isFinite ? w : ceil(used.width) + 2
        return CGSize(width: width, height: ceil(max(used.height, lineH)))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichField
        var styleKey = ""
        init(_ p: RichField) { parent = p }

        func textDidChange(_ n: Notification) {
            guard let tv = n.object as? LinkTextView, tv.editingMode else { return }
            tv.fullText = tv.string
            if parent.text != tv.string { parent.text = tv.string }
            tv.invalidateIntrinsicContentSize()
            updateToken(tv)
        }

        func textViewDidChangeSelection(_ n: Notification) {
            guard let tv = n.object as? LinkTextView, tv.editingMode else { return }
            updateToken(tv)
        }

        private func updateToken(_ tv: LinkTextView) {
            guard let c = parent.controller else { return }
            let sel = tv.selectedRange()
            let ns = tv.string as NSString
            var tok: String?
            var range = NSRange(location: NSNotFound, length: 0)
            if sel.length == 0, sel.location <= ns.length {
                var start = sel.location
                while start > 0 {
                    let ch = ns.character(at: start - 1)
                    if let u = UnicodeScalar(ch), CharacterSet.whitespacesAndNewlines.contains(u) { break }
                    start -= 1
                }
                let word = ns.substring(with: NSRange(location: start, length: sel.location - start))
                if word.hasPrefix("@") {
                    tok = word
                    range = NSRange(location: start, length: sel.location - start)
                }
            }
            c.tokenRange = range
            if c.token != tok {
                c.token = tok
                c.selected = 0
            }
        }

        func textView(_ tv: NSTextView, doCommandBy sel: Selector) -> Bool {
            let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
            let s = parent.suggestions

            if !s.isEmpty, let c = parent.controller {
                if sel == #selector(NSResponder.moveDown(_:)) { c.selected = (c.selected + 1) % s.count; return true }
                if sel == #selector(NSResponder.moveUp(_:)) { c.selected = (c.selected - 1 + s.count) % s.count; return true }
                if sel == #selector(NSResponder.insertTab(_:)) || (sel == #selector(NSResponder.insertNewline(_:)) && !shift) {
                    c.complete(s[min(c.selected, s.count - 1)])
                    return true
                }
                if sel == #selector(NSResponder.cancelOperation(_:)) { c.token = nil; return true }
            }

            switch sel {
            case #selector(NSResponder.insertNewline(_:)):
                if shift {
                    tv.insertNewlineIgnoringFieldEditor(nil)
                } else {
                    parent.onSubmit?()
                    if parent.endsOnSubmit { tv.window?.makeFirstResponder(nil) }
                }
                return true
            case #selector(NSResponder.insertLineBreak(_:)):
                tv.insertNewlineIgnoringFieldEditor(nil)
                return true
            case #selector(NSResponder.insertTab(_:)):
                tv.window?.selectNextKeyView(nil)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                tv.window?.selectPreviousKeyView(nil)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                tv.window?.makeFirstResponder(nil)
                return true
            default:
                return false
            }
        }
    }
}

/// Clicking anywhere outside a task title that is being edited ends editing.
enum OutsideClick {
    private static var monitor: Any?

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { e in
            if let w = e.window, let tv = w.firstResponder as? LinkTextView, tv.inline, tv.editingMode {
                let p = tv.convert(e.locationInWindow, from: nil)
                if !tv.bounds.contains(p) { w.makeFirstResponder(nil) }
            }
            return e
        }
    }
}

extension View {
    /// Pointing-hand cursor while hovering (macOS shows an arrow over buttons by default).
    func handCursor() -> some View {
        onContinuousHover { phase in
            switch phase {
            case .active: NSCursor.pointingHand.set()
            case .ended: NSCursor.arrow.set()
            }
        }
    }
}
