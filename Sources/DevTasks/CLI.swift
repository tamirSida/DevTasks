import Foundation
import AppKit

/// `devtasks <command>`: the same binary as the app, run from a terminal or by an agent.
enum CLI {
    static let commands: Set<String> = [
        "add", "list", "ls", "done", "undo", "reopen", "move", "mv", "edit", "rename", "rm", "delete",
        "sub", "clear", "action", "actions", "mcp", "path", "help", "--help", "-h", "version", "--version",
        "paste", "copy", "note", "notes", "lists", "prompt", "prompts",
    ]

    static func handles(_ args: [String]) -> Bool {
        args.count > 1 && commands.contains(args[1])
    }

    // MARK: arg parsing

    struct Args {
        var positional: [String] = []
        var values: [String: [String]] = [:]
        var flags: Set<String> = []

        func value(_ names: String...) -> String? { names.lazy.compactMap { values[$0]?.last }.first }
        func all(_ names: String...) -> [String] { names.flatMap { values[$0] ?? [] } }
        func has(_ names: String...) -> Bool { names.contains { flags.contains($0) } }
    }

    static let boolFlags: Set<String> = ["--json", "-j", "--all", "-a"]
    static let valueOptions: Set<String> = ["--list", "-l", "--sub", "-s", "--icon", "-i", "--in"]

    /// Lets shell users type \n for a line break.
    static func unescape(_ s: String) -> String { s.replacingOccurrences(of: "\\n", with: "\n") }

    static func parse(_ raw: [String]) -> Args {
        var a = Args()
        var i = 0
        while i < raw.count {
            let x = raw[i]
            if valueOptions.contains(x), i + 1 < raw.count {
                a.values[x, default: []].append(raw[i + 1])
                i += 2
                continue
            }
            if boolFlags.contains(x) { a.flags.insert(x) } else { a.positional.append(x) }
            i += 1
        }
        return a
    }

    static func bucket(_ s: String?) throws -> Bucket? {
        guard let s else { return nil }
        guard let b = Bucket.named(s) else { throw DTError("unknown list '\(s)' (\(Bucket.namesHelp))") }
        return b
    }

    // MARK: run

