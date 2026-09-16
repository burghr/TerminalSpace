import AppKit
import Darwin
import SwiftTerm

/// The kind of program that a new terminal starts.
enum TerminalKind: String, CaseIterable, Codable, Identifiable {
    case plain, claude, opencode

    var id: String { rawValue }

    var label: String {
        switch self {
        case .plain: return "Terminal"
        case .claude: return "Claude"
        case .opencode: return "opencode"
        }
    }

    var symbol: String {
        switch self {
        case .plain: return "terminal"
        case .claude: return "sparkles"
        case .opencode: return "chevron.left.forwardslash.chevron.right"
        }
    }
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
    var kind: TerminalKind
    var defaultName: String
    var customName: String?
    var directory: String
    /// The current Claude conversation ID. Other kinds do not use it.
    var toolSessionID: UUID?
}

/// One terminal in a workspace. The terminal view stays alive when the sidebar selection changes.
final class TerminalSession: NSObject, ObservableObject, Identifiable, LocalProcessTerminalViewDelegate {
    let id: UUID
    let kind: TerminalKind
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
    convenience init(workspace: Workspace, kind: TerminalKind, number: Int) {
        let saved = SavedSession(id: UUID(), workspaceID: workspace.id, kind: kind,
                                 defaultName: number > 1 ? "\(kind.label) \(number)" : kind.label,
                                 directory: workspace.directory,
                                 toolSessionID: kind == .claude ? UUID() : nil)
        self.init(saved: saved, restoring: false, scrollback: nil)
    }

    /// Opens a terminal from saved data. A restored Claude or opencode terminal resumes its conversation.
    init(saved: SavedSession, restoring: Bool, scrollback: String?) {
        id = saved.id
        workspaceID = saved.workspaceID
        kind = saved.kind
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
        switch kind {
        case .plain:
            return nil
        case .claude:
            let settings = "--settings '\(AppPaths.claudeSettings.path)'"
            guard let sessionID = initialToolSessionID?.uuidString.lowercased() else { return "claude \(settings)" }
            // Claude writes the conversation file only after the first message.
            if restoring && Self.claudeConversationExists(sessionID) {
                return "claude \(settings) --resume \(sessionID)"
            }
            return "claude \(settings) --session-id \(sessionID)"
        case .opencode:
            return restoring ? "opencode --continue" : "opencode"
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
        guard kind == .plain, !exited else { return startDirectory }
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

    /// The last lines of output, as plain text. Only a Terminal kind uses it, because Claude and opencode show their history again.
    func scrollbackText(maxLines: Int = 2000) -> String? {
        guard kind == .plain else { return nil }
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
        guard kind == .claude else { return nil }
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
        SavedSession(id: id, workspaceID: workspaceID, kind: kind, defaultName: defaultName,
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
