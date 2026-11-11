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
                    Group {
                        if a.isFolder { FolderChip(folder: a, edit: { editing = a }) } else { ActionChip(action: a) }
                    }
                    .contextMenu {
                        Button("Edit") { editing = a }
                        if !a.isFolder {
                            let folders = store.actions.filter(\.isFolder)
                            if !folders.isEmpty {
                                Menu("Move Into Folder") {
                                    ForEach(folders) { f in
                                        Button(f.title) { withAnimation(.spring) { store.moveAction(a.id, intoFolder: f.id) } }
                                    }
                                }
                            }
                        }
                        Button("Move Left") { withAnimation(.spring) { store.moveAction(a.id, by: -1) } }
                        Button("Move Right") { withAnimation(.spring) { store.moveAction(a.id, by: 1) } }
                        Divider()
                        Button("Delete", role: .destructive) { withAnimation(.spring) { store.deleteAction(a.id) } }
                    }
                }
                AddChip(
                    newLink: { editing = QuickAction(title: "", url: "", icon: "link") },
                    newFolder: { editing = QuickAction(title: "", url: "", icon: "folder", children: [QuickAction(title: "", url: "", icon: "link")]) }
                )
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.never)
        .sheet(item: $editing) { a in
            ThemeProvider(translucent: false) {
                ActionEditor(action: a, isNew: !store.actions.contains { $0.id == a.id })
            }
            .environmentObject(store)
        }
    }
}

private func open(_ a: QuickAction) {
    if let url = a.resolvedURL { NSWorkspace.shared.open(url) }
}

struct ChipLabel: View {
    @Environment(\.theme) private var t
    let icon: String
    let title: String
    var folder = false
    let hover: Bool
    var open = false

    var body: some View {
        HStack(spacing: 7) {
            FAIcon(icon, size: 11).foregroundStyle(hover || open ? t.accent : t.muted)
            Text(title).font(.mono(11.5, .medium)).lineLimit(1)
            if folder {
                FAIcon("chevron-down", size: 8).foregroundStyle(t.faint).rotationEffect(.degrees(open ? 180 : 0))
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(hover || open ? t.raised : t.panel))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(hover || open ? t.accent.opacity(0.45) : t.border, lineWidth: 1))
        .offset(y: hover ? -1 : 0)
        .contentShape(Rectangle())
    }
}

struct ActionChip: View {
    let action: QuickAction
    @State private var hover = false

    var body: some View {
        Button { open(action) } label: {
            ChipLabel(icon: action.icon, title: action.title, hover: hover)
        }
        .buttonStyle(.plain)
        .handCursor()
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .help(action.url)
    }
}

struct FolderChip: View {
    @Environment(\.theme) private var t
    let folder: QuickAction
    let edit: () -> Void
    @State private var hover = false
    @State private var show = false

    var body: some View {
        Button { show.toggle() } label: {
            ChipLabel(icon: folder.icon, title: folder.title, folder: true, hover: hover, open: show)
        }
        .buttonStyle(.plain)
        .handCursor()
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .popover(isPresented: $show, arrowEdge: .bottom) {
            ThemeProvider(translucent: false) {
                FolderMenu(folder: folder, close: { show = false }, edit: { show = false; edit() })
            }
        }
    }
}

struct FolderMenu: View {
    @Environment(\.theme) private var t
    let folder: QuickAction
    let close: () -> Void
    let edit: () -> Void

    var body: some View {
        let links = folder.children ?? []
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(folder.title.lowercased()).padding(.horizontal, 8).padding(.bottom, 4)
            if links.isEmpty {
                Text("empty folder").font(.mono(11)).foregroundStyle(t.faint).padding(8)
            }
            ForEach(links) { l in
                Button { open(l); close() } label: {
                    HStack(spacing: 10) {
                        FAIcon(l.icon, size: 11).foregroundStyle(t.accent).frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(l.title).font(.mono(12)).foregroundStyle(t.text)
                            Text(l.resolvedURL?.host ?? l.url).font(.mono(9.5)).foregroundStyle(t.faint).lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PopoverRowStyle())
                .help(l.url)
            }
            Divider().padding(.vertical, 4)
            HStack {
                if links.count > 1 {
                    Button { links.forEach(open); close() } label: {
                        HStack(spacing: 6) { FAIcon("arrow-up-right-from-square", size: 9); Text("open all").font(.mono(11)) }
                    }
                    .buttonStyle(.plain)
        .handCursor().foregroundStyle(t.muted)
                }
                Spacer()
                Button(action: edit) {
                    HStack(spacing: 6) { FAIcon("pen", size: 9); Text("edit").font(.mono(11)) }
                }
                .buttonStyle(.plain)
        .handCursor().foregroundStyle(t.muted)
            }
            .padding(.horizontal, 8)
        }
        .padding(8)
        .frame(width: 250)
        .background(t.panel)
        .foregroundStyle(t.text)
    }
}

