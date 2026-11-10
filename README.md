<p align="center">
  <img src="Resources/AppIcon-1024.png" width="128" alt="TerminalSpace icon">
</p>

# TerminalSpace

TerminalSpace is a native macOS terminal app that puts your terminals into workspaces.
Each workspace is a project folder. Each terminal in a workspace can be a normal shell,
a [Claude Code](https://claude.com/claude-code) session, an [opencode](https://opencode.ai) session,
or any command that you configure, for example `ssh`.

The app uses [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) for terminal emulation.

![TerminalSpace with five workspaces in the sidebar](Resources/screenshot.png)

## Features

- **Workspaces:** A sidebar shows your workspaces. The terminals of each workspace show under it.
- **Launchers:** The new-terminal menu shows a list of launchers. Each launcher has a name, an icon, and a command. The default launchers are Terminal, Claude, and opencode. Add your own, for example `ssh user@host`. The command starts in the workspace folder. When it stops, the tab continues as a normal shell.
- **Run Command:** Start any command one time, or save it as a launcher.
- **Link actions:** Let a different program, for example a browser plugin, open a workspace and a terminal with a `terminalspace://` link. Off until you add an action.
- **Resume links:** `terminalspace://resume?session=<id>` opens an earlier Claude conversation again, in its own folder. TerminalSpace asks first.
- **Updates:** TerminalSpace looks for a new release on GitHub and asks before it installs it. See [Updates](#updates).
- **Remote Control and Dispatch:** From the Claude app on your phone, open new Claude sessions on your Mac. Each session is a TerminalSpace terminal, so you can continue it at the Mac later. Off by default.
- **Drag files in:** Drag a file or a folder into a terminal to type its path. Dragged text also goes in.
- **File links:** Cmd-click a file path in a terminal to open the file in its default app, as in Terminal.app. A path can be absolute, relative to the current folder, or have a line number, for example `Sources/App.swift:12`. Cmd-click also opens URLs.
- **Claude session names:** A new Claude session gets the name of its workspace. The name shows in the Claude prompt box, in the `/resume` list, and in the tab.
- **Drag and drop:** Drag a terminal to a different workspace, or to a different position. Drag a workspace name onto a different workspace to change the order of workspaces.
- **Restore:** When you quit, the app saves your terminals. At the next start:
  - A Terminal tab shows its last output and opens a shell in its last folder.
  - A tab from a custom launcher shows its last output. By default, it runs its command again.
  - A Claude tab resumes the same conversation, also after `/resume` or `/clear`.
  - An opencode tab continues the last session in the workspace folder.
- **Themes:** The themes follow the profiles of the macOS Terminal app: Basic, Pro, Homebrew, Ocean, Grass, Man Page, Novel, Red Sands, and Silver Aerogel. You can set a default theme and a different theme for each workspace.
- **Workspace colors:** Each workspace has a color in the sidebar. A workspace theme can also set this color.
- **Settings:** Font, font size, cursor shape, and cursor blink.

## Requirements

- macOS 14 or later
- Swift 6 toolchain (Xcode 16 or later, or the Command Line Tools)
- Optional: `claude` and `opencode` in your login shell `PATH`

## Install

1. Download [`TerminalSpace.dmg`](https://github.com/burghr/TerminalSpace/releases/latest/download/TerminalSpace.dmg) from the latest release.
2. Open the disk image.
3. Drag TerminalSpace to the Applications folder.

Apple notarizes the releases, so the app opens without a Gatekeeper warning. Later versions install from inside the app. See [Updates](#updates).

## Build

```sh
git clone https://github.com/burghr/TerminalSpace.git
cd TerminalSpace
./build.sh
open build/TerminalSpace.app
```

`build.sh` builds a release binary and makes `build/TerminalSpace.app`. The app has an ad-hoc signature only.

Options:

- `./build.sh --run` stops the running copy, then opens the new build. The running copy saves its terminals before it stops.
- `build.sh` uses the Command Line Tools if Xcode cannot build the package, for example when the Xcode license is not accepted, or when the Metal toolchain for the SwiftTerm shaders is missing. To install that toolchain, run `xcodebuild -downloadComponent MetalToolchain`.

To change the icon, edit `Scripts/make-icon.swift`, then run `swift Scripts/make-icon.swift`.

`Scripts/make-dmg.sh [--notarize] [path/to/TerminalSpace.app]` makes `build/TerminalSpace.dmg`: a disk image with the app, an Applications link, and a background that says what to do. It signs the disk image with the Developer ID. With `--notarize`, Apple also notarizes the disk image. Notarize the app before you make the disk image.

## Keyboard shortcuts

| Action | Shortcut |
|---|---|
| New workspace | Shift-Cmd-N |
| First launcher (Terminal) | Cmd-T |
| Second launcher (Claude) | Shift-Cmd-T |
| Third launcher (opencode) | Option-Cmd-T |
| Launchers 4 to 9 | Control-Cmd-4 to Control-Cmd-9 |
| Run Command | Shift-Cmd-R |
| Close terminal | Cmd-W |
| Settings | Cmd-, |

The launcher shortcuts follow the order of the launchers in Settings.

Right-click a workspace to rename it, to set its color or theme, or to move it up or down. Right-click a terminal to rename or close it.

## Launchers

Open **Settings > Launchers** to add, edit, remove, or reorder launchers. Each launcher has these settings:

| Setting | Description |
|---|---|
| Name | The name in the menu, and the default name of new tabs |
| Icon | The icon in the menu and in the sidebar |
| Command | The command to run in your login shell. Leave it empty to start a normal shell. |
| Resume support | **None**, **Claude Code**, or **opencode**. See below. |

Resume support controls what happens when TerminalSpace restores a terminal:

- **None:** An option runs the command again. For example, an SSH launcher connects again.
- **Claude Code:** TerminalSpace adds `--settings`, a session ID, and `--name` with the workspace name. You can add your own flags, for example `claude --model opus`.
- **opencode:** TerminalSpace adds `--continue` to the command.

To name Claude sessions that are already open, use **File > Name All Claude Sessions**, or **Name Claude Sessions** in the menu of a workspace, or **Name Claude Session** in the menu of a terminal. TerminalSpace then types `/rename` into those terminals. It uses your tab name, or the workspace name.

A terminal keeps a copy of its launcher from when it started. A change to a launcher does not change terminals that are already open.

## Link actions

A link action lets a different program open a terminal with a `terminalspace://` link. For example, a browser plugin can open a workspace for the page that you look at. TerminalSpace has no link actions after you install it. A link does nothing until you add an action in **Settings > Links**.

Each action has these settings:

| Setting | Description |
|---|---|
| Name | The host of the link: `terminalspace://<name>?…` |
| Parameters | A name and a pattern for each value. The link must give each parameter one time, and the pattern must match the whole value. |
| Accept data | The link can also bring JSON data. See below. |
| Workspace name | The workspace to create or to select. It can use placeholders. |
| Folder | The folder of a new workspace |
| Launcher | The launcher for the new terminal |
| Arguments | One argument on each line. TerminalSpace adds them after the command of the launcher. |
| Ask before open | TerminalSpace shows the values and asks before it opens the link. This is on for each new action. |

Placeholders in the workspace name and in the arguments:

- `{name}`: the value of the parameter `name`.
- `{name:8}`: the first 8 characters of that value.
- `{data_file}`: the path of the saved data.

A link can only give values. The action sets the folder, the launcher, and the arguments. TerminalSpace puts each argument in shell quotes, so a value cannot add a command. If the workspace already has a running terminal of the launcher, TerminalSpace selects that terminal and does not start a second one. A restored terminal does not use the arguments again.

**Data.** With **Accept data**, the link must have one of these:

- `data=<base64url JSON>`, up to 64 KB.
- `source=download`. The program first saves `terminalspace-<action>-<first parameter>.json` in `~/Downloads`, up to 1 MB. TerminalSpace removes that file after it reads it.

TerminalSpace checks that the data is JSON. Then it saves the data to `link-data/<action>/<first parameter>.json` in its data folder. The first parameter names the file, so its value can have letters, digits, `-`, and `_` only.

Example: the action `ticket` with the parameter `id`, the launcher Claude, and the argument `Read {data_file} and summarize ticket {id}`. The link `terminalspace://ticket?id=T123&data=…` then opens the workspace and starts Claude with that prompt.

Any web page can open a `terminalspace://` link. Keep **Ask before open** on, unless you trust each program that sends the link. A browser also asks before a site opens the link for the first time.

### Resume a Claude conversation

`terminalspace://resume?session=<conversation ID>` is a built-in link. It needs no link action.

1. TerminalSpace finds the conversation file `~/.claude/projects/<folder>/<ID>.jsonl` and reads the folder of the conversation from it.
2. If a terminal already shows the conversation, TerminalSpace selects that terminal.
3. If not, TerminalSpace shows the title, the folder, and the ID, and asks before it opens.
4. It opens a Claude terminal with `claude --resume <ID>` in the workspace of that folder. If no workspace has that folder, it adds one with the folder name.

The link gives only the ID. TerminalSpace takes the folder from the conversation file, so a link cannot choose a folder or a command. The names `resume` and `remote-session` are reserved for the built-in links, so a link action cannot use them.

## Remote Control and Dispatch

With this feature, you can start a Claude session on your Mac when you are away from it. You can work in the session from the Claude app, and continue it in TerminalSpace when you return.

TerminalSpace runs one Claude terminal with the name **Dispatch**, with [Remote Control](https://code.claude.com/docs/en/remote-control) on. From the Claude app, you send `/ts-session <name>` to Dispatch. Dispatch then opens a new Claude terminal with that name in the **Remote Control Sessions** workspace. The new session also has Remote Control on, so it shows in the Claude app.

**Set up:**

1. Open **Settings > Remote**.
2. Click **Install** next to **/ts-session command**. TerminalSpace copies the command to `~/.claude/commands/ts-session.md`.
3. Click **Choose…** and select the folder for the sessions.
4. Select the permission mode. The mode applies to Dispatch and to each new session. TerminalSpace does not offer `bypassPermissions`.
5. Turn on **Run the Dispatch session**.
6. Optional: turn on **Open TerminalSpace at login**.

**Use:**

1. In the Claude app, open the session **Dispatch**.
2. Send `/ts-session fix-login`.
3. Open **fix-login** from the session list. The session can take a few seconds to show.
4. At the Mac, select **fix-login** in the **Remote Control Sessions** workspace. The conversation is on the screen, and you can type in the terminal or in the app.

The bar at the bottom of the sidebar shows the status of Dispatch. Click the bar to show the Dispatch terminal. Right-click it to restart or stop Dispatch. A restart keeps the Dispatch conversation. When you close the Dispatch terminal, the setting goes off.

**Requirements and limits:**

- Your Claude plan must include Remote Control. An organization can turn Remote Control off.
- Dispatch runs only while TerminalSpace is open. When you close the window, TerminalSpace quits.
- With **Keep the Mac awake**, TerminalSpace starts Claude under `caffeinate -i`. A MacBook with a closed lid still sleeps, unless it has power and an external display.
- If a link does not open, the error shows on the Mac, not on the phone.

**The link.** `/ts-session` runs `open 'terminalspace://remote-session?name=<name>'`. TerminalSpace accepts this link only while Dispatch is on. The name can have 1 to 40 letters, digits, spaces, dots, dashes, and underscores. TerminalSpace puts the name in shell quotes.

Any web page can open this link, and TerminalSpace does not ask before it opens the link. A page can start an idle Claude session on your account in the session folder. The page cannot send a prompt to the session. Only your Claude account can connect to the session. A browser also asks before a site opens the link for the first time.

## How Claude sessions resume

A Claude conversation can change its ID, for example after `/resume` or `/clear`. To track the current ID, TerminalSpace starts Claude with `--settings`. That settings file adds a `SessionStart` hook. The hook writes the current session data to a file for each terminal. Your own Claude settings and hooks stay active.

## Updates

TerminalSpace reads the latest release of `burghr/TerminalSpace` from GitHub 15 seconds after the start and then every 6 hours. Turn this off in **Settings > Updates**. **TerminalSpace > Check for Updates…** checks at once.

When a newer version is available, TerminalSpace asks: **Install and Restart**, **Later**, or **Skip This Version**. A skipped version does not ask again, but a newer one does. TerminalSpace never installs without your OK.

Before it installs, TerminalSpace checks the download:

1. The SHA-256 of the zip must match the checksum that GitHub gives for the file.
2. The app in the zip must have the TerminalSpace bundle ID and the version of the release.
3. The app must be signed with the Developer ID of team 3YULF6FJ6W, and Apple must have notarized it.

If a check fails, TerminalSpace installs nothing and offers the release page. Then it replaces its app bundle in one step and restarts. Your terminals open again: Claude and opencode resume their conversations, and other commands start again.

An update works only when TerminalSpace runs from `/Applications` or `~/Applications`. A copy in a build folder only shows that a new version is available.

## Data

TerminalSpace keeps its data in `~/Library/Application Support/TerminalSpace`:

| File | Content |
|---|---|
| `workspaces.json` | Workspaces: name, folder, color, theme |
| `sessions.json` | Open terminals and the selected terminal |
| `scrollback/` | Output of Terminal tabs, from the last quit. The app deletes it after a restore. |
| `claude-settings.json` | The hook settings for Claude |
| `claude-state/` | The current Claude session of each terminal |
| `link-data/` | The data from links, one folder for each link action |

The app keeps its settings, launchers, and link actions in the `com.coconetlabs.terminalspace` defaults domain.

## Limits

- A running command stops when you quit. The terminal opens again, but you must start the command again.
- The restored output of a Terminal tab is plain text without colors.
- Two opencode terminals in the same folder continue the same session.
- Sessions that you start with **New session** in the Claude app do not show in TerminalSpace. Use `/ts-session` in Dispatch.

## License

MIT. See [LICENSE](LICENSE). SwiftTerm is also MIT licensed.
