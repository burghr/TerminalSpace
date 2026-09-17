import AppKit
import Combine

final class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published var workspaces: [Workspace] = [] { didSet { saveWorkspaces() } }
    @Published var sessions: [TerminalSession] = []
    @Published var selection: UUID? {
        didSet {
            if let session = selectedSession { activeWorkspaceID = session.workspaceID }
            if oldValue != selection { saveSessions() }
        }
    }
    @Published var activeWorkspaceID: UUID?

    /// The entries of the new-terminal menu, in menu order.
    @Published var launchers: [Launcher] = AppStore.loadLaunchers() {
        didSet {
            if launchers.isEmpty { launchers = Launcher.defaults }
            if let data = try? JSONEncoder().encode(launchers) { UserDefaults.standard.set(data, forKey: "launchers") }
        }
    }

    /// The workspace for the "Run Command" prompt. A non-nil value shows the prompt.
    @Published var commandPromptWorkspaceID: UUID?

    private static func loadLaunchers() -> [Launcher] {
        guard let data = UserDefaults.standard.data(forKey: "launchers"),
              let saved = try? JSONDecoder().decode([Launcher].self, from: data), !saved.isEmpty else {
            return Launcher.defaults
        }
        return saved
    }

    // MARK: Appearance settings

    @Published var defaultThemeID: String = UserDefaults.standard.string(forKey: "theme") ?? "basic" {
        didSet { UserDefaults.standard.set(defaultThemeID, forKey: "theme"); applyAppearance() }
    }
    @Published var fontName: String = UserDefaults.standard.string(forKey: "fontName") ?? "" {
        didSet { UserDefaults.standard.set(fontName, forKey: "fontName"); applyAppearance() }
    }
    @Published var fontSize: Double = UserDefaults.standard.object(forKey: "fontSize") as? Double ?? 13 {
        didSet { UserDefaults.standard.set(fontSize, forKey: "fontSize"); applyAppearance() }
    }
    @Published var cursorShape: CursorShape = CursorShape(rawValue: UserDefaults.standard.string(forKey: "cursorShape") ?? "") ?? .block {
        didSet { UserDefaults.standard.set(cursorShape.rawValue, forKey: "cursorShape"); applyAppearance() }
    }
    @Published var cursorBlink: Bool = UserDefaults.standard.bool(forKey: "cursorBlink") {
        didSet { UserDefaults.standard.set(cursorBlink, forKey: "cursorBlink"); applyAppearance() }
    }

    func appearance(for workspaceID: UUID) -> TerminalAppearance {
        let themeID = workspaces.first { $0.id == workspaceID }?.theme ?? defaultThemeID
        return TerminalAppearance(theme: TerminalTheme.named(themeID), fontName: fontName, fontSize: fontSize,
                                  cursor: cursorShape, cursorBlink: cursorBlink)
    }

    /// Applies the current settings to all terminals. Call it after a change to a setting, a workspace theme, or the system appearance.
    func applyAppearance() {
        for session in sessions { session.view.apply(appearance(for: session.workspaceID)) }
    }

    func setWorkspaceTheme(_ id: UUID, to themeID: String?) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces[index].theme = themeID
        applyAppearance()
    }

    private var sessionObservers: [UUID: AnyCancellable] = [:]
    private var restoring = false

    private struct SavedLayout: Codable {
        var selection: UUID?
        var sessions: [SavedSession]
    }

    private let workspacesURL = AppPaths.support.appendingPathComponent("workspaces.json")
    private let sessionsURL = AppPaths.support.appendingPathComponent("sessions.json")
    private let scrollbackDirectory = AppPaths.support.appendingPathComponent("scrollback", isDirectory: true)

    init() {
        if let data = try? Data(contentsOf: workspacesURL),
           let saved = try? JSONDecoder().decode([Workspace].self, from: data) {
            workspaces = saved
        }
        if workspaces.isEmpty {
            workspaces = [Workspace(name: "Home", directory: NSHomeDirectory())]
        }
        activeWorkspaceID = workspaces.first?.id
        restoreSessions()
    }

    var selectedSession: TerminalSession? {
        sessions.first { $0.id == selection }
    }

    var activeWorkspace: Workspace? {
        workspaces.first { $0.id == activeWorkspaceID } ?? workspaces.first
    }

    var runningCount: Int { sessions.filter { !$0.exited }.count }

    func sessions(in workspace: Workspace) -> [TerminalSession] {
        sessions.filter { $0.workspaceID == workspace.id }
    }

    // MARK: Workspaces

    func addWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Create Workspace"
        panel.message = "Select the folder for the new workspace."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Give each new workspace the first color that no other workspace uses.
        let used = Set(workspaces.map { $0.color ?? .blue })
        let color = WorkspaceColor.allCases.first { !used.contains($0) } ?? .blue
        let workspace = Workspace(name: url.lastPathComponent, directory: url.path, color: color)
        workspaces.append(workspace)
        activeWorkspaceID = workspace.id
    }

    func renameWorkspace(_ id: UUID, to name: String) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }), !name.isEmpty else { return }
        workspaces[index].name = name
    }

    func setWorkspaceColor(_ id: UUID, to color: WorkspaceColor) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces[index].color = color
    }

    /// Moves a workspace up (negative offset) or down (positive offset) in the sidebar.
    func moveWorkspace(_ id: UUID, by offset: Int) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        let target = min(max(index + offset, 0), workspaces.count - 1)
        guard target != index else { return }
        workspaces.insert(workspaces.remove(at: index), at: target)
    }

    /// Moves a workspace to the position of a different workspace. The other workspaces move one step to make space.
    func moveWorkspace(_ id: UUID, onto targetID: UUID) {
        guard id != targetID,
              let index = workspaces.firstIndex(where: { $0.id == id }),
              let target = workspaces.firstIndex(where: { $0.id == targetID }) else { return }
        workspaces.insert(workspaces.remove(at: index), at: target)
    }

    func workspace(for session: TerminalSession) -> Workspace? {
        workspaces.first { $0.id == session.workspaceID }
    }

    func removeWorkspace(_ id: UUID) {
        for session in sessions where session.workspaceID == id { closeSession(session.id) }
        workspaces.removeAll { $0.id == id }
        if activeWorkspaceID == id { activeWorkspaceID = workspaces.first?.id }
    }

    // MARK: Terminals

    func newSession(_ launcher: Launcher, in workspaceID: UUID? = nil) {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) ?? activeWorkspace else { return }
        let number = sessions.filter { $0.workspaceID == workspace.id && $0.launcher.id == launcher.id }.count + 1
        add(TerminalSession(workspace: workspace, launcher: launcher, number: number))
        activeWorkspaceID = workspace.id
        selection = sessions.last?.id
    }

    /// Shows the prompt for a one-time command.
    func promptForCommand(in workspaceID: UUID? = nil) {
        commandPromptWorkspaceID = workspaceID ?? activeWorkspace?.id
    }

    /// Starts a terminal that runs a command one time. With `save`, the command also becomes a launcher.
    func runCommand(_ command: String, in workspaceID: UUID?, save: Bool) {
        let command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        let name = command.components(separatedBy: " ").first ?? command
        let launcher = Launcher(name: name, symbol: "chevron.right", command: command)
        if save { launchers.append(launcher) }
        newSession(launcher, in: workspaceID)
    }

    private func add(_ session: TerminalSession) {
        // The sidebar shows the title of each session, so publish its changes.
        sessionObservers[session.id] = session.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        session.view.apply(appearance(for: session.workspaceID))
        sessions.append(session)
        saveSessions()
    }

    /// Moves sessions to a workspace. The index is a position in the sidebar list of that workspace; nil adds them at the end.
    /// The shell keeps its current directory. Only the group in the sidebar changes.
    func moveSessions(_ ids: [UUID], to workspaceID: UUID, at index: Int?) {
        let moving = ids.compactMap { id in sessions.first { $0.id == id } }
        guard !moving.isEmpty, workspaces.contains(where: { $0.id == workspaceID }) else { return }

        // Find the session that the moved sessions go before, from the list before the move.
        let targetList = sessions.filter { $0.workspaceID == workspaceID }
        let anchor = index.flatMap { i in
            targetList[min(i, targetList.count)...].first { item in !moving.contains { $0 === item } }
        }

        sessions.removeAll { item in moving.contains { $0 === item } }
        for session in moving { session.workspaceID = workspaceID }

        let position: Int
        if let anchor, let anchorIndex = sessions.firstIndex(where: { $0 === anchor }) {
            position = anchorIndex
        } else if let last = sessions.lastIndex(where: { $0.workspaceID == workspaceID }) {
            position = last + 1
        } else {
            position = sessions.endIndex
        }
        sessions.insert(contentsOf: moving, at: position)
        activeWorkspaceID = workspaceID
        // The new workspace can have a different theme.
        applyAppearance()
        saveSessions()
    }

    func renameSession(_ id: UUID, to name: String) {
        sessions.first { $0.id == id }?.customName = name.isEmpty ? nil : name
        saveSessions()
    }

    func closeSession(_ id: UUID?) {
        guard let id, let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        let session = sessions[index]
        session.terminate()
        session.removeClaudeState()
        sessionObservers[id] = nil
        sessions.remove(at: index)

        if selection == id {
            // Select a neighbor in the same workspace, if one exists.
            let siblings = sessions.filter { $0.workspaceID == session.workspaceID }
            selection = siblings.last?.id
        }
        saveSessions()
    }

    // MARK: Save and restore

    private func saveWorkspaces() {
        guard let data = try? JSONEncoder().encode(workspaces) else { return }
        try? data.write(to: workspacesURL, options: .atomic)
    }

    /// Saves the list of terminals. The app calls this after each change, so a crash loses little.
    func saveSessions() {
        guard !restoring else { return }
        let layout = SavedLayout(selection: selection, sessions: sessions.map(\.saved))
        guard let data = try? JSONEncoder().encode(layout) else { return }
        try? data.write(to: sessionsURL, options: .atomic)
    }

    /// Saves the terminals and their output. The app calls this before it quits.
    func saveForQuit() {
        saveSessions()
        try? FileManager.default.removeItem(at: scrollbackDirectory)
        try? FileManager.default.createDirectory(at: scrollbackDirectory, withIntermediateDirectories: true)
        for session in sessions {
            guard let text = session.scrollbackText() else { continue }
            try? text.write(to: scrollbackURL(session.id), atomically: true, encoding: .utf8)
        }
    }

    private func scrollbackURL(_ id: UUID) -> URL {
        scrollbackDirectory.appendingPathComponent("\(id.uuidString).txt")
    }

    private func restoreSessions() {
        guard let data = try? Data(contentsOf: sessionsURL),
              let layout = try? JSONDecoder().decode(SavedLayout.self, from: data) else { return }

        restoring = true
        for saved in layout.sessions where workspaces.contains(where: { $0.id == saved.workspaceID }) {
            let scrollback = try? String(contentsOf: scrollbackURL(saved.id), encoding: .utf8)
            add(TerminalSession(saved: saved, restoring: true, scrollback: scrollback))
        }
        // The output shows one time only. A crash later must not show old output again.
        try? FileManager.default.removeItem(at: scrollbackDirectory)

        selection = sessions.contains { $0.id == layout.selection } ? layout.selection : sessions.first?.id
        restoring = false
    }
}
