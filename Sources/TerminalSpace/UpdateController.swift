import AppKit
import Foundation

/// Checks GitHub for a new TerminalSpace release at the start and every 6 hours
/// ("Check for updates automatically", on by default), and from the menu.
/// It never installs without the user's OK. A version that the user skipped
/// does not ask again; a newer version asks again.
@MainActor
final class UpdateController: ObservableObject {
    static let shared = UpdateController()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String)
        case installing(version: String)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var available: ReleaseInfo?
    @Published private(set) var lastCheck: Date?

    /// True after the user agreed to install. The app then quits without its
    /// "terminals are still running" alert, because the update dialog said so.
    private(set) var quittingForUpdate = false

    static let autoCheckKey = "autoCheckUpdates"
    static let skippedVersionKey = "skippedUpdateVersion"
    private static let interval: TimeInterval = 6 * 60 * 60
    private var timer: Timer?
    private var promptOpen = false

    var autoCheck: Bool {
        get { UserDefaults.standard.object(forKey: Self.autoCheckKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.autoCheckKey); objectWillChange.send() }
    }

    var currentVersion: String { UpdateCheck.currentVersion }

    func start() {
        // Wait a short time after the start, so that the network is up.
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            Task { await self?.automaticCheck() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.automaticCheck() }
        }
    }

    private func automaticCheck() async {
        guard autoCheck else { return }
        await check(manual: false)
        guard let release = available, case .available = state else { return }
        if UserDefaults.standard.string(forKey: Self.skippedVersionKey) == release.version {
            NSLog("[TerminalSpace] update %@ was skipped by the user; no prompt", release.version)
            return
        }
        prompt(release)
    }

    /// Reads the latest release. An automatic check that fails stays quiet;
    /// a manual check shows the result.
    func check(manual: Bool) async {
        if case .installing = state { return }
        state = .checking
        defer { lastCheck = Date() }
        do {
            let latest = try await UpdateCheck.fetchLatest()
            guard UpdateCheck.compare(latest.version, currentVersion) == .orderedDescending else {
                available = nil
                state = .upToDate
                return
            }
            available = latest
            state = .available(version: latest.version)
            NSLog("[TerminalSpace] update check: %@ is available (this is %@)", latest.version, currentVersion)
        } catch {
            NSLog("[TerminalSpace] update check failed: %@", error.localizedDescription)
            state = manual ? .failed(error.localizedDescription) : .idle
        }
    }

    /// The menu item: always shows a result.
    func checkNow() {
        Task {
            await check(manual: true)
            if let release = available, case .available = state {
                prompt(release)
                return
            }
            let alert = NSAlert()
            switch state {
            case .upToDate:
                alert.messageText = "TerminalSpace is up to date"
                alert.informativeText = "Version \(currentVersion) is the latest version."
            case .failed(let text):
                alert.messageText = "The update check failed"
                alert.informativeText = text
            default:
                return
            }
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    /// Asks the user about a new release. TerminalSpace installs only after
    /// "Install and Restart".
    func prompt(_ release: ReleaseInfo) {
        guard !promptOpen else { return }
        promptOpen = true
        defer { promptOpen = false }

        let running = AppStore.shared.runningCount
        let alert = NSAlert()
        alert.messageText = "TerminalSpace \(release.version) is available"
        var text = "You have version \(currentVersion). TerminalSpace restarts to install the update."
        if running > 0 {
            text += " Your \(running) terminal\(running == 1 ? "" : "s") open again after the restart:"
                + " Claude and opencode resume their conversations, and other commands start again."
        }
        if let notes = release.shortNotes { text += "\n\n" + notes }
        alert.informativeText = text
        alert.addButton(withTitle: "Install and Restart")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Skip This Version")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task { await install() }
        case .alertThirdButtonReturn:
            UserDefaults.standard.set(release.version, forKey: Self.skippedVersionKey)
            NSLog("[TerminalSpace] user skipped update %@", release.version)
        default:
            break
        }
    }

    /// Installs the available release and restarts. Call only after the user agreed.
    func install() async {
        guard let release = available else { return }
        state = .installing(version: release.version)
        do {
            let current = Bundle.main.bundleURL
            try AppUpdater.checkLocation(current)
            let newApp = try await AppUpdater.prepare(release)
            try AppUpdater.install(newApp, replacing: current)
            NSLog("[TerminalSpace] installed %@; restarting", release.version)
            AppUpdater.relaunch(current)
            quittingForUpdate = true
            NSApp.terminate(nil)
        } catch {
            NSLog("[TerminalSpace] update failed: %@", error.localizedDescription)
            state = .failed(error.localizedDescription)
            let alert = NSAlert()
            alert.messageText = "The update did not install"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "Open the Release Page")
            alert.addButton(withTitle: "Close")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn { openReleasePage() }
        }
    }

    func openReleasePage() {
        let link = available?.htmlURL ?? "https://github.com/\(UpdateCheck.repository)/releases/latest"
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }
}
