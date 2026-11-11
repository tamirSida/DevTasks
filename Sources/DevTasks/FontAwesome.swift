import SwiftUI
import CoreText

struct FAEntry: Identifiable {
    let name: String        // canonical name
    let glyph: String
    let names: [String]     // canonical + aliases, used for search
    var id: String { name }
}

/// Font Awesome 6 Free Solid, bundled as a TTF and registered for this process.
enum FA {
    private(set) static var fontName = "FontAwesome6Free-Solid"
    private static var descriptor: CTFontDescriptor?

    static func register() {
        guard let url = fontURL() else {
            NSLog("DevTasks: fa-solid-900.ttf not found")
            return
        }
        if let descs = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
           let d = descs.first {
            descriptor = d
            if let n = CTFontDescriptorCopyAttribute(d, kCTFontNameAttribute) as? String { fontName = n }
        }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    private static func fontURL() -> URL? {
        if let u = Bundle.main.url(forResource: "fa-solid-900", withExtension: "ttf") { return u }
        // Fallback for `swift run`: look for Resources/ near the cwd or the executable.
        let fm = FileManager.default
        var candidates = [URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("Resources/fa-solid-900.ttf")]
        var dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<6 {
            candidates.append(dir.appendingPathComponent("Resources/fa-solid-900.ttf"))
            dir = dir.deletingLastPathComponent()
        }
        return candidates.first { fm.fileExists(atPath: $0.path) }
    }

    static let map: [String: String] = {
        var m: [String: String] = [:]
        for line in faIconData.split(separator: "\n") {
            let parts = line.split(separator: ":")
            guard parts.count == 2, let code = UInt32(parts[1], radix: 16), let scalar = Unicode.Scalar(code) else { continue }
            m[String(parts[0])] = String(Character(scalar))
        }
        return m
    }()

    /// Unique icons that actually exist in the Solid font (brand icons are filtered out).
    static let entries: [FAEntry] = {
        let font = descriptor.map { CTFontCreateWithFontDescriptor($0, 16, nil) }
            ?? CTFontCreateWithName(fontName as CFString, 16, nil)
        var order: [String] = []
        var byGlyph: [String: [String]] = [:]
        for line in faIconData.split(separator: "\n") {
            guard let name = line.split(separator: ":").first.map(String.init), let g = map[name] else { continue }
            if byGlyph[g] == nil { order.append(g) }
            byGlyph[g, default: []].append(name)
        }
        return order.compactMap { g in
            var chars = Array(g.utf16)
            var glyphs = [CGGlyph](repeating: 0, count: chars.count)
            guard CTFontGetGlyphsForCharacters(font, &chars, &glyphs, chars.count), glyphs[0] != 0,
                  let names = byGlyph[g] else { return nil }
            return FAEntry(name: names[0], glyph: g, names: names)
        }
    }()

    static func glyph(_ name: String) -> String { map[name] ?? map["circle-question"] ?? "?" }

    static func exists(_ name: String) -> Bool { map[name] != nil }
}

struct FAIcon: View {
    let name: String
    var size: CGFloat = 13

    init(_ name: String, size: CGFloat = 13) {
        self.name = name
        self.size = size
    }

    var body: some View {
        Text(FA.glyph(name))
            .font(.custom(FA.fontName, fixedSize: size))
            .frame(minWidth: size * 1.15)
    }
}
