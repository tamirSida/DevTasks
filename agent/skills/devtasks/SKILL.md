---
name: devtasks
description: Manage the user's DevTasks todo app (Today / Tomorrow / This Week / Backlog lists, subtasks, quick-action link buttons) from the terminal with the `devtasks` CLI. Use when the user asks to add, list, check off, move, rename or delete tasks or subtasks, plan their day or week, turn work into todos ("add these as tasks", "what's on my list", "mark X done"), or add a quick-action button to the app.
---

# DevTasks

`devtasks` edits the same local data file as the DevTasks Mac app. Changes show up in the open app immediately.
Run `devtasks help` for the full reference.

## Lists

Built-in: `today` (default), `tomorrow`, `week`, `backlog`. Each new day, open tomorrow tasks move to today automatically.
Custom lists: `devtasks lists` shows them with their ids; use the id anywhere a list is expected (`--list side-project`, `@side-project`).

## Referring to tasks

`<task>` is either the 6-char id shown by `list` (e.g. `a1b2c3`) or any unique part of the title (`devtasks done "auth race"`).
If a reference matches several tasks, the command fails and lists the candidates with their ids. Retry with an id.
Prefer ids when acting on tasks you just listed.

## Commands

```bash
devtasks list                         # open tasks in all lists
devtasks list today --all --json      # one list, include done, machine-readable
devtasks add "write migration" --list week --sub "draft schema" --sub "backfill"
devtasks add fix flaky e2e test @tomorrow    # @today @tomorrow @week @backlog work inline
devtasks done <task> [<task>...]
devtasks undo <task>
devtasks move <task> <list>
devtasks edit <task> "new title"
devtasks rm <task>
devtasks clear [list|all]             # delete completed tasks

devtasks sub add  <task> "subtask title"
devtasks sub done <task> <n|title>    # n is 1-based, as shown by list
devtasks sub undo <task> <n|title>
devtasks sub rm   <task> <n|title>

devtasks lists                        # all lists, with ids and open counts
devtasks lists add "Side Project" --icon rocket
devtasks lists rm side-project        # its tasks move to backlog

devtasks note add 'standup\n- shipped auth fix'   # scratchpad notes (first line = title)
pbpaste | devtasks note add
devtasks note list | show <note> | append <note> <text> | rm <note>

devtasks prompt add "code review" 'Review this diff for bugs...'   # saved prompts, copy on click in the app
devtasks prompt list | show <prompt> | copy <prompt>

devtasks paste [list]                 # task from clipboard; keeps embedded links (e.g. Azure DevOps titles)
devtasks copy <task>                  # copy a task with clickable links for chats

devtasks action list
devtasks action add "Grafana" https://grafana.example.com --icon chart-line
devtasks action folder "Dashboards" --icon gauge-high           # a dropdown of links
devtasks action add "Sentry" https://sentry.io --icon bug --in Dashboards
devtasks action rm <action>
```

Add `--json` to any command to get JSON back (errors become `{"error": "..."}` with exit code 1).

## Guidelines

- Use `devtasks list --json` before changing tasks so you reference real ids.
- Keep titles short and imperative ("fix token refresh race"). Put steps in subtasks, not in the title.
- Titles can span lines: use `\n` in the CLI (`devtasks add 'deploy\nrun migrations first'`).
- Put URLs straight into titles (PRs, tickets, docs). The app shows them as short clickable links.
- For a link with its own label use markdown: `[PBI 48213: Fix SSO timeout](https://dev.azure.com/...)`.
- Don't `rm` or `clear` unless the user asked to delete. Completing a task (`done`) is the normal path.
- Quick-action icons are Font Awesome 6 names without the `fa-` prefix, Solid or Brands: rocket, bug, server, terminal, chart-line, github, gitlab, docker, aws, python, slack, jira, figma. Unknown names are rejected.
- After making changes, tell the user briefly what you added, moved or checked off.