struct AddChip: View {
    @Environment(\.theme) private var t
    let newLink: () -> Void
    let newFolder: () -> Void
    @State private var hover = false
    @State private var show = false

    var body: some View {
        Button { show.toggle() } label: {
            HStack(spacing: 6) {
                FAIcon("plus", size: 10)
                Text("action").font(.mono(11.5))
            }
            .foregroundStyle(hover || show ? t.accent : t.faint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(hover || show ? t.accent.opacity(0.5) : t.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .handCursor()
        .onHover { hover = $0 }
        .help("add a link or a folder of links")
        .popover(isPresented: $show, arrowEdge: .bottom) {
            ThemeProvider(translucent: false) {
                AddMenu(pickLink: { show = false; newLink() }, pickFolder: { show = false; newFolder() })
            }
        }
    }
}

private struct AddMenu: View {
    @Environment(\.theme) private var t
    let pickLink: () -> Void
    let pickFolder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            row("link", "link", "a button that opens a url", pickLink)
            row("folder-open", "folder", "a dropdown of links", pickFolder)
        }
        .padding(6)
        .frame(width: 230)
        .background(t.panel)
        .foregroundStyle(t.text)
    }

    private func row(_ icon: String, _ title: String, _ sub: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                FAIcon(icon, size: 12).foregroundStyle(t.accent).frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.mono(12, .medium))
                    Text(sub).font(.mono(10)).foregroundStyle(t.faint)
                }
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PopoverRowStyle())
    }
}

// MARK: - Editor

struct ActionEditor: View {
    @EnvironmentObject private var store: Store
    @Environment(\.theme) private var t
    @Environment(\.dismiss) private var dismiss
    @State private var draft: QuickAction
    @State private var query = ""
    @State private var tab: IconTab = .dev
    /// nil = the action/folder itself, otherwise the index of a link inside the folder.
    @State private var iconTarget: Int?
    let isNew: Bool

    enum IconTab: String, CaseIterable { case dev, solid, brands }

    init(action: QuickAction, isNew: Bool) {
        _draft = State(initialValue: action)
        self.isNew = isNew
    }

    private var isFolder: Bool { draft.isFolder }

