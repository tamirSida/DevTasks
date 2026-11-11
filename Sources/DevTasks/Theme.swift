import SwiftUI
import AppKit

struct Theme: Identifiable {
    let id: String
    let name: String
    let isDark: Bool
    var bg, panel, raised: Color
    let border, text, muted, faint, accent, accentInk, danger, warn, info: Color

    init(_ id: String, _ name: String, dark: Bool,
         bg: UInt32, panel: UInt32, raised: UInt32, border: UInt32, text: UInt32, muted: UInt32, faint: UInt32,
         accent: UInt32, accentInk: UInt32, danger: UInt32, warn: UInt32, info: UInt32) {
        self.id = id
        self.name = name
        isDark = dark
        self.bg = Color(hex: bg); self.panel = Color(hex: panel); self.raised = Color(hex: raised)
        self.border = Color(hex: border); self.text = Color(hex: text); self.muted = Color(hex: muted)
        self.faint = Color(hex: faint); self.accent = Color(hex: accent); self.accentInk = Color(hex: accentInk)
        self.danger = Color(hex: danger); self.warn = Color(hex: warn); self.info = Color(hex: info)
    }

    func tint(_ b: Bucket) -> Color {
        switch b {
        case .today: accent
        case .tomorrow: info
        case .week: warn
        case .backlog: muted
        }
    }

    /// Surfaces become translucent; text and accents stay solid.
    func withOpacity(_ o: Double) -> Theme {
        guard o < 0.999 else { return self }
        var t = self
        t.bg = bg.opacity(o)
        t.panel = panel.opacity(min(1, o + 0.1))
        t.raised = raised.opacity(min(1, o + 0.2))
        return t
    }

    // MARK: catalog

    static let dark = Theme("devtasks-dark", "DevTasks", dark: true,
        bg: 0x0B0E14, panel: 0x11151C, raised: 0x181D27, border: 0x232A35, text: 0xE6EDF3, muted: 0x8B949E,
        faint: 0x4D5562, accent: 0x5EF2A6, accentInk: 0x06140D, danger: 0xFF6B6B, warn: 0xFFB86B, info: 0x7AA2F7)

    static let light = Theme("devtasks-light", "DevTasks Light", dark: false,
        bg: 0xF5F6F8, panel: 0xFFFFFF, raised: 0xEEF1F4, border: 0xE1E4E8, text: 0x1F2328, muted: 0x5F6873,
        faint: 0xA0A7B0, accent: 0x12A35A, accentInk: 0xFFFFFF, danger: 0xD1242F, warn: 0xBF6A02, info: 0x3B6FE0)

    static let all: [Theme] = [
        dark,
        // Based on your iTerm2 default profile.
        Theme("iterm", "iTerm", dark: true,
              bg: 0x15191F, panel: 0x1A1F27, raised: 0x222831, border: 0x2C333E, text: 0xDCDCDC, muted: 0x8E949C,
              faint: 0x585F69, accent: 0x58E790, accentInk: 0x0A1A10, danger: 0xDD7975, warn: 0xE5D45A, info: 0x328EEE),
        Theme("tokyo-night", "Tokyo Night", dark: true,
              bg: 0x1A1B26, panel: 0x1F2335, raised: 0x292E42, border: 0x2F3549, text: 0xC0CAF5, muted: 0x8089B3,
              faint: 0x565F89, accent: 0x7AA2F7, accentInk: 0x16161E, danger: 0xF7768E, warn: 0xE0AF68, info: 0xBB9AF7),
        Theme("catppuccin-mocha", "Catppuccin Mocha", dark: true,
              bg: 0x1E1E2E, panel: 0x232334, raised: 0x313244, border: 0x45475A, text: 0xCDD6F4, muted: 0xA6ADC8,
              faint: 0x6C7086, accent: 0xCBA6F7, accentInk: 0x1E1E2E, danger: 0xF38BA8, warn: 0xF9E2AF, info: 0x89B4FA),
        Theme("dracula", "Dracula", dark: true,
              bg: 0x282A36, panel: 0x21222C, raised: 0x343746, border: 0x44475A, text: 0xF8F8F2, muted: 0xA9ADC1,
              faint: 0x6272A4, accent: 0x50FA7B, accentInk: 0x1A1B23, danger: 0xFF5555, warn: 0xF1FA8C, info: 0xBD93F9),
        Theme("one-dark", "One Dark", dark: true,
              bg: 0x282C34, panel: 0x21252B, raised: 0x2C313A, border: 0x3A3F4B, text: 0xABB2BF, muted: 0x8B919D,
              faint: 0x5C6370, accent: 0x98C379, accentInk: 0x1E2127, danger: 0xE06C75, warn: 0xE5C07B, info: 0x61AFEF),
        Theme("nord", "Nord", dark: true,
              bg: 0x2E3440, panel: 0x333A47, raised: 0x3B4252, border: 0x434C5E, text: 0xECEFF4, muted: 0xA3ABB9,
              faint: 0x616E88, accent: 0x88C0D0, accentInk: 0x2E3440, danger: 0xBF616A, warn: 0xEBCB8B, info: 0x81A1C1),
        Theme("gruvbox", "Gruvbox", dark: true,
              bg: 0x282828, panel: 0x1D2021, raised: 0x32302F, border: 0x3C3836, text: 0xEBDBB2, muted: 0xA89984,
              faint: 0x665C54, accent: 0xB8BB26, accentInk: 0x1D2021, danger: 0xFB4934, warn: 0xFABD2F, info: 0x83A598),
        light,
        Theme("github-light", "GitHub Light", dark: false,
              bg: 0xF6F8FA, panel: 0xFFFFFF, raised: 0xEEF1F4, border: 0xD0D7DE, text: 0x1F2328, muted: 0x59636E,
              faint: 0x8C959F, accent: 0x0969DA, accentInk: 0xFFFFFF, danger: 0xCF222E, warn: 0x9A6700, info: 0x8250DF),
        Theme("catppuccin-latte", "Catppuccin Latte", dark: false,
              bg: 0xEFF1F5, panel: 0xE6E9EF, raised: 0xDCE0E8, border: 0xCCD0DA, text: 0x4C4F69, muted: 0x6C6F85,
              faint: 0x9CA0B0, accent: 0x8839EF, accentInk: 0xFFFFFF, danger: 0xD20F39, warn: 0xDF8E1D, info: 0x1E66F5),
        Theme("solarized-light", "Solarized Light", dark: false,
              bg: 0xFDF6E3, panel: 0xEEE8D5, raised: 0xE8E1CC, border: 0xDDD6C1, text: 0x073642, muted: 0x657B83,
              faint: 0x93A1A1, accent: 0x859900, accentInk: 0xFDF6E3, danger: 0xDC322F, warn: 0xB58900, info: 0x268BD2),
    ]

