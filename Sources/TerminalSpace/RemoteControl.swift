import Foundation
import ServiceManagement

/// The settings for the Dispatch terminal: a Claude terminal with Remote Control on.
/// From the Claude app, /ts-session in the Dispatch session opens new TerminalSpace sessions on this Mac.
struct RemoteControlSettings: Codable, Equatable {
    var enabled = false
    var folder = "~"
    var permissionMode = "default"
    /// Run Claude under `caffeinate -i`, so that the Mac does not go to idle sleep.
    var keepAwake = true

    /// The permission modes for the Dispatch session and the remote sessions. bypassPermissions is not in the list on purpose.
    static let permissionModes = ["default", "acceptEdits", "auto", "plan", "dontAsk"]

    /// The name of the Dispatch session in TerminalSpace and in the Claude app.
    static let dispatchName = "Dispatch"

    private static let key = "remoteControl"

    static func load() -> RemoteControlSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode(RemoteControlSettings.self, from: data) else {
            return RemoteControlSettings()
        }
        return saved
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    var expandedFolder: String { (folder as NSString).expandingTildeInPath }

    /// The name from --remote-control is the title in the Claude app. A name from `claude remote-control --name` did not show.
    /// TerminalSpace adds --settings and the session flags, so that the conversation resumes after a restart.
    var command: String {
        let name = TerminalSession.shellQuoted(Self.dispatchName)
        let claude = "claude --remote-control \(name) --name \(name) --permission-mode \(permissionMode)"
        return keepAwake ? "caffeinate -i " + claude : claude
    }

    var launcher: Launcher {
        Launcher(id: Launcher.remoteControlID, name: Self.dispatchName, symbol: "antenna.radiowaves.left.and.right",
                 command: command, integration: .claude)
    }

    /// The link host that opens a remote session: terminalspace://remote-session?name=<name>
    static let sessionLinkHost = "remote-session"

    /// A session name must match this pattern, so that a link cannot put other text in the command.
    static let sessionNamePattern = #"^[A-Za-z0-9][A-Za-z0-9 ._-]{0,39}$"#

    /// A Claude terminal with Remote Control on. You can use it from the Claude app now and from TerminalSpace later.
    /// A restored terminal resumes its conversation, and Remote Control connects to the same remote session again.
    func sessionLauncher(name: String) -> Launcher {
        let quoted = TerminalSession.shellQuoted(name)
        return Launcher(name: name, symbol: "iphone",
                        command: "claude --remote-control \(quoted) --name \(quoted) --permission-mode \(permissionMode)",
                        integration: .claude)
    }
}

/// The /ts-session command for Claude Code. The Dispatch session uses it to open new TerminalSpace sessions.
/// The app bundle has a copy. Settings > Remote copies it to ~/.claude/commands.
enum DispatchCommand {
    enum Status { case installed, outdated, missing, unavailable }

    static let installedURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".claude/commands/ts-session.md")

    /// The copy in the app bundle. A build without a bundle, for example from `swift run`, has no copy.
    private static var bundled: String? {
        Bundle.main.url(forResource: "ts-session", withExtension: "md")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }

    static var status: Status {
        guard let bundled else { return .unavailable }
        guard let installed = try? String(contentsOf: installedURL, encoding: .utf8) else { return .missing }
        return installed == bundled ? .installed : .outdated
    }

    /// Returns an error message, or nil if the copy worked.
    static func install() -> String? {
        guard let bundled else { return "The app bundle has no copy of the command." }
        do {
            try FileManager.default.createDirectory(at: installedURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try bundled.write(to: installedURL, atomically: true, encoding: .utf8)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

/// Opens TerminalSpace at login, through the Login Items of macOS.
enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    /// Returns an error message, or nil if the change worked.
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
