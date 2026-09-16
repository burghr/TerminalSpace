import AppKit
import Darwin
import SwiftTerm

/// Special restore support for a tool. The app adds flags to the command, so that the tool resumes after a restart.
enum LaunchIntegration: String, Codable, CaseIterable, Identifiable {
    case none, claude, opencode

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "None"
        case .claude: return "Claude Code"
        case .opencode: return "opencode"
        }
    }
}

/// An entry in the new-terminal menu. An empty command starts only a login shell.
struct Launcher: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var symbol: String
    var command: String
    var integration: LaunchIntegration = .none
    /// For a launcher without integration: run the command again when the app restores the terminal.
    var rerunOnRestore = true

    static let terminalID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    static let claudeID = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    static let opencodeID = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!

    static let defaults = [
        Launcher(id: terminalID, name: "Terminal", symbol: "terminal", command: ""),
        Launcher(id: claudeID, name: "Claude", symbol: "sparkles", command: "claude", integration: .claude),
        Launcher(id: opencodeID, name: "opencode", symbol: "chevron.left.forwardslash.chevron.right",
                 command: "opencode", integration: .opencode),
    ]

    /// The icons that the launcher editor offers.
    static let symbols = [
        "terminal", "sparkles", "chevron.left.forwardslash.chevron.right", "network", "server.rack",
        "externaldrive", "cloud", "globe", "lock.shield", "cpu", "hammer", "wrench.and.screwdriver",
        "shippingbox", "cube", "bolt", "doc.text", "chart.bar", "gearshape", "house", "star",
    ]
}

enum AppPaths {
    static let support: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TerminalSpace", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// The Claude hook writes one file here for each terminal. The file holds the current conversation ID.
    static let claudeState = support.appendingPathComponent("claude-state", isDirectory: true)

    /// Extra Claude settings with a SessionStart hook. Claude runs the hook at start, at /resume, and at /clear.
    static let claudeSettings: URL = {
        let url = support.appendingPathComponent("claude-settings.json")
        try? FileManager.default.createDirectory(at: claudeState, withIntermediateDirectories: true)
        let command = #"cat > "$TERMINALSPACE_STATE_DIR/$TERMINALSPACE_TERMINAL_ID.json""#
        let settings: [String: Any] = [
            "hooks": ["SessionStart": [["hooks": [["type": "command", "command": command]]]]]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted]) {
            try? data.write(to: url, options: .atomic)
        }
        return url
    }()
}

enum WorkspaceColor: String, CaseIterable, Codable, Identifiable {
    case blue, purple, pink, red, orange, yellow, green, teal, gray

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

struct Workspace: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var directory: String
    /// Workspaces from older versions have no color. They show as blue.
    var color: WorkspaceColor?
    /// A theme ID for the terminals in this workspace. A nil value uses the default theme from Settings.
    var theme: String?
}

/// The data that the app saves for one terminal, so that the terminal can open again at the next start.
struct SavedSession: Codable {
    var id: UUID
    var workspaceID: UUID
    /// A copy of the launcher from when the terminal started. A later change to the launcher does not change the terminal.
    var launcher: Launcher
    var defaultName: String
    var customName: String?
    var directory: String
    /// The current Claude conversation ID. Other launchers do not use it.
    var toolSessionID: UUID?

    init(id: UUID, workspaceID: UUID, launcher: Launcher, defaultName: String, customName: String? = nil,
         directory: String, toolSessionID: UUID?) {
        self.id = id
        self.workspaceID = workspaceID
        self.launcher = launcher
        self.defaultName = defaultName
        self.customName = customName
        self.directory = directory
        self.toolSessionID = toolSessionID
    }

    private enum CodingKeys: String, CodingKey {
        case id, workspaceID, launcher, kind, defaultName, customName, directory, toolSessionID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        workspaceID = try c.decode(UUID.self, forKey: .workspaceID)
        defaultName = try c.decode(String.self, forKey: .defaultName)
        customName = try c.decodeIfPresent(String.self, forKey: .customName)
        directory = try c.decode(String.self, forKey: .directory)
        toolSessionID = try c.decodeIfPresent(UUID.self, forKey: .toolSessionID)
        if let launcher = try c.decodeIfPresent(Launcher.self, forKey: .launcher) {
            self.launcher = launcher
        } else {
            // Older versions saved a "kind" of plain, claude, or opencode.
            let kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "plain"
            let index = ["plain": 0, "claude": 1, "opencode": 2][kind] ?? 0
            launcher = Launcher.defaults[index]
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(workspaceID, forKey: .workspaceID)
        try c.encode(launcher, forKey: .launcher)
        try c.encode(defaultName, forKey: .defaultName)
        try c.encodeIfPresent(customName, forKey: .customName)
        try c.encode(directory, forKey: .directory)
        try c.encodeIfPresent(toolSessionID, forKey: .toolSessionID)
    }
}

/// One terminal in a workspace. The terminal view stays alive when the sidebar selection changes.
final class TerminalSession: NSObject, ObservableObject, Identifiable, LocalProcessTerminalViewDelegate {
    let id: UUID
    let launcher: Launcher
    let view: LocalProcessTerminalView
    let defaultName: String
    private let initialToolSessionID: UUID?

    @Published var workspaceID: UUID
    @Published var customName: String?
    @Published var processTitle: String?
    @Published var exited = false

    /// The folder where the process started.
    private let startDirectory: String

    var displayName: String {
        if let customName, !customName.isEmpty { return customName }
        if let processTitle, !processTitle.isEmpty { return processTitle }
        return defaultName
    }

