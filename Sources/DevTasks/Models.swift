import Foundation

enum Bucket: String, Codable, CaseIterable, Identifiable {
    case today, tomorrow, week, backlog

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .tomorrow: "Tomorrow"
        case .week: "This Week"
        case .backlog: "Backlog"
        }
    }

    var path: String {
        switch self {
        case .today: "~/today"
        case .tomorrow: "~/tomorrow"
        case .week: "~/this-week"
        case .backlog: "~/backlog"
        }
    }

    var icon: String {
        switch self {
        case .today: "sun"
        case .tomorrow: "forward"
        case .week: "calendar-week"
        case .backlog: "box-archive"
        }
    }

    var key: Character {
        switch self {
        case .today: "1"
        case .tomorrow: "2"
        case .week: "3"
        case .backlog: "4"
        }
    }

    /// Inline routing tokens for the quick-add prompt.
    static func parse(_ token: String) -> Bucket? {
        switch token.lowercased() {
        case "@today", "@td", "@now": .today
        case "@tomorrow", "@tom", "@tmr": .tomorrow
        case "@week", "@wk", "@thisweek": .week
        case "@backlog", "@bl", "@later", "@someday": .backlog
        default: nil
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

struct QuickAction: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var url: String
    var icon: String
    /// Non-nil makes this a folder: a dropdown of links.
    var children: [QuickAction]? = nil

    var isFolder: Bool { children != nil }

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
    var actions: [QuickAction] = QuickAction.defaults
    var lastDay: String = DataFile.dayKey(Date())

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tasks = try c.decodeIfPresent([TaskItem].self, forKey: .tasks) ?? []
        notes = try c.decodeIfPresent([Note].self, forKey: .notes) ?? []
        actions = try c.decodeIfPresent([QuickAction].self, forKey: .actions) ?? QuickAction.defaults
        lastDay = try c.decodeIfPresent(String.self, forKey: .lastDay) ?? DataFile.dayKey(Date())
    }
}
