import SwiftUI
import CoreText

struct FAEntry: Identifiable {
    let name: String        // canonical name
    let glyph: String
    let names: [String]     // canonical + aliases, used for search
    let brand: Bool
    var id: String { name }
}

/// Font Awesome 6 Free: Solid + Brands, bundled as TTFs and registered for this process.
enum FA {
    private(set) static var solidName = "FontAwesome6Free-Solid"
    private(set) static var brandsName = "FontAwesome6Brands-Regular"
    private static var solidDesc: CTFontDescriptor?
    private static var brandsDesc: CTFontDescriptor?

    static func register() {
        if let (d, n) = load("fa-solid-900") { solidDesc = d; solidName = n }
        if let (d, n) = load("fa-brands-400") { brandsDesc = d; brandsName = n }
    }

    private static func load(_ file: String) -> (CTFontDescriptor, String)? {
        guard let url = fontURL(file) else {
            NSLog("DevTasks: \(file).ttf not found")
            return nil
        }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        guard let descs = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let d = descs.first,
              let n = CTFontDescriptorCopyAttribute(d, kCTFontNameAttribute) as? String else { return nil }
        return (d, n)
    }

    private static func fontURL(_ file: String) -> URL? {
        if let u = Bundle.main.url(forResource: file, withExtension: "ttf") { return u }
        // Fallback for `swift run`: look for Resources/ near the cwd or the executable.
        let fm = FileManager.default
        var candidates = [URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("Resources/\(file).ttf")]
        var dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<6 {
            candidates.append(dir.appendingPathComponent("Resources/\(file).ttf"))
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

    private static func has(_ desc: CTFontDescriptor?, _ g: String) -> Bool {
        guard let desc else { return false }
        let font = CTFontCreateWithFontDescriptor(desc, 16, nil)
        var chars = Array(g.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: chars.count)
        return CTFontGetGlyphsForCharacters(font, &chars, &glyphs, chars.count) && glyphs[0] != 0
    }

    /// Unique icons that exist in one of the bundled fonts.
    static let entries: [FAEntry] = {
        var order: [String] = []
        var byGlyph: [String: [String]] = [:]
        for line in faIconData.split(separator: "\n") {
            guard let name = line.split(separator: ":").first.map(String.init), let g = map[name] else { continue }
            if byGlyph[g] == nil { order.append(g) }
            byGlyph[g, default: []].append(name)
        }
        return order.compactMap { g in
            guard let names = byGlyph[g] else { return nil }
            if has(solidDesc, g) { return FAEntry(name: names[0], glyph: g, names: names, brand: false) }
            if has(brandsDesc, g) { return FAEntry(name: names[0], glyph: g, names: names, brand: true) }
            return nil
        }
    }()

    static let brandNames: Set<String> = Set(entries.filter(\.brand).flatMap(\.names))

    /// Hand-picked icons for developer quick actions (missing names are skipped).
    static let devIcons: [FAEntry] = {
        let names = [
            // brands
            "github", "gitlab", "git-alt", "bitbucket", "docker", "aws", "google", "microsoft", "cloudflare",
            "digital-ocean", "python", "js", "node-js", "npm", "yarn", "react", "vuejs", "angular", "java",
            "rust", "golang", "php", "swift", "apple", "linux", "ubuntu", "windows", "android", "app-store-ios",
            "html5", "css3-alt", "sass", "laravel", "wordpress", "figma", "sketch", "slack", "discord", "jira",
            "confluence", "atlassian", "trello", "stack-overflow", "dev", "codepen", "jenkins", "gitkraken",
            "stripe", "chrome", "firefox-browser", "safari", "google-drive", "dropbox", "unity", "raspberry-pi",
            "youtube", "x-twitter", "linkedin", "reddit", "hacker-news", "medium", "markdown", "openid",
            // solid
            "code", "terminal", "bug", "bug-slash", "server", "database", "code-branch", "code-merge",
            "code-pull-request", "code-commit", "code-compare", "code-fork", "laptop-code", "file-code",
            "folder-tree", "microchip", "memory", "hard-drive", "cloud", "cloud-arrow-up", "network-wired",
            "plug", "gear", "gears", "robot", "cube", "cubes", "layer-group", "diagram-project", "sitemap",
            "key", "lock", "shield-halved", "user-secret", "flask", "vial", "book", "book-open", "rocket",
            "chart-line", "gauge-high", "list-check", "keyboard", "hashtag", "at", "link", "globe", "box",
            "boxes-stacked", "wrench", "screwdriver-wrench", "hammer", "toolbox", "magnifying-glass", "eye",
            "bolt", "fire", "triangle-exclamation", "circle-check", "clipboard-list", "calendar", "envelope",
            "message", "comments", "video", "headphones", "mug-hot", "brain", "wand-magic-sparkles",
            "puzzle-piece", "desktop", "mobile-screen", "table", "chart-pie", "chart-bar", "signal",
            "satellite-dish", "infinity", "arrows-rotate", "play", "power-off", "folder", "folder-open",
            "file-lines", "house", "star", "bookmark", "flag", "tag",
        ]
        let byName = Dictionary(entries.flatMap { e in e.names.map { ($0, e) } }, uniquingKeysWith: { a, _ in a })
        var seen = Set<String>()
        return names.compactMap { n in
            guard let e = byName[n], seen.insert(e.name).inserted else { return nil }
            return e
        }
    }()

    static func glyph(_ name: String) -> String { map[name] ?? map["circle-question"] ?? "?" }
    static func fontName(for name: String) -> String { brandNames.contains(name) ? brandsName : solidName }
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
            .font(.custom(FA.fontName(for: name), fixedSize: size))
            .frame(minWidth: size * 1.15)
    }
}
