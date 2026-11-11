import Foundation

/// A user-created list. Its `id` is a stable slug used in data, CLI and @tokens.
struct CustomList: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var icon: String = "list-ul"

    static func slug(_ name: String) -> String {
        let lowered = name.lowercased()
        var out = ""
        for ch in lowered {
            if ch.isLetter || ch.isNumber { out.append(ch) } else if !out.hasSuffix("-") { out.append("-") }
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

/// Custom lists currently known (set by the Store / TaskDB whenever data loads or changes).
enum ListRegistry {
    static var custom: [CustomList] = []
    static func find(_ id: String) -> CustomList? { custom.first { $0.id == id } }
}

/// A list a task lives in: one of the four built-ins or a custom list (by id).
struct Bucket: Hashable, Identifiable, Codable {
    let rawValue: String

    static let today = Bucket(raw: "today")
    static let tomorrow = Bucket(raw: "tomorrow")
    static let week = Bucket(raw: "week")
    static let backlog = Bucket(raw: "backlog")
    static let builtins: [Bucket] = [.today, .tomorrow, .week, .backlog]

    static var allCases: [Bucket] { builtins + ListRegistry.custom.map { Bucket(raw: $0.id) } }
    static var custom: [Bucket] { ListRegistry.custom.map { Bucket(raw: $0.id) } }

    init(raw: String) { rawValue = raw }

    /// nil for ids that are neither built-in nor an existing custom list.
    init?(rawValue: String) {
        let b = Bucket(raw: rawValue)
        guard b.isBuiltin || ListRegistry.find(rawValue) != nil else { return nil }
        self = b
    }

    init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }

    var id: String { rawValue }
    var isBuiltin: Bool { Bucket.builtins.map(\.rawValue).contains(rawValue) }
    var exists: Bool { isBuiltin || ListRegistry.find(rawValue) != nil }

    var title: String {
        switch self {
        case .today: "Today"
        case .tomorrow: "Tomorrow"
        case .week: "This Week"
        case .backlog: "Backlog"
        default: ListRegistry.find(rawValue)?.name ?? rawValue
        }
    }

    var path: String {
        switch self {
        case .week: "~/this-week"
        default: "~/" + rawValue
        }
    }

    var icon: String {
        switch self {
        case .today: "sun"
        case .tomorrow: "forward"
        case .week: "calendar-week"
        case .backlog: "box-archive"
        default: ListRegistry.find(rawValue)?.icon ?? "list-ul"
        }
    }

    /// Cmd-number shortcut, built-ins only.
    var key: Character? {
        switch self {
        case .today: "1"
        case .tomorrow: "2"
        case .week: "3"
        case .backlog: "4"
        default: nil
        }
    }

    /// Inline routing tokens for the quick-add prompt.
    static func parse(_ token: String) -> Bucket? {
        let t = token.lowercased()
        guard t.hasPrefix("@"), t.count > 1 else { return nil }
        switch t {
        case "@today", "@td", "@now": return .today
        case "@tomorrow", "@tom", "@tmr": return .tomorrow
        case "@week", "@wk", "@thisweek", "@this-week": return .week
        case "@backlog", "@bl", "@later", "@someday": return .backlog
        default:
            let name = String(t.dropFirst())
            if let l = ListRegistry.custom.first(where: { $0.id == name || CustomList.slug($0.name) == name }) {
                return Bucket(raw: l.id)
            }
            return nil
        }
    }
}

struct Subtask: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var done = false
}

struct TaskItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var done = false
    var bucket: Bucket
    var subtasks: [Subtask] = []
    var createdAt = Date()
    var completedAt: Date?

    init(title: String, bucket: Bucket) {
        self.title = title
        self.bucket = bucket
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        bucket = try c.decodeIfPresent(Bucket.self, forKey: .bucket) ?? .backlog
        subtasks = try c.decodeIfPresent([Subtask].self, forKey: .subtasks) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
    }
}

/// A named piece of text (e.g. an AI prompt) that copies to the clipboard when clicked.
struct Snippet: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var text: String
    var shortID: String { String(id.uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(6)) }
}

struct QuickAction: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var url: String
    var icon: String
    /// Non-nil makes this a folder: a dropdown of links.
    var children: [QuickAction]? = nil
    /// Non-nil makes this a prompts button: a dropdown of text snippets that copy on click.
    var snippets: [Snippet]? = nil

    var isFolder: Bool { children != nil }
    var isSnippets: Bool { snippets != nil }

    static let defaults: [QuickAction] = [
        QuickAction(title: "GitHub", url: "https://github.com", icon: "code-branch"),
        QuickAction(title: "localhost:3000", url: "http://localhost:3000", icon: "server"),
    ]

    /// Adds https:// when no scheme is given; leaves custom schemes (vscode://, file://) alone.
    var resolvedURL: URL? {
        let raw = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if raw.contains("://") || raw.hasPrefix("mailto:") { return URL(string: raw) }
        return URL(string: "https://" + raw)
    }
}

struct Note: Identifiable, Codable, Equatable {
    var id = UUID()
    var text = ""
    var updatedAt = Date()

    private var lines: [String] {
        text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    var title: String { lines.first.map(LinkFormat.plain) ?? "untitled" }
    var preview: String { lines.dropFirst().first.map(LinkFormat.plain) ?? "" }
    var shortID: String { String(id.uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(6)) }
}

struct AppData: Codable {
    var tasks: [TaskItem] = []
    var notes: [Note] = []
    var lists: [CustomList] = []
    var actions: [QuickAction] = QuickAction.defaults
    var lastDay: String = DataFile.dayKey(Date())

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tasks = try c.decodeIfPresent([TaskItem].self, forKey: .tasks) ?? []
        notes = try c.decodeIfPresent([Note].self, forKey: .notes) ?? []
        lists = try c.decodeIfPresent([CustomList].self, forKey: .lists) ?? []
        actions = try c.decodeIfPresent([QuickAction].self, forKey: .actions) ?? QuickAction.defaults
        lastDay = try c.decodeIfPresent(String.self, forKey: .lastDay) ?? DataFile.dayKey(Date())
    }
}
