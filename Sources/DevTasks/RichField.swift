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

enum LinkFormat {
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func matches(_ s: String) -> [NSTextCheckingResult] {
        detector?.matches(in: s, range: NSRange(location: 0, length: (s as NSString).length)) ?? []
    }

    /// "https://github.com/acme/api/pull/412" -> "github.com/…/pull/412"
    static func shortLabel(_ url: URL, original: String) -> String {
        var label: String
        if let host = url.host {
            let h = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            let comps = url.path.split(separator: "/").map(String.init)
            if comps.isEmpty { label = h }
            else if comps.count <= 2 { label = h + "/" + comps.joined(separator: "/") }
            else { label = h + "/\u{2026}/" + comps.suffix(2).joined(separator: "/") }
        } else {
            label = original
        }
        if label.count > 48 { label = String(label.prefix(45)) + "\u{2026}" }
        return label
    }

    private static func segments(_ s: String) -> [(text: String, url: URL?)] {
        let ns = s as NSString
        var out: [(String, URL?)] = []
        var cursor = 0
        for m in matches(s) {
            guard let url = m.url else { continue }
            if m.range.location > cursor {
                out.append((ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor)), nil))
            }
            out.append((shortLabel(url, original: ns.substring(with: m.range)), url))
            cursor = NSMaxRange(m.range)
        }
        if cursor < ns.length { out.append((ns.substring(from: cursor), nil)) }
        return out
    }

    static func display(_ s: String, base: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for seg in segments(s) {
            var a = base
            if let u = seg.url { a[.link] = u }
            out.append(NSAttributedString(string: seg.text, attributes: a))
        }
        return out
    }

    /// Text with URLs replaced by their short labels (for read-only SwiftUI Text).
    static func plain(_ s: String) -> String { segments(s).map(\.text).joined() }
}

final class LinkTextView: NSTextView {
    var inline = false
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
    var controller: FieldController? = nil
    /// Autocomplete options for the current @token (empty hides the menu).
    var suggestions: [String] = []
    /// Drop focus after Enter (titles) vs keep typing (input bars).
    var endsOnSubmit = true
    var onSubmit: (() -> Void)? = nil
    var onFocus: ((Bool) -> Void)? = nil

    private var font: NSFont { .monospacedSystemFont(ofSize: size, weight: .regular) }

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
        tv.inline = inline
        tv.fullText = text
        applyStyle(tv, context.coordinator)
        if inline { tv.showDisplay() } else { tv.string = text }
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
        let key = "\(color)|\(accent)|\(size)"
        guard key != c.styleKey else { return false }
        c.styleKey = key
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 2
        let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(color), .paragraphStyle: para]
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
