import SwiftUI
import AppKit

final class Store: ObservableObject {
    @Published var tasks: [TaskItem] = [] { didSet { if !applyingExternal { scheduleSave() } } }
    @Published var actions: [QuickAction] = [] { didSet { if !applyingExternal { scheduleSave() } } }
    @Published var selected: Bucket = .today
    @Published var focusQuickAdd = 0

    private var lastDay: String
    private var pendingSave: DispatchWorkItem?
    private var applyingExternal = false
    /// Bytes we last read or wrote; anything else on disk came from the CLI / MCP.
    private var lastSynced: Data?
    private var watcher: DispatchSourceFileSystemObject?

    init() {
        var data = AppData()
        do {
            data = try DataFile.load()
        } catch {
            // Never silently overwrite an unreadable file: keep a copy aside.
            let backup = DataFile.directory.appendingPathComponent("data.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: DataFile.url, to: backup)
        }
        lastSynced = try? Data(contentsOf: DataFile.url)
        tasks = data.tasks
        actions = data.actions
        lastDay = data.lastDay

        rollover()
        startWatching()

        let nc = NotificationCenter.default
        nc.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in self?.rollover() }
        nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.reloadIfChanged()
            self?.rollover()
        }
        nc.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in self?.saveNow() }
    }

    // MARK: - Day rollover

    func rollover() {
        var d = snapshot()
        guard d.rollover() else { return }
        tasks = d.tasks
        lastDay = d.lastDay
        scheduleSave()
    }

    // MARK: - External changes (CLI / MCP)

    private func startWatching() {
        let fd = Darwin.open(DataFile.directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename], queue: .main)
        src.setEventHandler { [weak self] in self?.reloadIfChanged() }
        src.setCancelHandler { close(fd) }
        src.resume()
        watcher = src
    }

    private func reloadIfChanged() {
        guard let raw = try? Data(contentsOf: DataFile.url), raw != lastSynced,
              let d = try? DataFile.decoder.decode(AppData.self, from: raw) else { return }
        lastSynced = raw
        pendingSave?.cancel()
        applyingExternal = true
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            tasks = d.tasks
            actions = d.actions
        }
        lastDay = d.lastDay
        applyingExternal = false
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

    private func snapshot() -> AppData {
        var d = AppData()
        d.tasks = tasks
        d.actions = actions
        d.lastDay = lastDay
        return d
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    func saveNow() {
        pendingSave?.cancel()
        // An agent wrote while we had unsaved edits: take theirs rather than clobber it.
        if let disk = try? Data(contentsOf: DataFile.url), disk != lastSynced {
            reloadIfChanged()
            return
        }
        do {
            lastSynced = try DataFile.save(snapshot())
        } catch {
            NSLog("DevTasks: save failed: \(error)")
        }
    }
}
