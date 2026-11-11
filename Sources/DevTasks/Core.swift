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
        do {
            var d = try decoder.decode(AppData.self, from: raw)
            d.normalize()
            return d
        } catch {
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
    /// Publishes custom lists to the registry and rescues tasks whose list no longer exists.
    mutating func normalize() {
        ListRegistry.custom = lists
        for i in tasks.indices where !tasks[i].bucket.exists { tasks[i].bucket = .backlog }
    }

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
        let bare = s.hasPrefix("@") ? String(s.dropFirst()) : s
        return Bucket.parse("@" + bare)
            ?? Bucket.parse("@" + CustomList.slug(bare))
            ?? Bucket.parse("@" + bare.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: ""))
    }

    static var namesHelp: String { allCases.map(\.rawValue).joined(separator: " | ") }

    /// Pulls @list tokens out of a (possibly multi-line) title. Last token wins.
    static func extract(_ raw: String) -> (title: String, bucket: Bucket?) {
        var found: Bucket?
        let lines = raw.components(separatedBy: "\n").map { line in
            line.split(separator: " ", omittingEmptySubsequences: false).filter { w in
                if let b = Bucket.parse(String(w)) { found = b; return false }
                return true
            }.joined(separator: " ")
        }
        return (lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), found)
    }
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

    static func folderIndex(of ref: String, in actions: [QuickAction]) throws -> Int {
        let r = ref.lowercased()
        let folders = actions.indices.filter { actions[$0].isFolder }
        if let i = folders.filter({ actions[$0].title.lowercased() == r || actions[$0].shortID.hasPrefix(r) }).onlyOne { return i }
        let hits = folders.filter { actions[$0].title.lowercased().contains(r) }
        guard hits.count == 1 else { throw DTError(hits.isEmpty ? "no folder matches '\(ref)'" : "'\(ref)' matches several folders") }
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
        let (title, token) = Bucket.extract(rawTitle)
        guard !title.isEmpty else { throw DTError("task title is empty") }
        var t = TaskItem(title: title, bucket: list ?? token ?? .today)
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
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
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

    static func addAction(title: String, url: String, icon: String, folder: String? = nil) throws -> QuickAction {
        let a = QuickAction(title: title.trimmingCharacters(in: .whitespaces),
                            url: url.trimmingCharacters(in: .whitespaces),
                            icon: icon.isEmpty ? "link" : icon)
        guard !a.title.isEmpty else { throw DTError("action title is empty") }
        guard a.resolvedURL != nil else { throw DTError("invalid url '\(url)'") }
        guard FA.exists(a.icon) else { throw DTError("unknown Font Awesome icon '\(a.icon)' (use names like 'rocket', 'github', 'docker')") }
        try write { d in
            if let folder {
                let i = try folderIndex(of: folder, in: d.actions)
                d.actions[i].children?.append(a)
            } else {
                d.actions.append(a)
            }
        }
        return a
    }

    static func addFolder(title: String, icon: String) throws -> QuickAction {
        let f = QuickAction(title: title.trimmingCharacters(in: .whitespaces), url: "",
                            icon: icon.isEmpty ? "folder" : icon, children: [])
        guard !f.title.isEmpty else { throw DTError("folder title is empty") }
        guard FA.exists(f.icon) else { throw DTError("unknown Font Awesome icon '\(f.icon)'") }
        try write { $0.actions.append(f) }
        return f
    }

    /// Removes a top-level action/folder, or a link inside a folder.
    static func deleteAction(_ ref: String) throws -> QuickAction {
        try write { d in
            if let i = try? actionIndex(of: ref, in: d.actions) { return d.actions.remove(at: i) }
            for f in d.actions.indices where d.actions[f].isFolder {
                if let j = try? actionIndex(of: ref, in: d.actions[f].children ?? []) {
                    return d.actions[f].children!.remove(at: j)
                }
            }
            throw DTError("no quick action matches '\(ref)'")
        }
    }

    // MARK: lists

    static func addList(_ name: String, icon: String = "list-ul") throws -> CustomList {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { throw DTError("list name is empty") }
        guard FA.exists(icon) else { throw DTError("unknown Font Awesome icon '\(icon)'") }
        return try write { d in
            let l = CustomList(id: uniqueSlug(n, d.lists), name: n, icon: icon)
            d.lists.append(l)
            d.normalize()
            return l
        }
    }

    static func uniqueSlug(_ name: String, _ lists: [CustomList]) -> String {
        var base = CustomList.slug(name)
        if base.isEmpty { base = "list" }
        let taken = Set(lists.map(\.id) + Bucket.builtins.map(\.rawValue) + ["this-week", "all"])
        var s = base
        var n = 2
        while taken.contains(s) { s = "\(base)-\(n)"; n += 1 }
        return s
    }

    static func customIndex(_ ref: String, _ lists: [CustomList]) throws -> Int {
        let r = ref.lowercased().trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "")
        if let i = lists.firstIndex(where: { $0.id == r || $0.name.lowercased() == r }) { return i }
        let hits = lists.indices.filter { lists[$0].name.lowercased().contains(r) }
        guard hits.count == 1 else { throw DTError(hits.isEmpty ? "no custom list matches '\(ref)'" : "'\(ref)' matches several lists") }
        return hits[0]
    }

    /// Deletes a custom list; its tasks move to the backlog.
    static func deleteList(_ ref: String) throws -> (CustomList, Int) {
        try write { d in
            let i = try customIndex(ref, d.lists)
            let l = d.lists.remove(at: i)
            var moved = 0
            for j in d.tasks.indices where d.tasks[j].bucket.rawValue == l.id { d.tasks[j].bucket = .backlog; moved += 1 }
            d.normalize()
            return (l, moved)
        }
    }

    static func renameList(_ ref: String, to name: String) throws -> CustomList {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { throw DTError("list name is empty") }
        return try write { d in
            let i = try customIndex(ref, d.lists)
            d.lists[i].name = n
            d.normalize()
            return d.lists[i]
        }
    }

    // MARK: prompts (snippet collections on the quick-action bar)

    static func promptCollectionIndex(_ ref: String?, in d: inout AppData, create: Bool) throws -> Int {
        let cols = d.actions.indices.filter { d.actions[$0].isSnippets }
        if let ref, !ref.isEmpty {
            let r = ref.lowercased()
            if let i = cols.filter({ d.actions[$0].title.lowercased() == r || d.actions[$0].shortID.hasPrefix(r) }).onlyOne { return i }
            if let i = cols.filter({ d.actions[$0].title.lowercased().contains(r) }).onlyOne { return i }
            guard create else { throw DTError("no prompts button matches '\(ref)'") }
            d.actions.append(QuickAction(title: ref, url: "", icon: "wand-magic-sparkles", snippets: []))
            return d.actions.count - 1
        }
        if let first = cols.first { return first }
        guard create else { throw DTError("no prompts button yet") }
        d.actions.append(QuickAction(title: "Prompts", url: "", icon: "wand-magic-sparkles", snippets: []))
        return d.actions.count - 1
    }

    /// Adds a prompt to a prompts button (created as "Prompts" if there is none).
    static func addPrompt(title: String, text: String, collection: String?) throws -> (Snippet, String) {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw DTError("prompt text is empty") }
        var name = title.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { name = String(body.split(separator: "\n").first ?? "prompt").prefix(40).description }
        let snip = Snippet(title: name, text: body)
        let colName: String = try write { d in
            let i = try promptCollectionIndex(collection, in: &d, create: true)
            d.actions[i].snippets?.append(snip)
            return d.actions[i].title
        }
        return (snip, colName)
    }

    static func allPrompts(_ d: AppData) -> [(collection: String, snippet: Snippet)] {
        d.actions.filter(\.isSnippets).flatMap { a in (a.snippets ?? []).map { (a.title, $0) } }
    }

    static func findPrompt(_ ref: String, in d: AppData) throws -> Snippet {
        let all = allPrompts(d).map(\.snippet)
        let r = ref.lowercased()
        if let s = all.filter({ $0.shortID.hasPrefix(r) || $0.title.lowercased() == r }).onlyOne { return s }
        let hits = all.filter { $0.title.lowercased().contains(r) }
        guard hits.count == 1 else { throw DTError(hits.isEmpty ? "no prompt matches '\(ref)'" : "'\(ref)' matches \(hits.count) prompts") }
        return hits[0]
    }

    static func json(_ s: Snippet, collection: String) -> [String: Any] {
        ["id": s.shortID, "title": s.title, "text": s.text, "collection": collection]
    }

    // MARK: notes

    static func noteIndex(of ref: String, in notes: [Note]) throws -> Int {
        let r = ref.lowercased().trimmingCharacters(in: .whitespaces)
        if r.count >= 4, r.allSatisfy(\.isHexDigit), let i = notes.indices.filter({ notes[$0].shortID.hasPrefix(r) || notes[$0].id.uuidString.lowercased().replacingOccurrences(of: "-", with: "").hasPrefix(r) }).onlyOne { return i }
        let hits = notes.indices.filter { notes[$0].text.lowercased().contains(r) }
        if let i = hits.filter({ notes[$0].title.lowercased().contains(r) }).onlyOne ?? hits.onlyOne { return i }
        if hits.isEmpty { throw DTError("no note matches '\(ref)'") }
        let list = hits.prefix(8).map { "  \(notes[$0].shortID)  \(notes[$0].title)" }.joined(separator: "\n")
        throw DTError("'\(ref)' matches \(hits.count) notes, use an id:\n\(list)")
    }

    static func addNote(_ text: String) throws -> Note {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw DTError("note is empty") }
        let n = Note(text: t)
        try write { $0.notes.insert(n, at: 0) }
        return n
    }

    static func appendNote(_ ref: String, _ text: String) throws -> Note {
        try write { d in
            let i = try noteIndex(of: ref, in: d.notes)
            d.notes[i].text += (d.notes[i].text.hasSuffix("\n") || d.notes[i].text.isEmpty ? "" : "\n") + text
            d.notes[i].updatedAt = Date()
            return d.notes[i]
        }
    }

    static func deleteNote(_ ref: String) throws -> Note {
        try write { d in
            let i = try noteIndex(of: ref, in: d.notes)
            return d.notes.remove(at: i)
        }
    }

    static func json(_ n: Note) -> [String: Any] {
        ["id": n.shortID, "title": n.title, "text": n.text, "updatedAt": ISO8601DateFormatter().string(from: n.updatedAt)]
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
        if let snips = a.snippets {
            return ["id": a.shortID, "title": a.title, "icon": a.icon, "prompts": snips.map { json($0, collection: a.title) }]
        }
        if let kids = a.children {
            return ["id": a.shortID, "title": a.title, "icon": a.icon, "folder": true, "links": kids.map(json)]
        }
        return ["id": a.shortID, "title": a.title, "url": a.url, "icon": a.icon]
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