    static func run(_ argv: [String]) -> Int32 {
        let cmd = argv[1]
        let a = parse(Array(argv.dropFirst(2)))
        let json = a.has("--json", "-j")
        _ = try? DataFile.load() // registers custom lists before any list names are parsed
        do {
            switch cmd {
            case "mcp":
                MCPServer.run()
            case "help", "--help", "-h":
                print(usage)
            case "version", "--version":
                print("devtasks 1.1")
            case "path":
                print(DataFile.url.path)

            case "add":
                guard !a.positional.isEmpty else { throw DTError("usage: devtasks add <title> [@list | --list <list>] [--sub <title>]...") }
                let t = try TaskDB.addTask(unescape(a.positional.joined(separator: " ")), list: try bucket(a.value("--list", "-l")),
                                           subtasks: a.all("--sub", "-s").map(unescape))
                emit(t, json, verb: "added")

            case "paste":
                // Clipboard -> task, keeping embedded links (e.g. a copied Azure DevOps work item).
                let pb = NSPasteboard.general
                guard let text = LinkFormat.fromPasteboard(pb) ?? pb.string(forType: .string),
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw DTError("clipboard is empty")
                }
                let list = try bucket(a.value("--list", "-l") ?? a.positional.first)
                emit(try TaskDB.addTask(text, list: list), json, verb: "added")

            case "copy":
                let d = try TaskDB.read()
                let t = d.tasks[try TaskDB.index(of: try refs(a)[0], in: d.tasks)]
                LinkFormat.copy(t.title)
                print(json ? TaskDB.jsonString(TaskDB.json(t)) : "copied \(t.shortID)  \(LinkFormat.plain(t.title))")

            case "list", "ls":
                let d = try TaskDB.read()
                let which = a.positional.first
                let list: Bucket? = (which == nil || which == "all") ? nil : try bucket(which)
                let items = TaskDB.filtered(d, list: list, includeDone: a.has("--all", "-a"))
                if json { print(TaskDB.jsonString(items.map(TaskDB.json))) } else { printList(items, only: list) }

            case "done":
                try refs(a).forEach { emit(try TaskDB.setDone($0, true), json, verb: "done") }
            case "undo", "reopen":
                try refs(a).forEach { emit(try TaskDB.setDone($0, false), json, verb: "reopened") }
            case "rm", "delete":
                try refs(a).forEach { emit(try TaskDB.delete($0), json, verb: "deleted") }

            case "move", "mv":
                guard a.positional.count >= 2, let b = try bucket(a.positional.last) else {
                    throw DTError("usage: devtasks move <task> <list>")
                }
                var rest = a
                rest.positional.removeLast()
                try refs(rest).forEach { emit(try TaskDB.move($0, to: b), json, verb: "moved") }

            case "edit", "rename":
                guard a.positional.count >= 2 else { throw DTError("usage: devtasks edit <task> <new title>") }
                emit(try TaskDB.rename(a.positional[0], to: unescape(a.positional.dropFirst().joined(separator: " "))), json, verb: "renamed")

            case "clear":
                let n = try TaskDB.clearDone(try bucket(a.positional.first == "all" ? nil : a.positional.first))
                print(json ? TaskDB.jsonString(["removed": n]) : "cleared \(n) done task\(n == 1 ? "" : "s")")

            case "lists":
                try runLists(a, json)
            case "prompt", "prompts":
                try runPrompt(a, json)
            case "note", "notes":
                try runNote(a, json)
            case "sub":
                try runSub(a, json)
            case "action", "actions":
                try runAction(a, json)
            default:
                print(usage)
            }
            return 0
        } catch {
            if json {
                print(TaskDB.jsonString(["error": "\(error)"]))
            } else {
                FileHandle.standardError.write(Data("devtasks: \(error)\n".utf8))
            }
            return 1
        }
    }

    private static func refs(_ a: Args) throws -> [String] {
        guard !a.positional.isEmpty else { throw DTError("missing task reference (id prefix or part of the title)") }
        // Quoted multi-word titles arrive as one arg; unquoted words are joined into one ref.
        return a.positional.count > 1 && a.positional.allSatisfy(isShortID) ? a.positional : [a.positional.joined(separator: " ")]
    }

    private static func isShortID(_ s: String) -> Bool { s.count >= 4 && s.count <= 32 && s.allSatisfy(\.isHexDigit) }

    private static func runSub(_ a: Args, _ json: Bool) throws {
        let p = a.positional
        guard p.count >= 3 else { throw DTError("usage: devtasks sub add|done|undo|rm <task> <subtask title | n>") }
        let rest = p.dropFirst(2).joined(separator: " ")
        switch p[0] {
        case "add": emit(try TaskDB.addSubtask(p[1], unescape(rest)), json, verb: "subtask added to")
        case "done": emit(try TaskDB.setSubtaskDone(p[1], rest, true), json, verb: "subtask done in")
        case "undo", "reopen": emit(try TaskDB.setSubtaskDone(p[1], rest, false), json, verb: "subtask reopened in")
        case "rm", "delete": emit(try TaskDB.deleteSubtask(p[1], rest), json, verb: "subtask removed from")
        default: throw DTError("unknown sub command '\(p[0])'")
        }
    }

    private static func runPrompt(_ a: Args, _ json: Bool) throws {
        let p = a.positional
        switch p.first ?? "list" {
        case "list", "ls":
            let all = TaskDB.allPrompts(try TaskDB.read())
            if json { print(TaskDB.jsonString(all.map { TaskDB.json($0.snippet, collection: $0.collection) })); return }
            if all.isEmpty { print("no prompts") }
            for (c, s) in all { print("\(s.shortID)  [\(c)] \(s.title)") }
        case "add":
            // devtasks prompt add <title> <text...>   or pipe the text: pbpaste | devtasks prompt add <title>
            guard p.count >= 2 else { throw DTError("usage: devtasks prompt add <title> <text> [--in <prompts button>]") }
            var text = unescape(p.dropFirst(2).joined(separator: " "))
            if text.isEmpty, isatty(0) == 0 { text = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self) }
            let (s, col) = try TaskDB.addPrompt(title: p[1], text: text, collection: a.value("--in"))
            print(json ? TaskDB.jsonString(TaskDB.json(s, collection: col)) : "added prompt \(s.shortID)  \(s.title)  [\(col)]")
        case "show", "cat":
            guard p.count >= 2 else { throw DTError("usage: devtasks prompt show <prompt>") }
            print(try TaskDB.findPrompt(p.dropFirst().joined(separator: " "), in: try TaskDB.read()).text)
        case "copy":
            guard p.count >= 2 else { throw DTError("usage: devtasks prompt copy <prompt>") }
            let s = try TaskDB.findPrompt(p.dropFirst().joined(separator: " "), in: try TaskDB.read())
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(s.text, forType: .string)
            print("copied \(s.title)")
        default:
            throw DTError("usage: devtasks prompt [list | add <title> <text> | show <prompt> | copy <prompt>]")
        }
    }

    private static func runLists(_ a: Args, _ json: Bool) throws {
        let p = a.positional
        switch p.first ?? "ls" {
        case "ls", "list":
            let d = try TaskDB.read()
            let rows: [[String: Any]] = Bucket.allCases.map { b in
                ["id": b.rawValue, "name": b.title, "icon": b.icon, "builtin": b.isBuiltin,
                 "open": d.tasks.filter { $0.bucket == b && !$0.done }.count]
            }
            if json { print(TaskDB.jsonString(rows)); return }
            for r in rows {
                let id = (r["id"] as! String).padding(toLength: 18, withPad: " ", startingAt: 0)
                print("\(id) \((r["name"] as! String).padding(toLength: 20, withPad: " ", startingAt: 0)) \(r["open"]!) open\((r["builtin"] as! Bool) ? "" : "  (custom)")")
            }
        case "add", "new":
            guard p.count >= 2 else { throw DTError("usage: devtasks lists add <name> [--icon name]") }
            let l = try TaskDB.addList(p.dropFirst().joined(separator: " "), icon: a.value("--icon", "-i") ?? "list-ul")
            print(json ? TaskDB.jsonString(["id": l.id, "name": l.name, "icon": l.icon]) : "added list \(l.id)  (\(l.name))  use @\(l.id) when adding tasks")
        case "rename":
            guard p.count >= 3 else { throw DTError("usage: devtasks lists rename <list> <new name>") }
            let l = try TaskDB.renameList(p[1], to: p.dropFirst(2).joined(separator: " "))
            print(json ? TaskDB.jsonString(["id": l.id, "name": l.name, "icon": l.icon]) : "renamed list \(l.id) to \(l.name)")
        case "rm", "delete":
            guard p.count >= 2 else { throw DTError("usage: devtasks lists rm <list>") }
            let (l, moved) = try TaskDB.deleteList(p.dropFirst().joined(separator: " "))
            print(json ? TaskDB.jsonString(["id": l.id, "movedToBacklog": moved]) : "deleted list \(l.name); \(moved) task\(moved == 1 ? "" : "s") moved to backlog")
        default:
            throw DTError("usage: devtasks lists [ls | add <name> | rename <list> <name> | rm <list>]")
        }
    }

    private static func runNote(_ a: Args, _ json: Bool) throws {
        let p = a.positional
        switch p.first ?? "list" {
        case "list", "ls":
            let notes = try TaskDB.read().notes
            if json { print(TaskDB.jsonString(notes.map(TaskDB.json))); return }
            if notes.isEmpty { print("no notes") }
            for n in notes { print("\(n.shortID)  \(n.title)") }
        case "add", "new":
            var text = unescape(p.dropFirst().joined(separator: " "))
            if text.isEmpty, isatty(0) == 0 { text = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self) }
            let n = try TaskDB.addNote(text)
            print(json ? TaskDB.jsonString(TaskDB.json(n)) : "added note \(n.shortID)  \(n.title)")
        case "show", "cat":
            guard p.count >= 2 else { throw DTError("usage: devtasks note show <note>") }
            let d = try TaskDB.read()
            let n = d.notes[try TaskDB.noteIndex(of: p.dropFirst().joined(separator: " "), in: d.notes)]
            print(json ? TaskDB.jsonString(TaskDB.json(n)) : n.text)
        case "append":
            guard p.count >= 3 else { throw DTError("usage: devtasks note append <note> <text>") }
            let n = try TaskDB.appendNote(p[1], unescape(p.dropFirst(2).joined(separator: " ")))
            print(json ? TaskDB.jsonString(TaskDB.json(n)) : "appended to \(n.shortID)  \(n.title)")
        case "rm", "delete":
            guard p.count >= 2 else { throw DTError("usage: devtasks note rm <note>") }
            let n = try TaskDB.deleteNote(p.dropFirst().joined(separator: " "))
            print(json ? TaskDB.jsonString(TaskDB.json(n)) : "deleted note \(n.title)")
        default:
            throw DTError("usage: devtasks note [list | add <text> | show <note> | append <note> <text> | rm <note>]")
        }
    }

    private static func runAction(_ a: Args, _ json: Bool) throws {
        let p = a.positional
        switch p.first ?? "list" {
        case "list", "ls":
            let acts = try TaskDB.read().actions
            if json { print(TaskDB.jsonString(acts.map(TaskDB.json))); return }
            if acts.isEmpty { print("no quick actions") }
            func row(_ x: QuickAction, _ indent: String) -> String {
                "\(indent)\(x.shortID)  \(x.title.padding(toLength: 22, withPad: " ", startingAt: 0)) fa-\(x.icon.padding(toLength: 18, withPad: " ", startingAt: 0)) \(x.isFolder ? "(folder)" : x.isSnippets ? "(prompts)" : x.url)"
            }
            for x in acts {
                print(row(x, ""))
                for c in x.children ?? [] { print(row(c, "  - ")) }
                for s in x.snippets ?? [] { print("  - \(s.shortID)  \(s.title)  (prompt)") }
            }
        case "add":
            guard p.count >= 3 else { throw DTError("usage: devtasks action add <title> <url> [--icon name] [--in <folder>]") }
            let x = try TaskDB.addAction(title: p[1], url: p[2], icon: a.value("--icon", "-i") ?? "link", folder: a.value("--in"))
            print(json ? TaskDB.jsonString(TaskDB.json(x)) : "added action \(x.shortID)  \(x.title)")
        case "folder":
            guard p.count >= 2 else { throw DTError("usage: devtasks action folder <title> [--icon name]") }
            let x = try TaskDB.addFolder(title: p.dropFirst().joined(separator: " "), icon: a.value("--icon", "-i") ?? "folder")
            print(json ? TaskDB.jsonString(TaskDB.json(x)) : "added folder \(x.shortID)  \(x.title)")
        case "rm", "delete":
            guard p.count >= 2 else { throw DTError("usage: devtasks action rm <action>") }
            let x = try TaskDB.deleteAction(p.dropFirst().joined(separator: " "))
            print(json ? TaskDB.jsonString(TaskDB.json(x)) : "deleted action \(x.title)")
        default:
            throw DTError("usage: devtasks action [list | add <title> <url> [--icon <name>] [--in <folder>] | folder <title> | rm <action>]")
        }
    }

    // MARK: output

    private static func emit(_ t: TaskItem, _ json: Bool, verb: String) {
        if json { print(TaskDB.jsonString(TaskDB.json(t))); return }
        print("\(verb) \(t.shortID)  \(t.title)  [\(t.bucket.path)]")
    }

    private static func line(_ t: TaskItem) -> String {
        var s = "  \(t.done ? "[x]" : "[ ]") \(t.shortID)  \(t.title.replacingOccurrences(of: "\n", with: "\n" + String(repeating: " ", count: 14)))"
        if !t.subtasks.isEmpty { s += "  (\(t.subtasks.filter(\.done).count)/\(t.subtasks.count))" }
        for (n, sub) in t.subtasks.enumerated() { s += "\n           \(n + 1). \(sub.done ? "[x]" : "[ ]") \(sub.title)" }
        return s
    }

    private static func printList(_ items: [TaskItem], only: Bucket?) {
        let buckets = only.map { [$0] } ?? Bucket.allCases
        var printed = false
        for b in buckets {
            let group = items.filter { $0.bucket == b }
            if group.isEmpty && only == nil { continue }
            if printed { print("") }
            print(b.path)
            if group.isEmpty { print("  (empty)") }
            for t in group.sorted(by: { !$0.done && $1.done }) { print(line(t)) }
            printed = true
        }
        if !printed { print("no open tasks") }
    }

    static let usage = """
    devtasks - command line for DevTasks (edits the same data the app shows, live)

    tasks
      devtasks add <title> [@today|@tomorrow|@week|@backlog|@<custom-list>] [--list <list>] [--sub <subtask>]...
      devtasks list [today|tomorrow|week|backlog|all] [--all] [--json]
      devtasks done <task>...          mark complete
      devtasks undo <task>...          reopen
      devtasks move <task> <list>
      devtasks edit <task> <new title>
      devtasks rm <task>...
      devtasks clear [list|all]        delete completed tasks

    lists
      devtasks lists                   show all lists (built-in + custom)
      devtasks lists add <name> [--icon <name>]
      devtasks lists rename <list> <new name>
      devtasks lists rm <list>         its tasks move to backlog

    subtasks
      devtasks sub add  <task> <title>
      devtasks sub done <task> <n | title>
      devtasks sub undo <task> <n | title>
      devtasks sub rm   <task> <n | title>

    quick actions
      devtasks action list
      devtasks action add <title> <url> [--icon <font-awesome-name>] [--in <folder>]
      devtasks action folder <title> [--icon <name>]      a dropdown of links
      devtasks action rm <action>

    prompts (a quick-action button whose items copy text)
      devtasks prompt list
      devtasks prompt add <title> <text> [--in <prompts button>]   (or pipe the text in)
      devtasks prompt show <prompt>
      devtasks prompt copy <prompt>

    notes
      devtasks note list
      devtasks note add <text>         (or pipe text in: pbpaste | devtasks note add)
      devtasks note show <note>
      devtasks note append <note> <text>
      devtasks note rm <note>

    clipboard
      devtasks paste [list]            add a task from the clipboard, keeping embedded links
                                       (copy a work item title in Azure DevOps, then run this)
      devtasks copy <task>             copy a task; links stay clickable when pasted in chats

    other
      devtasks mcp                     run as an MCP server (stdio)
      devtasks path                    print the data file location

    <task> is an id prefix from `list` (e.g. a1b2c3) or any unique part of the title.
    Use \\n in titles for a line break. URLs in titles become clickable links in the app.
    Use [text](url) for a link with its own label, e.g. [PBI 1234: Fix login](https://dev.azure.com/...).
    Add --json to any command for machine-readable output.
    """
}
