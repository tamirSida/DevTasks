# DevTasks

A native macOS todo app for developers. SwiftUI, no servers, no accounts. Your data stays in one local JSON file.

## Install on any Mac

You need macOS 14 or newer and the Command Line Tools (`xcode-select --install`). Full Xcode is not required.

```bash
git clone https://github.com/tamirSida/DevTasks.git
cd DevTasks
./build.sh --install      # builds and copies DevTasks.app to /Applications
```

Run `./build.sh` without the flag to build into `build/DevTasks.app` only.
The app is built on your own Mac, so Gatekeeper does not block it.

To work on it in Xcode, open `Package.swift`.

## Features

- Lists: **Today**, **Tomorrow**, **This Week**, **Backlog**, plus your own (sidebar "+ new list"; right-click to rename, change icon or delete). When the day changes, open Tomorrow tasks move to Today automatically.
- Scratchpad notes (sidebar, Cmd 5, new note Cmd Shift N) with clickable links.
- Rich paste: copy a work item title in Azure DevOps (or a link from Teams/Slack/a browser) and paste it; the link stays embedded. The copy button on a task puts it back on the clipboard with the link, ready for chats.
- Prompts: a quick-action button holding named snippets; click one to copy it. Notes can be saved to it with one click.
- Quick add prompt. Type `@` to pick a list from an autocomplete menu (Tab or Enter accepts, arrow keys move), or type `@tomorrow`, `@week`, `@backlog`, `@today` in full.
- Shift+Enter starts a new line in the quick-add bar, task titles and subtasks.
- URLs in tasks show as short clickable links (`github.com/…/pull/412`). Click anywhere else on the title to edit the full text.
- Subtasks with a progress chip. Click the chevron on a task to open them.
- Animated check with a sound (the sound can be turned off in the sidebar). Links on completed tasks stay clickable.
- Text size S / M / L / XL in the theme settings (handy on large 1440p screens).
- Quick actions: link buttons with a title, a URL (`https://`, `vscode://`, `file://`, ...) and a Font Awesome icon. The picker has a "dev" tab of coding icons plus all Solid and Brands icons (GitHub, Docker, AWS, Python...).
- Folders: a quick-action button that opens a dropdown of links, with "open all". Right-click a button to edit, reorder, delete it, or move it into a folder.
- Move tasks by dragging them onto a list in the sidebar, or with the hover / right-click menu.
- Themes: pick a dark theme and a light theme (DevTasks, iTerm, Tokyo Night, Catppuccin, Dracula, One Dark, Nord, Gruvbox, GitHub Light, Solarized Light). Set window opacity, with optional blur, from the palette button in the sidebar or with Cmd , (Settings).

## Agents and the CLI

`./build.sh --install` also installs:

- **`devtasks` CLI** in `/usr/local/bin` (or `~/.local/bin` if that is not writable). It is the app binary itself, run from the terminal.
- **Claude Code skill** in `~/.claude/skills/devtasks` (if `~/.claude` exists). It tells the agent how to use the CLI.

Every change goes to the same data file, and the open app updates within a fraction of a second.

```bash
devtasks add "fix flaky e2e" @tomorrow --sub "find seed" --sub "pin retries"
devtasks list --json
devtasks done flaky
devtasks sub done flaky 1
devtasks move a1b2c3 week
devtasks action add Grafana https://grafana.example.com --icon chart-line
devtasks help
```

### MCP server

`devtasks mcp` runs an MCP server over stdio with these tools: `list_tasks`, `add_task`, `complete_task`, `reopen_task`,
`move_task`, `rename_task`, `delete_task`, `clear_done`, `add_subtask`, `complete_subtask`, `delete_subtask`,
`list_quick_actions`, `add_quick_action` and `delete_quick_action`.

The configs below use the full path to the binary, so they work even when the agent doesn't load your shell PATH.

**GitHub Copilot CLI** - add to `~/.copilot/mcp-config.json` (or run `/mcp add` inside copilot):

```json
{
  "mcpServers": {
    "devtasks": {
      "type": "local",
      "command": "/Applications/DevTasks.app/Contents/MacOS/DevTasks",
      "args": ["mcp"],
      "tools": ["*"]
    }
  }
}
```

**VS Code Copilot** - `.vscode/mcp.json` in a workspace, or the user-level MCP config:

```json
{
  "servers": {
    "devtasks": { "type": "stdio", "command": "/Applications/DevTasks.app/Contents/MacOS/DevTasks", "args": ["mcp"] }
  }
}
```

**Claude Code** - the skill already covers it. If you'd rather use MCP:

```bash
claude mcp add --scope user devtasks -- /Applications/DevTasks.app/Contents/MacOS/DevTasks mcp
```

**Cursor / others** - command `/Applications/DevTasks.app/Contents/MacOS/DevTasks`, args `["mcp"]`.

## Shortcuts

| Keys | Action |
| --- | --- |
| Cmd N | Focus quick add |
| Cmd 1-4 | Today / Tomorrow / This Week / Backlog |
| Cmd Shift D | Cycle appearance |
| Cmd , | Themes and opacity |
| Shift Enter | New line |
| @ then Tab | Pick a list |
| Enter | Add task / subtask |

## Data

`~/Library/Application Support/DevTasks/data.json`. To sync between Macs, copy this file, or symlink the folder into iCloud Drive or Dropbox.
If the file can't be read, it is backed up as `data.corrupt-<timestamp>.json` and never overwritten.
Set `DEVTASKS_DATA_DIR` to use a different folder (handy for testing).

## Project layout

```
Package.swift
Sources/DevTasks/      SwiftUI app + CLI (CLI.swift) + MCP server (MCPServer.swift)
Resources/             Font Awesome Solid TTF, app icon
scripts/gen_icons.py   regenerates the icon-name map from a Font Awesome all.css
scripts/make_icon.swift regenerates Resources/AppIcon.icns
agent/skills/devtasks  Claude Code skill (installed by build.sh --install)
build.sh               builds + bundles + ad-hoc signs the .app
```

Icons: [Font Awesome Free](https://fontawesome.com) 6.5.1, Solid + Brands (fonts under SIL OFL 1.1).