    static func named(_ id: String, fallback: Theme) -> Theme { all.first { $0.id == id } ?? fallback }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension Font {
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

private struct ThemeKey: EnvironmentKey { static let defaultValue = Theme.dark }

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

enum Prefs {
    static let darkTheme = "darkTheme"
    static let lightTheme = "lightTheme"
    static let opacity = "windowOpacity"
    static let blur = "windowBlur"
}

/// Picks the palette from the effective color scheme so "system" mode follows macOS.
struct ThemeProvider<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @AppStorage(Prefs.darkTheme) private var darkID = Theme.dark.id
    @AppStorage(Prefs.lightTheme) private var lightID = Theme.light.id
    @AppStorage(Prefs.opacity) private var opacity = 1.0
    var translucent = true
    @ViewBuilder var content: Content

    var body: some View {
        let base = scheme == .dark ? Theme.named(darkID, fallback: .dark) : Theme.named(lightID, fallback: .light)
        content.environment(\.theme, translucent ? base.withOpacity(opacity) : base)
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .system: "circle-half-stroke"
        case .light: "sun"
        case .dark: "moon"
        }
    }

    var next: Appearance {
        switch self {
        case .system: .dark
        case .dark: .light
        case .light: .system
        }
    }

    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - Window translucency

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .underWindowBackground
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

/// Makes the hosting window non-opaque when the theme is translucent.
struct WindowTranslucency: NSViewRepresentable {
    let translucent: Bool
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ v: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            w.isOpaque = !translucent
            w.backgroundColor = translucent ? .clear : .windowBackgroundColor
        }
    }
}

// MARK: - Theme settings

struct ThemeSettings: View {
    @Environment(\.theme) private var t
    @AppStorage("appearance") private var appearance: Appearance = .dark
    @AppStorage(Prefs.darkTheme) private var darkID = Theme.dark.id
    @AppStorage(Prefs.lightTheme) private var lightID = Theme.light.id
    @AppStorage(Prefs.opacity) private var opacity = 1.0
    @AppStorage(Prefs.blur) private var blur = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("appearance").font(.mono(13, .bold))
                Spacer()
                HStack(spacing: 6) {
                    ForEach(Appearance.allCases) { a in
                        IconToggle(icon: a.icon, on: appearance == a, help: "\(a.rawValue) mode") { appearance = a }
                    }
                }
            }

            themeGrid("dark theme", Theme.all.filter(\.isDark), $darkID)
            themeGrid("light theme", Theme.all.filter { !$0.isDark }, $lightID)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionLabel("window opacity")
                    Spacer()
                    Text("\(Int((opacity * 100).rounded()))%").font(.mono(11)).foregroundStyle(t.muted)
                }
                Slider(value: $opacity, in: 0.45...1.0)
                    .controlSize(.small)
                Toggle(isOn: $blur) {
                    Text("blur what's behind the window").font(.mono(11)).foregroundStyle(t.muted)
                }
                .toggleStyle(.checkbox)
                .disabled(opacity >= 0.999)
            }
        }
        .padding(18)
        .frame(width: 380)
        .foregroundStyle(t.text)
    }

    private func themeGrid(_ label: String, _ themes: [Theme], _ sel: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(label)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 8)], spacing: 8) {
                ForEach(themes) { th in
                    ThemeSwatch(theme: th, selected: sel.wrappedValue == th.id) { sel.wrappedValue = th.id }
                }
            }
        }
    }
}

struct ThemeSwatch: View {
    @Environment(\.theme) private var t
    let theme: Theme
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Circle().fill(theme.accent).frame(width: 6, height: 6)
                        Capsule().fill(theme.text.opacity(0.8)).frame(width: 30, height: 4)
                    }
                    Capsule().fill(theme.muted.opacity(0.7)).frame(width: 44, height: 4)
                    HStack(spacing: 3) {
                        Capsule().fill(theme.info).frame(width: 12, height: 4)
                        Capsule().fill(theme.warn).frame(width: 12, height: 4)
                        Capsule().fill(theme.danger).frame(width: 12, height: 4)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(theme.bg))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.border))
                Text(theme.name).font(.mono(9.5)).foregroundStyle(selected ? t.accent : t.muted).lineLimit(1)
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? t.accent : .clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
