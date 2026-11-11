import SwiftUI
import AppKit

struct QuickActionsBar: View {
    @EnvironmentObject private var store: Store
    @Environment(\.theme) private var t
    @State private var editing: QuickAction?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(store.actions) { a in
                    ActionChip(action: a)
                        .contextMenu {
                            Button("Edit") { editing = a }
                            Button("Move Left") { withAnimation(.spring) { store.moveAction(a.id, by: -1) } }
                            Button("Move Right") { withAnimation(.spring) { store.moveAction(a.id, by: 1) } }
                            Divider()
                            Button("Delete", role: .destructive) { withAnimation(.spring) { store.deleteAction(a.id) } }
                        }
                }
                AddChip { editing = QuickAction(title: "", url: "", icon: "link") }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.never)
        .sheet(item: $editing) { a in
            ActionEditor(action: a, isNew: !store.actions.contains { $0.id == a.id })
        }
    }
}

struct ActionChip: View {
    @Environment(\.theme) private var t
    let action: QuickAction
    @State private var hover = false

    var body: some View {
        Button {
            if let url = action.resolvedURL { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: 7) {
                FAIcon(action.icon, size: 11).foregroundStyle(hover ? t.accent : t.muted)
                Text(action.title).font(.mono(11.5, .medium)).lineLimit(1)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(hover ? t.raised : t.panel))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(hover ? t.accent.opacity(0.45) : t.border, lineWidth: 1))
            .offset(y: hover ? -1 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .help(action.url)
    }
}

struct AddChip: View {
    @Environment(\.theme) private var t
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                FAIcon("plus", size: 10)
                Text("action").font(.mono(11.5))
            }
            .foregroundStyle(hover ? t.accent : t.faint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(hover ? t.accent.opacity(0.5) : t.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("add a quick action")
    }
}

struct ActionEditor: View {
    @EnvironmentObject private var store: Store
    @Environment(\.theme) private var t
    @Environment(\.dismiss) private var dismiss
    @State private var draft: QuickAction
    @State private var query = ""
    let isNew: Bool

    init(action: QuickAction, isNew: Bool) {
        _draft = State(initialValue: action)
        self.isNew = isNew
    }

    private var valid: Bool {
        !draft.title.trimmingCharacters(in: .whitespaces).isEmpty && draft.resolvedURL != nil
    }

    private var icons: [FAEntry] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        let list = q.isEmpty ? FA.entries : FA.entries.filter { $0.names.contains { $0.contains(q) } }
        return Array(list.prefix(420))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                FAIcon(draft.icon, size: 16)
                    .foregroundStyle(t.accentInk)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 8).fill(t.accent))
                VStack(alignment: .leading, spacing: 2) {
                    Text(isNew ? "new quick action" : "edit quick action").font(.mono(14, .bold))
                    Text("a button that opens a link, app url or file").font(.mono(11)).foregroundStyle(t.muted)
                }
            }

            Field(label: "title", text: $draft.title, prompt: "Jira board")
            Field(label: "url", text: $draft.url, prompt: "https://...  vscode://...  file:///...")

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("icon").font(.mono(11)).foregroundStyle(t.muted)
                    Text("fa-\(draft.icon)").font(.mono(11)).foregroundStyle(t.accent)
                    Spacer()
                    Text("\(FA.entries.count) solid icons").font(.mono(10)).foregroundStyle(t.faint)
                }
                HStack(spacing: 8) {
                    FAIcon("magnifying-glass", size: 10).foregroundStyle(t.faint)
                    TextField("", text: $query, prompt: Text("search icons (e.g. bug, rocket, server)").foregroundStyle(t.faint))
                        .textFieldStyle(.plain).font(.mono(12))
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 7).fill(t.bg))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(t.border))

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 34, maximum: 40), spacing: 6)], spacing: 6) {
                        ForEach(icons) { e in
                            let sel = draft.icon == e.name
                            Button { draft.icon = e.name } label: {
                                FAIcon(e.name, size: 14)
                                    .foregroundStyle(sel ? t.accentInk : t.text)
                                    .frame(width: 34, height: 34)
                                    .background(RoundedRectangle(cornerRadius: 7).fill(sel ? t.accent : t.panel))
                                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(sel ? t.accent : t.border))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(e.name)
                        }
                    }
                    .padding(2)
                }
                .frame(height: 210)
            }

            HStack {
                if !isNew {
                    Button("delete") {
                        store.deleteAction(draft.id)
                        dismiss()
                    }
                    .buttonStyle(.plain).font(.mono(12)).foregroundStyle(t.danger)
                }
                Spacer()
                Button("cancel") { dismiss() }
                    .buttonStyle(.plain).font(.mono(12)).foregroundStyle(t.muted)
                    .keyboardShortcut(.cancelAction)
                    .padding(.trailing, 10)
                Button {
                    draft.title = draft.title.trimmingCharacters(in: .whitespaces)
                    draft.url = draft.url.trimmingCharacters(in: .whitespaces)
                    withAnimation(.spring) { store.upsert(draft) }
                    dismiss()
                } label: {
                    Text("save").font(.mono(12, .bold))
                        .foregroundStyle(t.accentInk)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 7).fill(t.accent))
                        .opacity(valid ? 1 : 0.4)
                }
                .buttonStyle(.plain)
                .disabled(!valid)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 480)
        .background(t.panel)
        .foregroundStyle(t.text)
    }
}

private struct Field: View {
    @Environment(\.theme) private var t
    let label: String
    @Binding var text: String
    let prompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.mono(11)).foregroundStyle(t.muted)
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(t.faint))
                .textFieldStyle(.plain)
                .font(.mono(12.5))
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 7).fill(t.bg))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(t.border))
        }
    }
}
