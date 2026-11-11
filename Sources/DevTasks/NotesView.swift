import SwiftUI
import AppKit

struct NotesView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.theme) private var t

    private var current: Note? {
        store.notes.first { $0.id == store.selectedNote } ?? store.notes.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("~/notes").font(.mono(26, .bold))
                Text("scratchpad").font(.mono(12)).foregroundStyle(t.muted)
                Spacer()
                Text("\(store.notes.count) note\(store.notes.count == 1 ? "" : "s")").font(.mono(11.5)).foregroundStyle(t.muted)
                Button { withAnimation(.spring(response: 0.3)) { _ = store.newNote() } } label: {
                    HStack(spacing: 6) {
                        FAIcon("plus", size: 10)
                        Text("new note").font(.mono(11.5, .medium))
                    }
                    .foregroundStyle(t.accentInk)
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 7).fill(t.accent))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .handCursor()
                .help("new note (\u{2318}\u{21E7}N)")
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 16)

            if store.notes.isEmpty {
                VStack(spacing: 12) {
                    FAIcon("note-sticky", size: 30).foregroundStyle(t.faint)
                    Text("$ touch ~/notes/idea.md").font(.mono(12)).foregroundStyle(t.muted)
                    Text("no notes yet. press \u{2318}\u{21E7}N for a new one.").font(.mono(11)).foregroundStyle(t.faint)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
                Spacer()
            } else {
                HStack(alignment: .top, spacing: 12) {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(store.notes) { n in
                                NoteCard(note: n, selected: n.id == current?.id) { store.selectedNote = n.id }
                                    .contextMenu {
                                        Button("Copy") { LinkFormat.copy(n.text) }
                                        Divider()
                                        Button("Delete", role: .destructive) {
                                            withAnimation(.spring(response: 0.3)) { store.deleteNote(n.id) }
                                        }
                                    }
                            }
                        }
                    }
                    .scrollIndicators(.never)
                    .frame(width: 240 * UIScale.factor)

                    if let note = current {
                        NoteDetail(note: note)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }
        }
    }
}

private struct NoteCard: View {
    @Environment(\.theme) private var t
    let note: Note
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(note.title).font(.mono(12.5, .semibold)).foregroundStyle(selected ? t.text : t.text.opacity(0.85)).lineLimit(1)
                if !note.preview.isEmpty {
                    Text(note.preview).font(.mono(11)).foregroundStyle(t.muted).lineLimit(1)
                }
                Text(note.updatedAt, format: .relative(presentation: .named)).font(.mono(9.5)).foregroundStyle(t.faint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 9).fill(selected ? t.raised : hover ? t.raised.opacity(0.6) : t.panel))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? t.accent.opacity(0.5) : t.border))
            .overlay(alignment: .leading) {
                if selected { RoundedRectangle(cornerRadius: 2).fill(t.accent).frame(width: 3, height: 18).offset(x: -1) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .handCursor()
        .onHover { hover = $0 }
    }
}

private struct NoteDetail: View {
    @EnvironmentObject private var store: Store
    @Environment(\.theme) private var t
    let note: Note
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                FAIcon("note-sticky", size: 10).foregroundStyle(t.faint)
                Text("edited ").font(.mono(10.5)).foregroundStyle(t.faint)
                    + Text(note.updatedAt, format: .relative(presentation: .named)).font(.mono(10.5)).foregroundStyle(t.faint)
                Spacer()
                HoverIconButton(icon: copied ? "check" : "copy", hoverColor: t.accent, help: "copy note (keeps links)") {
                    LinkFormat.copy(note.text)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                }
                HoverIconButton(icon: "trash-can", hoverColor: t.danger, help: "delete note") {
                    withAnimation(.spring(response: 0.3)) { store.deleteNote(note.id) }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .overlay(alignment: .bottom) { Rectangle().fill(t.border).frame(height: 1) }

            NoteEditor(text: store.noteBinding(note.id), color: t.text, accent: t.accent, focus: note.text.isEmpty)
                .id(note.id)
        }
        .background(RoundedRectangle(cornerRadius: 9).fill(t.panel))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(t.border))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

/// Plain-text note editor: clickable links, rich paste keeps embedded links as [text](url).
struct NoteEditor: NSViewRepresentable {
    @Binding var text: String
    let color: Color
    let accent: Color
    var focus = false

    private var font: NSFont { .monospacedSystemFont(ofSize: 13 * UIScale.factor, weight: .regular) }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let tv = NoteTextView(usingTextLayoutManager: false)
        tv.delegate = context.coordinator
        tv.isRichText = true          // needed for clickable link attributes; paste is forced to plain
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.textContainerInset = NSSize(width: 12, height: 12)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        context.coordinator.style(tv)
        tv.string = text
        context.coordinator.relink(tv)

        let sv = NSScrollView()
        sv.documentView = tv
        sv.hasVerticalScroller = true
        sv.autohidesScrollers = true
        sv.drawsBackground = false
        sv.scrollerStyle = .overlay
        if focus {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { tv.window?.makeFirstResponder(tv) }
        }
        return sv
    }

    func updateNSView(_ sv: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = sv.documentView as? NoteTextView else { return }
        context.coordinator.style(tv)
        if tv.string != text {
            tv.string = text
            context.coordinator.relink(tv)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteEditor
        private var styleKey = ""
        init(_ p: NoteEditor) { parent = p }

        var base: [NSAttributedString.Key: Any] {
            let para = NSMutableParagraphStyle()
            para.lineSpacing = 3
            return [.font: parent.font, .foregroundColor: NSColor(parent.color), .paragraphStyle: para]
        }

        func style(_ tv: NSTextView) {
            let key = "\(parent.color)|\(parent.accent)|\(parent.font.pointSize)"
            guard key != styleKey else { return }
            styleKey = key
            tv.font = parent.font
            tv.textColor = NSColor(parent.color)
            tv.insertionPointColor = NSColor(parent.accent)
            tv.selectedTextAttributes = [.backgroundColor: NSColor(parent.accent).withAlphaComponent(0.28)]
            tv.linkTextAttributes = [
                .foregroundColor: NSColor(parent.accent),
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .cursor: NSCursor.pointingHand,
            ]
            relink(tv)
        }

        /// Restyles the whole note and marks URLs (bare or inside [text](url)) as links.
        func relink(_ tv: NSTextView) {
            guard let ts = tv.textStorage else { return }
            let full = NSRange(location: 0, length: ts.length)
            ts.beginEditing()
            ts.setAttributes(base, range: full)
            for (r, u) in LinkFormat.linkRanges(ts.string) { ts.addAttribute(.link, value: u, range: r) }
            ts.endEditing()
            tv.typingAttributes = base
        }

        func textDidChange(_ n: Notification) {
            guard let tv = n.object as? NSTextView else { return }
            relink(tv)
            if parent.text != tv.string { parent.text = tv.string }
        }
    }
}

final class NoteTextView: NSTextView {
    /// Never import formatting: embedded links become [text](url), everything else is plain text.
    override func paste(_ sender: Any?) {
        if let md = LinkFormat.fromPasteboard() {
            insertText(md, replacementRange: selectedRange())
        } else if let s = NSPasteboard.general.string(forType: .string) {
            insertText(s, replacementRange: selectedRange())
        }
    }

    override func copy(_ sender: Any?) {
        let sel = selectedRange()
        guard sel.length > 0 else { return super.copy(sender) }
        LinkFormat.copy((string as NSString).substring(with: sel))
    }
}
