import Foundation

/// Minimal MCP server over stdio (newline-delimited JSON-RPC 2.0). No dependencies.
/// Register with an agent as: command `devtasks`, args `["mcp"]`.
enum MCPServer {
    static func run() {
        setvbuf(stdout, nil, _IOLBF, 0)
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty,
                  let data = line.data(using: .utf8),
                  let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                send(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "parse error"]])
                continue
            }
            handle(msg)
        }
    }

    private static func send(_ obj: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: obj, options: [.withoutEscapingSlashes]) else { return }
        FileHandle.standardOutput.write(d)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func handle(_ msg: [String: Any]) {
        let method = msg["method"] as? String ?? ""
        guard let id = msg["id"] else { return } // notifications need no reply
        let params = msg["params"] as? [String: Any] ?? [:]

        func reply(_ result: [String: Any]) { send(["jsonrpc": "2.0", "id": id, "result": result]) }

        switch method {
        case "initialize":
            let clientVersion = params["protocolVersion"] as? String ?? "2025-06-18"
            reply([
                "protocolVersion": clientVersion,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "devtasks", "version": "1.1"],
                "instructions": "Manage the user's DevTasks todo app. Lists: today, tomorrow, week, backlog. Tasks are referenced by the short id returned from list_tasks/add_task, or a unique part of the title. Changes appear in the open app immediately.",
            ])
        case "ping":
            reply([:])
        case "tools/list":
            reply(["tools": tools])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            do {
                let out = try call(name, args)
                reply(["content": [["type": "text", "text": TaskDB.jsonString(out)]], "isError": false])
            } catch {
                reply(["content": [["type": "text", "text": "Error: \(error)"]], "isError": true])
            }
        default:
            send(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "method not found: \(method)"]])
        }
    }

    // MARK: tools

    private static func str(_ a: [String: Any], _ k: String) throws -> String {
        guard let v = a[k] as? String, !v.isEmpty else { throw DTError("missing argument '\(k)'") }
        return v
    }

    private static func list(_ a: [String: Any], _ k: String = "list") throws -> Bucket? {
        guard let s = a[k] as? String, !s.isEmpty, s != "all" else { return nil }
        guard let b = Bucket.named(s) else { throw DTError("unknown list '\(s)' (\(Bucket.namesHelp))") }
        return b
    }

    private static func call(_ name: String, _ a: [String: Any]) throws -> Any {
        switch name {
        case "list_tasks":
            let d = try TaskDB.read()
            return TaskDB.filtered(d, list: try list(a), includeDone: a["include_done"] as? Bool ?? false).map(TaskDB.json)
        case "add_task":
            let subs = a["subtasks"] as? [String] ?? []
            return TaskDB.json(try TaskDB.addTask(try str(a, "title"), list: try list(a), subtasks: subs))
        case "complete_task":
            return TaskDB.json(try TaskDB.setDone(try str(a, "task"), true))
        case "reopen_task":
            return TaskDB.json(try TaskDB.setDone(try str(a, "task"), false))
        case "move_task":
            guard let b = try list(a) else { throw DTError("missing argument 'list'") }
            return TaskDB.json(try TaskDB.move(try str(a, "task"), to: b))
        case "rename_task":
            return TaskDB.json(try TaskDB.rename(try str(a, "task"), to: try str(a, "title")))
        case "delete_task":
            return TaskDB.json(try TaskDB.delete(try str(a, "task")))
        case "clear_done":
            return ["removed": try TaskDB.clearDone(try list(a))]
        case "add_subtask":
            return TaskDB.json(try TaskDB.addSubtask(try str(a, "task"), try str(a, "title")))
        case "complete_subtask":
            return TaskDB.json(try TaskDB.setSubtaskDone(try str(a, "task"), try subRef(a), a["done"] as? Bool ?? true))
        case "delete_subtask":
            return TaskDB.json(try TaskDB.deleteSubtask(try str(a, "task"), try subRef(a)))
        case "list_notes":
            return try TaskDB.read().notes.map(TaskDB.json)
        case "add_note":
            return TaskDB.json(try TaskDB.addNote(try str(a, "text")))
        case "append_note":
            return TaskDB.json(try TaskDB.appendNote(try str(a, "note"), try str(a, "text")))
        case "delete_note":
            return TaskDB.json(try TaskDB.deleteNote(try str(a, "note")))
        case "list_quick_actions":
            return try TaskDB.read().actions.map(TaskDB.json)
        case "add_quick_action":
            return TaskDB.json(try TaskDB.addAction(title: try str(a, "title"), url: try str(a, "url"),
                                                    icon: a["icon"] as? String ?? "link", folder: a["folder"] as? String))
        case "add_quick_action_folder":
            return TaskDB.json(try TaskDB.addFolder(title: try str(a, "title"), icon: a["icon"] as? String ?? "folder"))
        case "delete_quick_action":
            return TaskDB.json(try TaskDB.deleteAction(try str(a, "action")))
        default:
            throw DTError("unknown tool '\(name)'")
        }
    }

    private static func subRef(_ a: [String: Any]) throws -> String {
        if let n = a["subtask"] as? Int { return String(n) }
        return try str(a, "subtask")
    }

    // MARK: schemas

    private static let listEnum: [String: Any] = [
        "type": "string", "enum": ["today", "tomorrow", "week", "backlog"],
    ]
    private static let taskRef: [String: Any] = [
        "type": "string", "description": "Task short id (from list_tasks) or a unique part of its title",
    ]
    private static let subRefSchema: [String: Any] = [
        "type": ["string", "integer"], "description": "1-based subtask number or a unique part of its title",
    ]

    private static func tool(_ name: String, _ desc: String, _ props: [String: Any] = [:], _ required: [String] = [], readOnly: Bool = false) -> [String: Any] {
        [
            "name": name,
            "description": desc,
            "inputSchema": ["type": "object", "properties": props, "required": required],
            "annotations": ["readOnlyHint": readOnly],
        ]
    }

    private static var tools: [[String: Any]] {
        [
            tool("list_tasks", "List tasks. Open tasks only unless include_done is true.",
                 ["list": listEnum.merging(["description": "Filter to one list; omit for all"]) { $1 },
                  "include_done": ["type": "boolean"]], readOnly: true),
            tool("add_task", "Add a task. Defaults to today. Titles may contain line breaks and URLs (shown as clickable links).",
                 ["title": ["type": "string"],
                  "list": listEnum,
                  "subtasks": ["type": "array", "items": ["type": "string"]]], ["title"]),
            tool("complete_task", "Mark a task as done.", ["task": taskRef], ["task"]),
            tool("reopen_task", "Mark a done task as open again.", ["task": taskRef], ["task"]),
            tool("move_task", "Move a task to another list.", ["task": taskRef, "list": listEnum], ["task", "list"]),
            tool("rename_task", "Change a task's title.", ["task": taskRef, "title": ["type": "string"]], ["task", "title"]),
            tool("delete_task", "Delete a task permanently.", ["task": taskRef], ["task"]),
            tool("clear_done", "Delete completed tasks, from one list or all.",
                 ["list": listEnum.merging(["description": "Omit for all lists"]) { $1 }]),
            tool("add_subtask", "Add a subtask to a task.", ["task": taskRef, "title": ["type": "string"]], ["task", "title"]),
            tool("complete_subtask", "Check (or with done=false, uncheck) a subtask.",
                 ["task": taskRef, "subtask": subRefSchema, "done": ["type": "boolean"]], ["task", "subtask"]),
            tool("delete_subtask", "Remove a subtask.", ["task": taskRef, "subtask": subRefSchema], ["task", "subtask"]),
            tool("list_notes", "List notes from the notepad (id, title = first line, full text).", readOnly: true),
            tool("add_note", "Create a note. The first line becomes its title.", ["text": ["type": "string"]], ["text"]),
            tool("append_note", "Append text to an existing note.",
                 ["note": ["type": "string", "description": "Note id or part of its text"], "text": ["type": "string"]], ["note", "text"]),
            tool("delete_note", "Delete a note.", ["note": ["type": "string", "description": "Note id or part of its text"]], ["note"]),
            tool("list_quick_actions", "List the quick-action link buttons.", readOnly: true),
            tool("add_quick_action", "Add a quick-action link button to the app.",
                 ["title": ["type": "string"],
                  "url": ["type": "string", "description": "https://, vscode://, file://, ..."],
                  "icon": ["type": "string", "description": "Font Awesome icon name without the fa- prefix (solid or brands), e.g. rocket, bug, github, docker"],
                  "folder": ["type": "string", "description": "Optional folder title/id to put the link inside"]],
                 ["title", "url"]),
            tool("add_quick_action_folder", "Add a folder: a quick-action button that opens a dropdown of links.",
                 ["title": ["type": "string"], "icon": ["type": "string"]], ["title"]),
            tool("delete_quick_action", "Remove a quick-action button, folder, or a link inside a folder.",
                 ["action": ["type": "string", "description": "Action id or title"]], ["action"]),
        ]
    }
}
