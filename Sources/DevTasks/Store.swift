import SwiftUI
import AppKit

final class Store: ObservableObject {
    @Published var tasks: [TaskItem] = [] { didSet { if !applyingExternal { scheduleSave() } } }
    @Published var actions: [QuickAction] = [] { didSet { if !applyingExternal { scheduleSave() } } }
    @Published var notes: [Note] = [] { didSet { if !applyingExternal { scheduleSave() } } }
    @Published var lists: [CustomList] = [] {
        didSet {
            ListRegistry.custom = lists
            if !applyingExternal { scheduleSave() }
        }
    }
    @Published var selected: Bucket = .today
    @Published var showNotes = UserDefaults.standard.bool(forKey: "showNotes") {
        didSet { UserDefaults.standard.set(showNotes, forKey: "showNotes") }
    }
    @Published var selectedNote: UUID?
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
        lists = data.lists
        ListRegistry.custom = data.lists
        tasks = data.tasks
        notes = data.notes
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
              var d = try? DataFile.decoder.decode(AppData.self, from: raw) else { return }
        d.normalize()
        lastSynced = raw
        pendingSave?.cancel()
        applyingExternal = true
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            lists = d.lists
            if !selected.exists { selected = .today }
            tasks = d.tasks
            notes = d.notes
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

    // MARK: - Custom lists

    @discardableResult
    func addList(_ name: String, icon: String = "list-ul") -> Bucket? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return nil }
        let l = CustomList(id: TaskDB.uniqueSlug(n, lists), name: n, icon: icon)
        lists.append(l)
        let b = Bucket(raw: l.id)
        selected = b
        showNotes = false
        return b
    }

    func renameList(_ id: String, to name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, let i = lists.firstIndex(where: { $0.id == id }) else { return }
        lists[i].name = n
    }

    func setListIcon(_ id: String, _ icon: String) {
        guard let i = lists.firstIndex(where: { $0.id == id }) else { return }
        lists[i].icon = icon
    }

    /// Tasks in a deleted list move to the backlog.
    func deleteList(_ id: String) {
        for i in tasks.indices where tasks[i].bucket.rawValue == id { tasks[i].bucket = .backlog }
        lists.removeAll { $0.id == id }
        if selected.rawValue == id { selected = .today }
    }

    // MARK: - Prompts

    var promptCollections: [QuickAction] { actions.filter(\.isSnippets) }

    /// Saves text as a prompt; creates a "Prompts" button when there is none.
    func savePrompt(title: String, text: String, into collectionID: UUID?) {
        let snip = Snippet(title: title.isEmpty ? "prompt" : title, text: text)
        if let id = collectionID, let i = actions.firstIndex(where: { $0.id == id }) {
            actions[i].snippets?.append(snip)
        } else if let i = actions.firstIndex(where: \.isSnippets) {
            actions[i].snippets?.append(snip)
        } else {
            actions.append(QuickAction(title: "Prompts", url: "", icon: "wand-magic-sparkles", snippets: [snip]))
        }
    }

    // MARK: - Notes

    @discardableResult
    func newNote() -> UUID {
        let n = Note()
        notes.insert(n, at: 0)
        selectedNote = n.id
        showNotes = true
        return n.id
    }

    func deleteNote(_ id: UUID) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        notes.remove(at: i)
        if selectedNote == id { selectedNote = notes.indices.contains(i) ? notes[i].id : notes.last?.id }
    }

    func noteBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { [weak self] in self?.notes.first { $0.id == id }?.text ?? "" },
            set: { [weak self] v in
                guard let self, let i = self.notes.firstIndex(where: { $0.id == id }), self.notes[i].text != v else { return }
                self.notes[i].text = v
                self.notes[i].updatedAt = Date()
            }
        )
    }

    // MARK: - Quick actions

    func upsert(_ a: QuickAction) {
        if let i = actions.firstIndex(where: { $0.id == a.id }) { actions[i] = a } else { actions.append(a) }
    }

    func deleteAction(_ id: UUID) { actions.removeAll { $0.id == id } }

    func moveAction(_ id: UUID, intoFolder folderID: UUID) {
        guard let i = actions.firstIndex(where: { $0.id == id }), !actions[i].isFolder else { return }
        let a = actions.remove(at: i)
        guard let f = actions.firstIndex(where: { $0.id == folderID }) else { actions.insert(a, at: i); return }
        actions[f].children?.append(a)
    }

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
        d.notes = notes
        d.lists = lists
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
