import SwiftUI
import AppKit

final class Store: ObservableObject {
    @Published var tasks: [TaskItem] = [] { didSet { scheduleSave() } }
    @Published var actions: [QuickAction] = [] { didSet { scheduleSave() } }
    @Published var selected: Bucket = .today
    @Published var focusQuickAdd = 0

    private var lastDay: String
    private let fileURL: URL
    private var pendingSave: DispatchWorkItem?

    static var dataDirectory: URL {
        if let custom = ProcessInfo.processInfo.environment["DEVTASKS_DATA_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DevTasks", isDirectory: true)
    }

    init() {
        let dir = Store.dataDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("data.json")

        var data = AppData()
        if let raw = try? Data(contentsOf: fileURL) {
            do {
                data = try Store.decoder.decode(AppData.self, from: raw)
            } catch {
                // Never silently overwrite an unreadable file: keep a copy aside.
                let backup = dir.appendingPathComponent("data.corrupt-\(Int(Date().timeIntervalSince1970)).json")
                try? FileManager.default.copyItem(at: fileURL, to: backup)
            }
        }
        tasks = data.tasks
        actions = data.actions
        lastDay = data.lastDay

        rollover()

        let nc = NotificationCenter.default
        nc.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in self?.rollover() }
        nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.rollover() }
        nc.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in self?.saveNow() }
    }

    // MARK: - Day rollover

    static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// On a new day, open "tomorrow" tasks become "today" tasks.
    func rollover() {
        let today = Store.dayKey(Date())
        guard today > lastDay else { return }
        for i in tasks.indices where tasks[i].bucket == .tomorrow && !tasks[i].done {
            tasks[i].bucket = .today
        }
        lastDay = today
        scheduleSave()
    }

    // MARK: - Queries

    func open(_ b: Bucket) -> [TaskItem] { tasks.filter { $0.bucket == b && !$0.done } }
    func done(_ b: Bucket) -> [TaskItem] {
        tasks.filter { $0.bucket == b && $0.done }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }
    var doneToday: Int {
        tasks.filter { $0.completedAt.map(Calendar.current.isDateInToday) ?? false }.count
    }
    private func index(_ id: UUID) -> Int? { tasks.firstIndex { $0.id == id } }

    // MARK: - Task mutations

    @discardableResult
    func add(_ title: String, to bucket: Bucket) -> Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        tasks.insert(TaskItem(title: t, bucket: bucket), at: 0)
        return true
    }

    func setDone(_ id: UUID, _ done: Bool) {
        guard let i = index(id) else { return }
        tasks[i].done = done
        tasks[i].completedAt = done ? Date() : nil
    }

    func move(_ id: UUID, to bucket: Bucket) {
        guard let i = index(id), tasks[i].bucket != bucket else { return }
        var t = tasks.remove(at: i)
        t.bucket = bucket
        tasks.insert(t, at: 0)
    }

    func delete(_ id: UUID) { tasks.removeAll { $0.id == id } }

    func clearDone(_ bucket: Bucket) { tasks.removeAll { $0.bucket == bucket && $0.done } }

    func titleBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { [weak self] in self?.tasks.first { $0.id == id }?.title ?? "" },
            set: { [weak self] v in
                guard let self, let i = self.index(id) else { return }
                self.tasks[i].title = v
            }
        )
    }

    // MARK: - Subtasks

    func addSubtask(_ id: UUID, _ title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let i = index(id) else { return }
        tasks[i].subtasks.append(Subtask(title: t))
    }

    func toggleSubtask(_ id: UUID, _ sid: UUID) {
        guard let i = index(id), let j = tasks[i].subtasks.firstIndex(where: { $0.id == sid }) else { return }
        tasks[i].subtasks[j].done.toggle()
    }

    func deleteSubtask(_ id: UUID, _ sid: UUID) {
        guard let i = index(id) else { return }
        tasks[i].subtasks.removeAll { $0.id == sid }
    }

    func subtaskBinding(_ id: UUID, _ sid: UUID) -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.tasks.first { $0.id == id }?.subtasks.first { $0.id == sid }?.title ?? ""
            },
            set: { [weak self] v in
                guard let self, let i = self.index(id),
                      let j = self.tasks[i].subtasks.firstIndex(where: { $0.id == sid }) else { return }
                self.tasks[i].subtasks[j].title = v
            }
        )
    }

    // MARK: - Quick actions

    func upsert(_ a: QuickAction) {
        if let i = actions.firstIndex(where: { $0.id == a.id }) { actions[i] = a } else { actions.append(a) }
    }

    func deleteAction(_ id: UUID) { actions.removeAll { $0.id == id } }

    func moveAction(_ id: UUID, by offset: Int) {
        guard let i = actions.firstIndex(where: { $0.id == id }) else { return }
        let j = i + offset
        guard actions.indices.contains(j) else { return }
        actions.swapAt(i, j)
    }

    // MARK: - Persistence

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    func saveNow() {
        pendingSave?.cancel()
        var data = AppData()
        data.tasks = tasks
        data.actions = actions
        data.lastDay = lastDay
        do {
            try Store.encoder.encode(data).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("DevTasks: save failed: \(error)")
        }
    }
}
