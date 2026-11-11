import Foundation

/// Shared persistence + operations used by the app, the CLI and the MCP server.
/// Everything goes through data.json with atomic writes, so the app (which watches the
/// file) picks up changes made by agents immediately.

struct DTError: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

enum DataFile {
    static var directory: URL {
        if let custom = ProcessInfo.processInfo.environment["DEVTASKS_DATA_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DevTasks", isDirectory: true)
    }

    static var url: URL { directory.appendingPathComponent("data.json") }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Missing file -> fresh data. Unreadable file -> throws (callers must not overwrite it).
    static func load() throws -> AppData {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let raw = try? Data(contentsOf: url) else { return AppData() }
        do { return try decoder.decode(AppData.self, from: raw) } catch {
            throw DTError("could not parse \(url.path): \(error.localizedDescription)")
        }
    }

    @discardableResult
    static func save(_ data: AppData) throws -> Data {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let raw = try encoder.encode(data)
        try raw.write(to: url, options: .atomic)
        return raw
    }

    static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

extension AppData {
    /// On a new day, open "tomorrow" tasks become "today" tasks. Returns true if anything changed.
    @discardableResult
    mutating func rollover(now: Date = Date()) -> Bool {
        let today = DataFile.dayKey(now)
        guard today > lastDay else { return false }
        for i in tasks.indices where tasks[i].bucket == .tomorrow && !tasks[i].done {
            tasks[i].bucket = .today
        }
        lastDay = today
        return true
    }
}

extension Bucket {
    /// Accepts "today", "@today", "tom", "this-week", "week", "bl", ...
    static func named(_ raw: String) -> Bucket? {
        let s = raw.lowercased().trimmingCharacters(in: .whitespaces)
        let tok = s.hasPrefix("@") ? s : "@" + s.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "")
        return Bucket.parse(tok)
    }

    static let namesHelp = "today | tomorrow | week | backlog"
}

extension TaskItem {
    var shortID: String { String(id.uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(6)) }
}

extension QuickAction {
    var shortID: String { String(id.uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(6)) }
}

/// One load -> mutate -> save transaction per operation.
enum TaskDB {
    static func read() throws -> AppData {
        var d = try DataFile.load()
        if d.rollover() { try DataFile.save(d) }
        return d
    }

    static func write<T>(_ body: (inout AppData) throws -> T) throws -> T {
        var d = try DataFile.load()
        d.rollover()
        let result = try body(&d)
        try DataFile.save(d)
        return result
    }

    // MARK: resolving references

    /// A task ref is an id prefix (>= 4 hex chars) or a case-insensitive title substring.
    static func index(of ref: String, in tasks: [TaskItem]) throws -> Int {
        let r = ref.lowercased().trimmingCharacters(in: .whitespaces)
        guard !r.isEmpty else { throw DTError("empty task reference") }
        let hex = r.replacingOccurrences(of: "-", with: "")
        if hex.count >= 4, hex.allSatisfy(\.isHexDigit) {
            let hits = tasks.indices.filter { tasks[$0].id.uuidString.replacingOccurrences(of: "-", with: "").lowercased().hasPrefix(hex) }
            if hits.count == 1 { return hits[0] }
        }
        if let exact = tasks.indices.filter({ tasks[$0].title.lowercased() == r }).onlyOne { return exact }
        let hits = tasks.indices.filter { tasks[$0].title.lowercased().contains(r) }
        if hits.count == 1 { return hits[0] }
        // Prefer a single open match over done ones.
        if let open = hits.filter({ !tasks[$0].done }).onlyOne { return open }
        if hits.isEmpty { throw DTError("no task matches '\(ref)'") }
        let list = hits.prefix(8).map { "  \(tasks[$0].shortID)  \(tasks[$0].title)" }.joined(separator: "\n")
        throw DTError("'\(ref)' matches \(hits.count) tasks, use an id:\n\(list)")
    }

    /// A subtask ref is a 1-based index or a title substring.
    static func subIndex(of ref: String, in subs: [Subtask]) throws -> Int {
        if let n = Int(ref) {
            guard n >= 1, n <= subs.count else { throw DTError("subtask #\(n) out of range (1-\(subs.count))") }
            return n - 1
        }
        let r = ref.lowercased()
        let hits = subs.indices.filter { subs[$0].title.lowercased().contains(r) }
        guard hits.count == 1 else {
            throw DTError(hits.isEmpty ? "no subtask matches '\(ref)'" : "'\(ref)' matches \(hits.count) subtasks, use its number")
        }
        return hits[0]
    }

    static func actionIndex(of ref: String, in actions: [QuickAction]) throws -> Int {
        let r = ref.lowercased()
        if let i = actions.indices.filter({ actions[$0].shortID.hasPrefix(r) || actions[$0].title.lowercased() == r }).onlyOne { return i }
        let hits = actions.indices.filter { actions[$0].title.lowercased().contains(r) }
        guard hits.count == 1 else { throw DTError(hits.isEmpty ? "no quick action matches '\(ref)'" : "'\(ref)' matches several quick actions") }
        return hits[0]
    }