    private var cleanedChildren: [QuickAction] {
        (draft.children ?? []).filter { !$0.url.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var valid: Bool {
        guard !draft.title.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if isFolder { return cleanedChildren.allSatisfy { $0.resolvedURL != nil } }
        return draft.resolvedURL != nil
    }

    private var currentIcon: String {
        if let i = iconTarget, let kids = draft.children, kids.indices.contains(i) { return kids[i].icon }
        return draft.icon
    }

    private func setIcon(_ name: String) {
        if let i = iconTarget, draft.children?.indices.contains(i) == true { draft.children?[i].icon = name } else { draft.icon = name }
    }

    private var icons: [FAEntry] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { return Array(FA.entries.filter { $0.names.contains { $0.contains(q) } }.prefix(420)) }
        switch tab {
        case .dev: return FA.devIcons
        case .solid: return Array(FA.entries.filter { !$0.brand }.prefix(600))
        case .brands: return FA.entries.filter(\.brand)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                FAIcon(draft.icon, size: 16)
                    .foregroundStyle(t.accentInk)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 8).fill(t.accent))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(isNew ? "new" : "edit") \(isFolder ? "folder" : "quick action")").font(.mono(14, .bold))
                    Text(isFolder ? "a button that opens a dropdown of links" : "a button that opens a link, app url or file")
                        .font(.mono(11)).foregroundStyle(t.muted)
                }
            }

            Field(label: "title", text: $draft.title, prompt: isFolder ? "Dashboards" : "Jira board")

            if isFolder {
                linksEditor
            } else {
                Field(label: "url", text: $draft.url, prompt: "https://...  vscode://...  file:///...")
            }

            iconPicker

            HStack {
                if !isNew {
                    Button("delete") {
                        store.deleteAction(draft.id)
                        dismiss()
                    }
                    .buttonStyle(.plain)
        .handCursor().font(.mono(12)).foregroundStyle(t.danger)
                }
                Spacer()
                Button("cancel") { dismiss() }
                    .buttonStyle(.plain)
        .handCursor().font(.mono(12)).foregroundStyle(t.muted)
                    .keyboardShortcut(.cancelAction)
                    .padding(.trailing, 10)
                Button(action: save) {
                    Text("save").font(.mono(12, .bold))
                        .foregroundStyle(t.accentInk)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 7).fill(t.accent))
                        .opacity(valid ? 1 : 0.4)
                }
                .buttonStyle(.plain)
        .handCursor()
                .disabled(!valid)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 520)
        .background(t.panel)
        .foregroundStyle(t.text)
    }

    private func save() {
        draft.title = draft.title.trimmingCharacters(in: .whitespaces)
        draft.url = draft.url.trimmingCharacters(in: .whitespaces)
        if isFolder {
            draft.url = ""
            draft.children = cleanedChildren.map { c in
                var c = c
                c.url = c.url.trimmingCharacters(in: .whitespaces)
                c.title = c.title.trimmingCharacters(in: .whitespaces)
                if c.title.isEmpty { c.title = c.resolvedURL?.host ?? c.url }
                return c
            }
        }
        withAnimation(.spring) { store.upsert(draft) }
        dismiss()
    }

    private var linksEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("links").font(.mono(11)).foregroundStyle(t.muted)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(Array((draft.children ?? []).enumerated()), id: \.element.id) { i, child in
                        HStack(spacing: 6) {
                            Button { iconTarget = (iconTarget == i ? nil : i) } label: {
                                FAIcon(child.icon, size: 12)
                                    .foregroundStyle(iconTarget == i ? t.accentInk : t.text)
                                    .frame(width: 30, height: 30)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(iconTarget == i ? t.accent : t.bg))
                                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(iconTarget == i ? t.accent : t.border))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
        .handCursor()
                            .help("pick an icon for this link below")
                            MiniField(text: childBinding(i, \.title), prompt: "title").frame(width: 130)
                            MiniField(text: childBinding(i, \.url), prompt: "https://...")
                            HoverIconButton(icon: "xmark", size: 10, hoverColor: t.danger, help: "remove link") {
                                if iconTarget == i { iconTarget = nil }
                                draft.children?.remove(at: i)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 150)
            .fixedSize(horizontal: false, vertical: true)
            Button {
                draft.children?.append(QuickAction(title: "", url: "", icon: "link"))
            } label: {
                HStack(spacing: 6) { FAIcon("plus", size: 9); Text("add link").font(.mono(11)) }
                    .foregroundStyle(t.accent)
            }
            .buttonStyle(.plain)
        .handCursor()
        }
    }

    private func childBinding(_ i: Int, _ kp: WritableKeyPath<QuickAction, String>) -> Binding<String> {
        Binding(
            get: { (draft.children?.indices.contains(i) == true) ? draft.children![i][keyPath: kp] : "" },
            set: { v in if draft.children?.indices.contains(i) == true { draft.children![i][keyPath: kp] = v } }
        )
    }

    private var iconPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(iconTarget == nil ? "icon" : "icon for link \(iconTarget! + 1)").font(.mono(11)).foregroundStyle(t.muted)
                Text("fa-\(currentIcon)").font(.mono(11)).foregroundStyle(t.accent)
                Spacer()
                HStack(spacing: 2) {
                    ForEach(IconTab.allCases, id: \.self) { tb in
                        Button { tab = tb; query = "" } label: {
                            Text(tb.rawValue).font(.mono(10.5, tab == tb && query.isEmpty ? .semibold : .regular))
                                .foregroundStyle(tab == tb && query.isEmpty ? t.accentInk : t.muted)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(RoundedRectangle(cornerRadius: 5).fill(tab == tb && query.isEmpty ? t.accent : .clear))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
        .handCursor()
                    }
                }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 7).fill(t.bg))
            }
            HStack(spacing: 8) {
                FAIcon("magnifying-glass", size: 10).foregroundStyle(t.faint)
                TextField("", text: $query, prompt: Text("search \(FA.entries.count) icons (github, docker, bug, rocket...)").foregroundStyle(t.faint))
                    .textFieldStyle(.plain).font(.mono(12))
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 7).fill(t.bg))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(t.border))

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 34, maximum: 40), spacing: 6)], spacing: 6) {
                    ForEach(icons) { e in
                        let sel = currentIcon == e.name
                        Button { setIcon(e.name) } label: {
                            FAIcon(e.name, size: 14)
                                .foregroundStyle(sel ? t.accentInk : t.text)
                                .frame(width: 34, height: 34)
                                .background(RoundedRectangle(cornerRadius: 7).fill(sel ? t.accent : t.bg))
                                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(sel ? t.accent : t.border))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
        .handCursor()
                        .help(e.name)
                    }
                }
                .padding(2)
            }
            .frame(height: 190)
        }
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
            MiniField(text: $text, prompt: prompt)
        }
    }
}

private struct MiniField: View {
    @Environment(\.theme) private var t
    @Binding var text: String
    let prompt: String

    var body: some View {
        TextField("", text: $text, prompt: Text(prompt).foregroundStyle(t.faint))
            .textFieldStyle(.plain)
            .font(.mono(12))
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 7).fill(t.bg))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(t.border))
    }
}
