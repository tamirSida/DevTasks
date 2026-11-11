# DevTasks

A native macOS todo app for developers. SwiftUI, no servers, no accounts. Your data stays in one local JSON file.

## Install on any Mac

You need macOS 14 or newer and the Command Line Tools (`xcode-select --install`). Full Xcode is not required.

```bash
git clone <your-repo-url> devtasks
cd devtasks
./build.sh --install      # builds and copies DevTasks.app to /Applications
```

Run `./build.sh` without the flag to build into `build/DevTasks.app` only.
The app is built on your own Mac, so Gatekeeper does not block it.

To work on it in Xcode, open `Package.swift`.

## Features

- Lists: **Today**, **Tomorrow**, **This Week**, **Backlog**. When the day changes, open Tomorrow tasks move to Today automatically.
- Quick add prompt. Add `@tomorrow`, `@week`, `@backlog` or `@today` anywhere in the text to choose the list (short forms: `@tom`, `@wk`, `@bl`).
- Subtasks with a progress chip. Click the chevron on a task to open them.
- Animated check with a sound (the sound can be turned off in the sidebar).
- Quick actions: link buttons with a title, a URL (`https://`, `vscode://`, `file://`, ...) and any Font Awesome Solid icon. Right-click a button to edit, reorder or delete it.
- Move tasks by dragging them onto a list in the sidebar, or with the hover / right-click menu.
- Appearance: system, light or dark.

## Shortcuts

| Keys | Action |
| --- | --- |
| Cmd N | Focus quick add |
| Cmd 1-4 | Today / Tomorrow / This Week / Backlog |
| Cmd Shift D | Cycle appearance |
| Enter | Add task / subtask |

## Data

`~/Library/Application Support/DevTasks/data.json`. To sync between Macs, copy this file, or symlink the folder into iCloud Drive or Dropbox.
If the file can't be read, it is backed up as `data.corrupt-<timestamp>.json` and never overwritten.
Set `DEVTASKS_DATA_DIR` to use a different folder (handy for testing).

## Project layout

```
Package.swift
Sources/DevTasks/      SwiftUI app
Resources/             Font Awesome Solid TTF, app icon
scripts/gen_icons.py   regenerates the icon-name map from a Font Awesome all.css
scripts/make_icon.swift regenerates Resources/AppIcon.icns
build.sh               builds + bundles + ad-hoc signs the .app
```

Icons: [Font Awesome Free](https://fontawesome.com) 6.5.1 (font under SIL OFL 1.1).
