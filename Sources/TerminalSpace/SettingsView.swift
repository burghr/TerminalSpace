import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        TabView {
            AppearanceSettingsView(store: store)
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            LaunchersSettingsView(store: store)
                .tabItem { Label("Launchers", systemImage: "list.bullet.rectangle") }
            LinksSettingsView(store: store)
                .tabItem { Label("Links", systemImage: "link") }
            RemoteSettingsView(store: store)
                .tabItem { Label("Remote", systemImage: "antenna.radiowaves.left.and.right") }
        }
    }
}

/// The settings for the Dispatch session and for the start at login.
struct RemoteSettingsView: View {
    @ObservedObject var store: AppStore
    @State private var loginStatus = LoginItem.status
    @State private var loginError: String?
    @State private var commandStatus = DispatchCommand.status
    @State private var commandError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Run the Dispatch session", isOn: $store.remoteControl.enabled)
                Text("TerminalSpace runs a Claude session with the name \"Dispatch\" and Remote Control on. In the Claude app, open Dispatch and type /ts-session <name>. A new session with that name then opens in the \"Remote Control Sessions\" workspace.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("/ts-session command") {
                    HStack {
                        switch commandStatus {
                        case .installed: Text("Installed").foregroundStyle(.secondary)
                        case .outdated: Text("Changed").foregroundStyle(.orange)
                        case .missing: Text("Not installed").foregroundStyle(.orange)
                        case .unavailable: Text("Not in this build").foregroundStyle(.secondary)
                        }
                        if commandStatus == .missing || commandStatus == .outdated {
                            Button(commandStatus == .missing ? "Install" : "Replace") {
                                commandError = DispatchCommand.install()
                                commandStatus = DispatchCommand.status
                            }
                        }
                    }
                }
                Text(commandStatus == .outdated
                     ? "~/.claude/commands/ts-session.md is different from the copy in this version of TerminalSpace. Replace overwrites your changes."
                     : "Dispatch needs the command in ~/.claude/commands/ts-session.md.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let commandError {
                    Text(commandError).font(.caption).foregroundStyle(.orange)
                }
                if store.remoteControl.enabled {
                    LabeledContent("Status") {
                        if let session = store.remoteControlSession, !session.exited {
                            Label("Running", systemImage: "circle.fill").foregroundStyle(.green)
                        } else {
                            Label("Stopped", systemImage: "circle.fill").foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Session") {
                LabeledContent("Folder") {
                    HStack {
                        Text(store.remoteControl.folder).font(.body.monospaced()).lineLimit(1).truncationMode(.middle)
                        Button("Choose…") { chooseFolder() }
                    }
                }
                Picker("Permission mode", selection: $store.remoteControl.permissionMode) {
                    ForEach(RemoteControlSettings.permissionModes, id: \.self) { Text($0).tag($0) }
                }
                Text("The permission mode applies to Dispatch and to each new session from /ts-session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Keep the Mac awake while Dispatch runs", isOn: $store.remoteControl.keepAwake)
                Text("Uses caffeinate -i. A MacBook with a closed lid still sleeps, unless it has power and an external display.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Restart Dispatch") { store.syncRemoteControl(restart: true) }
                    .disabled(!store.remoteControl.enabled)
                Text("A change to a setting restarts Dispatch. A restart keeps the Dispatch conversation and does not stop the other sessions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Start at login") {
                Toggle("Open TerminalSpace at login", isOn: Binding(
                    get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                    set: { value in
                        loginError = LoginItem.set(value)
                        loginStatus = LoginItem.status
                    }))
                if loginStatus == .requiresApproval {
                    HStack {
                        Text("macOS must approve the login item.")
                        Button("Open Login Items") { LoginItem.openSystemSettings() }
                    }
                    .font(.caption)
                }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.orange)
                }
                Text("Dispatch runs only while TerminalSpace is open. If you close the window, TerminalSpace quits and Dispatch stops.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 560)
        .onAppear {
            loginStatus = LoginItem.status
            commandStatus = DispatchCommand.status
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = URL(fileURLWithPath: store.remoteControl.expandedFolder)
        panel.prompt = "Choose"
        panel.message = "Select the folder for the Remote Control sessions."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Keep the folder short with ~, so that it shows well in the settings.
        let home = NSHomeDirectory()
        store.remoteControl.folder = url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }
}

/// The list of link actions, with an editor for the selected action.
struct LinksSettingsView: View {
    @ObservedObject var store: AppStore
    @State private var selection: UUID?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(store.linkActions) { action in
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(action.name)
                                Text("\(LinkActions.scheme)://\(action.name)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        } icon: {
                            let ok = LinkActions.problems(action, among: store.linkActions, launchers: store.launchers).isEmpty
                            Image(systemName: ok ? "link" : "exclamationmark.triangle")
                                .foregroundStyle(ok ? Color.primary : Color.orange)
                        }
                        .tag(action.id)
                    }
                }
                Divider()
                HStack(spacing: 2) {
                    Button { add() } label: { Image(systemName: "plus").frame(width: 20, height: 20) }
                        .help("Add a link action")
                    Button { remove() } label: { Image(systemName: "minus").frame(width: 20, height: 20) }
                        .help("Remove the selected link action")
                        .disabled(selection == nil)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(width: 190)

            Divider()

            if let id = selection, store.linkActions.contains(where: { $0.id == id }) {
                LinkActionEditor(action: binding(for: id), store: store)
            } else {
                VStack(spacing: 8) {
                    Text("A link action lets a different program, for example a browser plugin, open a terminal with a link.")
                    Text("Click + to add one.")
                }
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 700, height: 560)
        .onAppear { if selection == nil { selection = store.linkActions.first?.id } }
    }

    /// A binding by ID, so that a removed action cannot cause an index out of range.
    private func binding(for id: UUID) -> Binding<LinkAction> {
        Binding(
            get: { store.linkActions.first { $0.id == id } ?? LinkAction.new(launcherID: Launcher.terminalID) },
            set: { value in
                if let index = store.linkActions.firstIndex(where: { $0.id == id }) { store.linkActions[index] = value }
            }
        )
    }

    private func add() {
        var action = LinkAction.new(launcherID: store.launchers.first?.id ?? Launcher.terminalID)
        var number = 2
        while store.linkActions.contains(where: { $0.name == action.name }) {
            action.name = "open-\(number)"
            number += 1
        }
        store.linkActions.append(action)
        selection = action.id
    }

    private func remove() {
        guard let id = selection, let index = store.linkActions.firstIndex(where: { $0.id == id }) else { return }
        store.linkActions.remove(at: index)
        selection = store.linkActions.isEmpty ? nil : store.linkActions[min(index, store.linkActions.count - 1)].id
    }
}

struct LinkActionEditor: View {
    @Binding var action: LinkAction
    @ObservedObject var store: AppStore

    private var example: String {
        var parts = action.parameters.map { "\($0.name)=…" }
        if action.acceptsData { parts.append("\(LinkActions.dataName)=…") }
        return "\(LinkActions.scheme)://\(action.name)" + (parts.isEmpty ? "" : "?" + parts.joined(separator: "&"))
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $action.name)
                LabeledContent("Link") {
                    Text(example).font(.caption.monospaced()).textSelection(.enabled)
                }
                let problems = LinkActions.problems(action, among: store.linkActions, launchers: store.launchers)
                if !problems.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(problems, id: \.self) { problem in
                            Label(problem, systemImage: "exclamationmark.triangle")
                        }
                        Text("A link to this action does not open until you fix these problems.")
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }

            Section("Parameters") {
                ForEach($action.parameters) { $parameter in
                    HStack {
                        TextField("Name", text: $parameter.name, prompt: Text("name"))
                            .frame(width: 120)
                        TextField("Pattern", text: $parameter.pattern, prompt: Text("^[0-9a-f]{32}$"))
                            .font(.body.monospaced())
                        Button { action.parameters.removeAll { $0.id == parameter.id } } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove the parameter")
                    }
                    .labelsHidden()
                }
                Button("Add Parameter") { action.parameters.append(LinkParameter(name: "", pattern: "")) }
                Text("The link must give each parameter one time. The pattern must match the whole value.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Accept data", isOn: $action.acceptsData)
                Text("The link can bring JSON data as data=<base64url>, up to \(LinkActions.linkDataLimit / 1024) KB. For more data, the program saves terminalspace-\(action.name)-<first parameter>.json in Downloads and sends source=download. TerminalSpace saves the data and gives its path as {data_file}.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Terminal") {
                TextField("Workspace name", text: $action.workspaceName, prompt: Text("Story {sys_id:8}"))
                TextField("Folder", text: $action.folder, prompt: Text("~/projects"))
                Picker("Launcher", selection: $action.launcherID) {
                    ForEach(store.launchers) { launcher in
                        Label(launcher.name, systemImage: launcher.symbol).tag(launcher.id)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Arguments")
                    TextEditor(text: $action.arguments)
                        .font(.body.monospaced())
                        .frame(height: 56)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3)))
                    Text("One argument on each line. TerminalSpace adds them after the command of the launcher, each one in shell quotes. Placeholders: {name} for the value of a parameter, {name:8} for its first 8 characters, and {data_file}.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("If the workspace already has a running terminal of this launcher, TerminalSpace selects that terminal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Ask before open", isOn: $action.askBeforeOpen)
                Text("Any web page can open a TerminalSpace link. Keep this on unless you trust each program that sends this link.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct AppearanceSettingsView: View {
    @ObservedObject var store: AppStore

    private let fontNames: [String] = NSFontManager.shared
        .availableFontNames(with: .fixedPitchFontMask)?.sorted() ?? []

    var body: some View {
        Form {
            Section("Default theme") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
                    ForEach(TerminalTheme.all) { theme in
                        ThemeCard(theme: theme.id == "basic" ? TerminalTheme.named("basic") : theme,
                                  selected: store.defaultThemeID == theme.id)
                            .onTapGesture { store.defaultThemeID = theme.id }
                    }
                }
                .padding(.vertical, 4)
                Text("Right-click a workspace to give it a different theme.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Text") {
                Picker("Font", selection: $store.fontName) {
                    Text("System Monospaced").tag("")
                    Divider()
                    ForEach(fontNames, id: \.self) { name in
                        Text(NSFont(name: name, size: 13)?.displayName ?? name).tag(name)
                    }
                }
                Stepper(value: $store.fontSize, in: 9...28, step: 1) {
                    LabeledContent("Size", value: "\(Int(store.fontSize)) pt")
                }
            }

            Section("Cursor") {
                Picker("Shape", selection: $store.cursorShape) {
                    ForEach(CursorShape.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Blink", isOn: $store.cursorBlink)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 560)
    }
}

/// A small preview of a theme, like the profile list of the Terminal app.
struct ThemeCard: View {
    let theme: TerminalTheme
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text("~ % ls")
                Text("Sources  build.sh")
                HStack(spacing: 2) {
                    Text("~ %")
                    Rectangle().fill(SwiftUI.Color(nsColor: NSColor(hex: theme.cursor))).frame(width: 7, height: 12)
                }
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(SwiftUI.Color(nsColor: NSColor(hex: theme.foreground)))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(SwiftUI.Color(nsColor: NSColor(hex: theme.background)))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(SwiftUI.Color.gray.opacity(0.3)))

            Text(theme.name).font(.caption)
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 8).stroke(selected ? SwiftUI.Color.accentColor : .clear, lineWidth: 2))
        .contentShape(Rectangle())
    }
}

/// The list of launchers, with an editor for the selected launcher.
struct LaunchersSettingsView: View {
    @ObservedObject var store: AppStore
    @State private var selection: UUID?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(store.launchers) { launcher in
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(launcher.name)
                                Text(launcher.command.isEmpty ? "Login shell" : launcher.command)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        } icon: {
                            Image(systemName: launcher.symbol)
                        }
                        .tag(launcher.id)
                    }
                    .onMove { store.launchers.move(fromOffsets: $0, toOffset: $1) }
                }
                Divider()
                HStack(spacing: 2) {
                    Button { add() } label: { Image(systemName: "plus").frame(width: 20, height: 20) }
                        .help("Add a launcher")
                    Button { remove() } label: { Image(systemName: "minus").frame(width: 20, height: 20) }
                        .help("Remove the selected launcher")
                        .disabled(selection == nil || store.launchers.count <= 1)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(width: 210)

            Divider()

            if let id = selection, let index = store.launchers.firstIndex(where: { $0.id == id }) {
                LauncherEditor(launcher: binding(for: id), position: index)
            } else {
                Text("Select a launcher, or click + to add one.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 640, height: 440)
        .onAppear { if selection == nil { selection = store.launchers.first?.id } }
    }

    /// A binding by ID, so that a removed launcher cannot cause an index out of range.
    private func binding(for id: UUID) -> Binding<Launcher> {
        Binding(
            get: { store.launchers.first { $0.id == id } ?? Launcher(name: "", symbol: "terminal", command: "") },
            set: { value in
                if let index = store.launchers.firstIndex(where: { $0.id == id }) { store.launchers[index] = value }
            }
        )
    }

    private func add() {
        let launcher = Launcher(name: "New Launcher", symbol: "terminal", command: "")
        store.launchers.append(launcher)
        selection = launcher.id
    }

    private func remove() {
        guard let id = selection, let index = store.launchers.firstIndex(where: { $0.id == id }) else { return }
        store.launchers.remove(at: index)
        selection = store.launchers[min(index, store.launchers.count - 1)].id
    }
}

struct LauncherEditor: View {
    @Binding var launcher: Launcher
    let position: Int

    var body: some View {
        Form {
            TextField("Name", text: $launcher.name)

            Picker("Icon", selection: $launcher.symbol) {
                ForEach(Launcher.symbols, id: \.self) { symbol in
                    Label(symbol, systemImage: symbol).tag(symbol)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                TextField("Command", text: $launcher.command, prompt: Text("For example: ssh user@host. Empty: a login shell"))
                    .font(.body.monospaced())
                Text("The command runs in your login shell, in the folder of the workspace. When it stops, the terminal continues as a shell.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Restore") {
                Picker("Resume support", selection: $launcher.integration) {
                    ForEach(LaunchIntegration.allCases) { Text($0.label).tag($0) }
                }
                switch launcher.integration {
                case .none:
                    Toggle("Run the command again when TerminalSpace restores the terminal", isOn: $launcher.rerunOnRestore)
                        .disabled(launcher.command.trimmingCharacters(in: .whitespaces).isEmpty)
                case .claude:
                    Text("TerminalSpace adds --settings and a session ID to the command, so that the conversation resumes after a restart. Put extra flags in the command, for example: claude --model opus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .opencode:
                    Text("When TerminalSpace restores the terminal, it adds --continue to the command.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let shortcut = LauncherShortcut.label(position) {
                LabeledContent("Shortcut", value: shortcut)
            }
        }
        .formStyle(.grouped)
    }
}
