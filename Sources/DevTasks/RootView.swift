import SwiftUI

struct RootView: View {
    @Environment(\.theme) private var t
    @AppStorage(Prefs.opacity) private var opacity = 1.0
    @AppStorage(Prefs.blur) private var blur = true

    var body: some View {
        let translucent = opacity < 0.999
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 228)
                .background(t.panel)
            Rectangle().fill(t.border).frame(width: 1)
            MainView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background {
            ZStack {
                if translucent && blur { VisualEffectBackground() }
                t.bg
            }
            .ignoresSafeArea()
        }
        .background(WindowTranslucency(translucent: translucent))
        .foregroundStyle(t.text)
        .ignoresSafeArea()
        .frame(minWidth: 780, minHeight: 520)
        .tint(t.accent)
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.theme) private var t
    @AppStorage("appearance") private var appearance: Appearance = .dark
    @AppStorage("soundOn") private var soundOn = true
    @State private var showThemes = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                FAIcon("terminal", size: 13).foregroundStyle(t.accent)
                Text("devtasks").font(.mono(14, .bold))
                Text("v1.0").font(.mono(10)).foregroundStyle(t.faint)
            }
            .padding(.horizontal, 14)
            .padding(.top, 46)
            .padding(.bottom, 22)

            SectionLabel("lists").padding(.horizontal, 14).padding(.bottom, 4)

            ForEach(Bucket.allCases) { b in
                SidebarRow(bucket: b)
            }
            .padding(.horizontal, 8)

            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("done today").font(.mono(11)).foregroundStyle(t.muted)
                    Spacer()
                    Text("\(store.doneToday)").font(.mono(11, .bold)).foregroundStyle(t.accent)
                        .contentTransition(.numericText())
                        .animation(.spring, value: store.doneToday)
                }
                HStack(spacing: 6) {
                    ForEach(Appearance.allCases) { a in
                        IconToggle(icon: a.icon, on: appearance == a, help: "\(a.rawValue) appearance") {
                            appearance = a
                        }
                    }
                    Spacer()
                    IconToggle(icon: "palette", on: showThemes, help: "themes and opacity") { showThemes.toggle() }
                        .popover(isPresented: $showThemes, arrowEdge: .top) {
                            ThemeProvider(translucent: false) { ThemeSettingsPopover() }
                        }
                    IconToggle(icon: soundOn ? "volume-high" : "volume-xmark", on: soundOn, help: "check sound") {
                        soundOn.toggle()
                    }
                }
            }
            .padding(14)
            .overlay(alignment: .top) { Rectangle().fill(t.border).frame(height: 1) }
        }
    }
}

struct SidebarRow: View {
    @EnvironmentObject private var store: Store
    @Environment(\.theme) private var t
    let bucket: Bucket
    @State private var hover = false
    @State private var targeted = false

    var body: some View {
        let selected = store.selected == bucket
        let count = store.open(bucket).count
        Button {
            store.selected = bucket
        } label: {
            HStack(spacing: 10) {
                FAIcon(bucket.icon, size: 12)
                    .foregroundStyle(selected ? t.tint(bucket) : t.muted)
                    .frame(width: 16)
                Text(bucket.title.lowercased())
                    .font(.mono(12.5, selected ? .semibold : .regular))
                    .foregroundStyle(selected ? t.text : t.muted)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.mono(10.5, .semibold))
                        .foregroundStyle(selected ? t.tint(bucket) : t.faint)
                        .contentTransition(.numericText())
                }
                Text("\u{2318}\(String(bucket.key))")
                    .font(.mono(10)).foregroundStyle(t.faint)
                    .opacity(hover ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(targeted ? t.tint(bucket).opacity(0.18) : selected ? t.raised : hover ? t.raised.opacity(0.6) : .clear)
            )
            .overlay(alignment: .leading) {
                if selected {
                    RoundedRectangle(cornerRadius: 2).fill(t.tint(bucket)).frame(width: 3, height: 14).offset(x: -1)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(targeted ? t.tint(bucket) : .clear, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .animation(.spring(response: 0.3), value: count)
        .dropDestination(for: String.self) { items, _ in
            let ids = items.compactMap(UUID.init(uuidString:))
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                ids.forEach { store.move($0, to: bucket) }
            }
            return !ids.isEmpty
        } isTargeted: { targeted = $0 }
    }
}

// MARK: - Small shared pieces

struct SectionLabel: View {
    @Environment(\.theme) private var t
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text("// \(text)").font(.mono(10.5)).foregroundStyle(t.faint)
    }
}

struct IconToggle: View {
    @Environment(\.theme) private var t
    let icon: String
    let on: Bool
    let help: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            FAIcon(icon, size: 11)
                .foregroundStyle(on ? t.accent : hover ? t.text : t.muted)
                .frame(width: 28, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(on ? t.accent.opacity(0.14) : hover ? t.raised : .clear))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(on ? t.accent.opacity(0.4) : t.border, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

struct HoverIconButton: View {
    @Environment(\.theme) private var t
    let icon: String
    var size: CGFloat = 11
    var hoverColor: Color? = nil
    var help: String = ""
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            FAIcon(icon, size: size)
                .foregroundStyle(hover ? (hoverColor ?? t.text) : t.muted)
                .frame(width: 24, height: 22)
                .background(RoundedRectangle(cornerRadius: 5).fill(hover ? t.border.opacity(0.6) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

private struct ThemeSettingsPopover: View {
    @Environment(\.theme) private var t
    var body: some View { ThemeSettings().background(t.panel) }
}
