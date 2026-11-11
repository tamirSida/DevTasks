import SwiftUI
import AppKit

struct Theme {
    let bg, panel, raised, border, text, muted, faint, accent, accentInk, danger, warn, info: Color

    static let dark = Theme(
        bg: Color(hex: 0x0B0E14), panel: Color(hex: 0x11151C), raised: Color(hex: 0x181D27),
        border: Color(hex: 0x232A35), text: Color(hex: 0xE6EDF3), muted: Color(hex: 0x8B949E),
        faint: Color(hex: 0x4D5562), accent: Color(hex: 0x5EF2A6), accentInk: Color(hex: 0x06140D),
        danger: Color(hex: 0xFF6B6B), warn: Color(hex: 0xFFB86B), info: Color(hex: 0x7AA2F7)
    )

    static let light = Theme(
        bg: Color(hex: 0xF5F6F8), panel: Color(hex: 0xFFFFFF), raised: Color(hex: 0xEEF1F4),
        border: Color(hex: 0xE1E4E8), text: Color(hex: 0x1F2328), muted: Color(hex: 0x5F6873),
        faint: Color(hex: 0xA0A7B0), accent: Color(hex: 0x12A35A), accentInk: Color(hex: 0xFFFFFF),
        danger: Color(hex: 0xD1242F), warn: Color(hex: 0xBF6A02), info: Color(hex: 0x3B6FE0)
    )

    func tint(_ b: Bucket) -> Color {
        switch b {
        case .today: accent
        case .tomorrow: info
        case .week: warn
        case .backlog: muted
        }
    }
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

/// Picks the palette from the effective color scheme so "system" mode follows macOS.
struct ThemeProvider<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: Content
    var body: some View {
        content.environment(\.theme, scheme == .dark ? .dark : .light)
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