    // MARK: operations

    /// Title may contain @list tokens; an explicit list wins over tokens.
    static func addTask(_ rawTitle: String, list: Bucket?, subtasks: [String] = []) throws -> TaskItem {
        var target: Bucket = .today
        var words: [Substring] = []
        for w in rawTitle.split(separator: " ") {
            if let b = Bucket.parse(String(w)) { target = b } else { words.append(w) }
        }
        let title = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { throw DTError("task title is empty") }
        var t = TaskItem(title: title, bucket: list ?? target)
        t.subtasks = subtasks.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.map { Subtask(title: $0) }
        let task = t
        try write { $0.tasks.insert(task, at: 0) }
        return task
    }

    static func mutateTask(_ ref: String, _ body: (inout TaskItem) throws -> Void) throws -> TaskItem {
        try write { d in
            let i = try index(of: ref, in: d.tasks)
            try body(&d.tasks[i])
            return d.tasks[i]
        }
    }

    static func setDone(_ ref: String, _ done: Bool) throws -> TaskItem {
        try mutateTask(ref) { t in
            t.done = done
            t.completedAt = done ? Date() : nil
        }
    }

    static func move(_ ref: String, to b: Bucket) throws -> TaskItem {
        try write { d in
            let i = try index(of: ref, in: d.tasks)
            var t = d.tasks.remove(at: i)
            t.bucket = b
            d.tasks.insert(t, at: 0)
            return t
        }
    }

    static func rename(_ ref: String, to title: String) throws -> TaskItem {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { throw DTError("title is empty") }
        return try mutateTask(ref) { $0.title = t }
    }

    static func delete(_ ref: String) throws -> TaskItem {
        try write { d in
            let i = try index(of: ref, in: d.tasks)
            return d.tasks.remove(at: i)
        }
    }

    static func clearDone(_ b: Bucket?) throws -> Int {
        try write { d in
            let before = d.tasks.count
            d.tasks.removeAll { $0.done && (b == nil || $0.bucket == b) }
            return before - d.tasks.count
        }
    }

    static func addSubtask(_ ref: String, _ title: String) throws -> TaskItem {
        let s = title.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { throw DTError("subtask title is empty") }
        return try mutateTask(ref) { $0.subtasks.append(Subtask(title: s)) }
    }

    static func setSubtaskDone(_ ref: String, _ sub: String, _ done: Bool) throws -> TaskItem {
        try mutateTask(ref) { t in
            let j = try subIndex(of: sub, in: t.subtasks)
            t.subtasks[j].done = done
        }
    }

    static func deleteSubtask(_ ref: String, _ sub: String) throws -> TaskItem {
        try mutateTask(ref) { t in
            let j = try subIndex(of: sub, in: t.subtasks)
            t.subtasks.remove(at: j)
        }
    }

    static func addAction(title: String, url: String, icon: String) throws -> QuickAction {
        let a = QuickAction(title: title.trimmingCharacters(in: .whitespaces),
                            url: url.trimmingCharacters(in: .whitespaces),
                            icon: icon.isEmpty ? "link" : icon)
        guard !a.title.isEmpty else { throw DTError("action title is empty") }
        guard a.resolvedURL != nil else { throw DTError("invalid url '\(url)'") }
        guard FA.exists(a.icon) else { throw DTError("unknown Font Awesome icon '\(a.icon)' (use names like 'rocket', 'bug', 'server')") }
        try write { $0.actions.append(a) }
        return a
    }

    static func deleteAction(_ ref: String) throws -> QuickAction {
        try write { d in
            let i = try actionIndex(of: ref, in: d.actions)
            return d.actions.remove(at: i)
        }
    }

    // MARK: JSON views (for --json and MCP)

    static func json(_ t: TaskItem) -> [String: Any] {
        var o: [String: Any] = [
            "id": t.shortID,
            "uuid": t.id.uuidString,
            "title": t.title,
            "list": t.bucket.rawValue,
            "done": t.done,
            "createdAt": ISO8601DateFormatter().string(from: t.createdAt),
            "subtasks": t.subtasks.enumerated().map { ["n": $0.offset + 1, "title": $0.element.title, "done": $0.element.done] },
        ]
        if let c = t.completedAt { o["completedAt"] = ISO8601DateFormatter().string(from: c) }
        return o
    }

    static func json(_ a: QuickAction) -> [String: Any] {
        ["id": a.shortID, "title": a.title, "url": a.url, "icon": a.icon]
    }

    static func filtered(_ d: AppData, list: Bucket?, includeDone: Bool) -> [TaskItem] {
        d.tasks.filter { (list == nil || $0.bucket == list) && (includeDone || !$0.done) }
    }

    static func jsonString(_ obj: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

extension Array {
    var onlyOne: Element? { count == 1 ? first : nil }
}