    /// Starts a new terminal.
    convenience init(workspace: Workspace, launcher: Launcher, number: Int) {
        let saved = SavedSession(id: UUID(), workspaceID: workspace.id, launcher: launcher,
                                 defaultName: number > 1 ? "\(launcher.name) \(number)" : launcher.name,
                                 directory: workspace.directory,
                                 toolSessionID: launcher.integration == .claude ? UUID() : nil)
        self.init(saved: saved, restoring: false, scrollback: nil)
    }

    /// Opens a terminal from saved data. A restored Claude or opencode terminal resumes its conversation.
    init(saved: SavedSession, restoring: Bool, scrollback: String?) {
        id = saved.id
        workspaceID = saved.workspaceID
        launcher = saved.launcher
        defaultName = saved.defaultName
        customName = saved.customName
        initialToolSessionID = saved.toolSessionID
        startDirectory = FileManager.default.fileExists(atPath: saved.directory) ? saved.directory : NSHomeDirectory()
        view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        super.init()

        view.processDelegate = self

        if let scrollback, !scrollback.isEmpty {
            view.feed(text: scrollback.replacingOccurrences(of: "\n", with: "\r\n"))
            view.feed(text: "\r\n\u{1b}[2m── restored ──\u{1b}[0m\r\n")
        }
        start(command: command(restoring: restoring))
    }

    private func command(restoring: Bool) -> String? {
        let base = launcher.command.trimmingCharacters(in: .whitespacesAndNewlines)
        switch launcher.integration {
        case .none:
            if base.isEmpty || (restoring && !launcher.rerunOnRestore) { return nil }
            return base
        case .claude:
            let claude = base.isEmpty ? "claude" : base
            let settings = "--settings '\(AppPaths.claudeSettings.path)'"
            guard let sessionID = initialToolSessionID?.uuidString.lowercased() else { return "\(claude) \(settings)" }
            // Claude writes the conversation file only after the first message.
            if restoring && Self.claudeConversationExists(sessionID) {
                return "\(claude) \(settings) --resume \(sessionID)"
            }
            return "\(claude) \(settings) --session-id \(sessionID)"
        case .opencode:
            let opencode = base.isEmpty ? "opencode" : base
            return restoring ? "\(opencode) --continue" : opencode
        }
    }

    private func start(command: String?) {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shellName = "-" + (shell as NSString).lastPathComponent

        // A login shell loads the PATH of the user, also when Finder starts the app.
        var args = ["-l"]
        if let command {
            // When the tool stops, the terminal continues as a normal shell.
            args += ["-i", "-c", "\(command); exec \(shell) -l"]
        }
        view.startProcess(executable: shell, args: args, environment: environment(),
                          execName: shellName, currentDirectory: startDirectory)
    }

    private func environment() -> [String] {
        var env = ProcessInfo.processInfo.environment
        // Remove the markers of a parent Claude Code session, if the app started from one.
        for key in env.keys where key.hasPrefix("CLAUDECODE") || key.hasPrefix("CLAUDE_CODE") {
            env[key] = nil
        }
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["TERM_PROGRAM"] = "TerminalSpace"
        env["TERMINALSPACE_TERMINAL_ID"] = id.uuidString
        env["TERMINALSPACE_STATE_DIR"] = AppPaths.claudeState.path
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        return env.map { "\($0.key)=\($0.value)" }
    }

    private static func claudeConversationExists(_ sessionID: String) -> Bool {
        let projects = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: projects.path)) ?? []
        return folders.contains { folder in
            FileManager.default.fileExists(atPath: projects.appendingPathComponent("\(folder)/\(sessionID).jsonl").path)
        }
    }

    /// The current folder of the shell. Claude and opencode keep their start folder, because they resume by folder.
    var currentDirectory: String {
        guard launcher.integration == .none, !exited else { return startDirectory }
        let pid = view.process.shellPid
        guard pid > 0 else { return startDirectory }

        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return startDirectory }
        let path = withUnsafePointer(to: info.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
        return path.isEmpty ? startDirectory : path
    }

    /// The last lines of output, as plain text. Claude and opencode do not use it, because they show their history again.
    func scrollbackText(maxLines: Int = 2000) -> String? {
        guard launcher.integration == .none else { return nil }
        let data = view.getTerminal().getBufferAsData(kind: .normal)
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        var lines = text.components(separatedBy: "\n")
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        return lines.suffix(maxLines).joined(separator: "\n")
    }

    private var claudeStateURL: URL {
        AppPaths.claudeState.appendingPathComponent("\(id.uuidString).json")
    }

    /// The conversation that Claude uses now. The ID changes after /resume or /clear in Claude.
    var toolSessionID: UUID? {
        guard launcher.integration == .claude else { return nil }
        if let data = try? Data(contentsOf: claudeStateURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let value = json["session_id"] as? String, let current = UUID(uuidString: value) {
            return current
        }
        return initialToolSessionID
    }

    func removeClaudeState() {
        try? FileManager.default.removeItem(at: claudeStateURL)
    }

    var saved: SavedSession {
        SavedSession(id: id, workspaceID: workspaceID, launcher: launcher, defaultName: defaultName,
                     customName: customName, directory: currentDirectory, toolSessionID: toolSessionID)
    }

    func terminate() {
        if !exited { view.terminate() }
    }

    // MARK: LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        DispatchQueue.main.async { self.processTitle = title }
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { self.exited = true }
    }
}
