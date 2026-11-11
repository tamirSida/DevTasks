import AppKit

/// Links inside task titles.
///
/// Two forms are supported:
///  - bare URLs: shown as a short label ("github.com/…/pull/412")
///  - markdown links `[PBI 1234: Fix login](https://dev.azure.com/...)`: shown as the text only.
///    These come from pasting rich text (Azure DevOps, Teams, Slack, browsers) and are
///    turned back into rich links when copied out.
enum LinkFormat {
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    private static let mdLink = try! NSRegularExpression(
        pattern: #"\[([^\[\]\n]+)\]\(([a-zA-Z][a-zA-Z0-9+.\-]*:[^\s()]+)\)"#)

    struct Segment {
        let text: String
        let url: URL?
        let markdown: Bool
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

    static func segments(_ s: String, shorten: Bool = true) -> [Segment] {
        let ns = s as NSString
        var out: [Segment] = []
        var cursor = 0
        for m in mdLink.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            if m.range.location > cursor {
                out += bareSegments(ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor)), shorten: shorten)
            }
            let text = ns.substring(with: m.range(at: 1))
            if let url = URL(string: ns.substring(with: m.range(at: 2))) {
                out.append(Segment(text: text, url: url, markdown: true))
            } else {
                out.append(Segment(text: ns.substring(with: m.range), url: nil, markdown: false))
            }
            cursor = NSMaxRange(m.range)
        }
        if cursor < ns.length { out += bareSegments(ns.substring(from: cursor), shorten: shorten) }
        return out
    }

    private static func bareSegments(_ s: String, shorten: Bool) -> [Segment] {
        let ns = s as NSString
        var out: [Segment] = []
        var cursor = 0
        let found = detector?.matches(in: s, range: NSRange(location: 0, length: ns.length)) ?? []
        for m in found {
            guard let url = m.url else { continue }
            if m.range.location > cursor {
                out.append(Segment(text: ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor)), url: nil, markdown: false))
            }
            let original = ns.substring(with: m.range)
            out.append(Segment(text: shorten ? shortLabel(url, original: original) : original, url: url, markdown: false))
            cursor = NSMaxRange(m.range)
        }
        if cursor < ns.length { out.append(Segment(text: ns.substring(from: cursor), url: nil, markdown: false)) }
        return out
    }

    /// Exact ranges of links in the raw text (markdown links cover the whole [text](url)).
    static func linkRanges(_ s: String) -> [(range: NSRange, url: URL)] {
        let ns = s as NSString
        var out: [(NSRange, URL)] = []
        var cursor = 0
        func bare(_ r: NSRange) {
            guard r.length > 0 else { return }
            for m in detector?.matches(in: s, range: r) ?? [] { if let u = m.url { out.append((m.range, u)) } }
        }
        for m in mdLink.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            bare(NSRange(location: cursor, length: m.range.location - cursor))
            if let u = URL(string: ns.substring(with: m.range(at: 2))) { out.append((m.range, u)) }
            cursor = NSMaxRange(m.range)
        }
        bare(NSRange(location: cursor, length: ns.length - cursor))
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

    /// Text with links reduced to their labels (for read-only SwiftUI Text).
    static func plain(_ s: String) -> String { segments(s).map(\.text).joined() }

    static func hasLinks(_ s: String) -> Bool { segments(s, shorten: false).contains { $0.url != nil } }

    // MARK: - Clipboard out

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func html(_ s: String) -> String {
        let body = segments(s, shorten: false).map { seg -> String in
            let text = esc(seg.text).replacingOccurrences(of: "\n", with: "<br>")
            guard let u = seg.url else { return text }
            return "<a href=\"\(esc(u.absoluteString))\">\(text)</a>"
        }.joined()
        return "<meta charset=\"utf-8\"><span>\(body)</span>"
    }

    /// Plain-text fallback for apps that don't take HTML: "title (url)".
    static func plainForCopy(_ s: String) -> String {
        segments(s, shorten: false).map { seg in
            guard let u = seg.url, seg.markdown else { return seg.text }
            return "\(seg.text) (\(u.absoluteString))"
        }.joined()
    }

    /// Puts text on the clipboard; links become real embedded links where the target app supports it.
    static func copy(_ s: String, to pb: NSPasteboard = .general) {
        pb.clearContents()
        if hasLinks(s) {
            pb.declareTypes([.html, .string], owner: nil)
            pb.setString(html(s), forType: .html)
            pb.setString(plainForCopy(s), forType: .string)
        } else {
            pb.setString(s, forType: .string)
        }
    }

    // MARK: - Clipboard in

    /// Converts rich clipboard content with embedded links (e.g. an Azure DevOps work item title)
    /// to text with markdown links. Returns nil when there are no embedded links.
    static func fromPasteboard(_ pb: NSPasteboard = .general) -> String? {
        var attr: NSAttributedString?
        if let d = pb.data(forType: .html) {
            attr = NSAttributedString(html: d, options: [.characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil)
        }
        if attr == nil, let d = pb.data(forType: .rtf) {
            attr = NSAttributedString(rtf: d, documentAttributes: nil)
        }
        guard let a = attr else { return nil }
        return markdown(from: a)
    }

    static func markdown(from a: NSAttributedString) -> String? {
        let ns = a.string as NSString
        var out = ""
        var hasLink = false
        a.enumerateAttribute(.link, in: NSRange(location: 0, length: ns.length)) { value, range, _ in
            let raw = ns.substring(with: range)
            let url = (value as? URL) ?? (value as? String).flatMap(URL.init(string:))
            let label = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url, !label.isEmpty else { out += raw; return }
            hasLink = true
            let lead = String(raw.prefix { $0.isWhitespace })
            let trail = String(raw.reversed().prefix { $0.isWhitespace }.reversed())
            let link = url.absoluteString
            if label == link || label == link.replacingOccurrences(of: "https://", with: "") {
                out += lead + link + trail
            } else {
                let cleanLabel = label.replacingOccurrences(of: "[", with: "(").replacingOccurrences(of: "]", with: ")")
                    .replacingOccurrences(of: "\n", with: " ")
                let cleanURL = link.replacingOccurrences(of: "(", with: "%28").replacingOccurrences(of: ")", with: "%29")
                out += "\(lead)[\(cleanLabel)](\(cleanURL))\(trail)"
            }
        }
        guard hasLink else { return nil }
        return out.replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
