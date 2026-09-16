import SwiftUI

@main
struct TerminalSpaceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var store = AppStore.shared

    var body: some Scene {
        Window("TerminalSpace", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 700, minHeight: 400)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Workspace…") { store.addWorkspace() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Divider()
                ForEach(Array(store.launchers.prefix(9).enumerated()), id: \.element.id) { index, launcher in
                    Button("New \(launcher.name)") { store.newSession(launcher) }
                        .keyboardShortcut(LauncherShortcut.forPosition(index))
                }
                Divider()
                Button("Run Command…") { store.promptForCommand() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .saveItem) {
                Button("Close Terminal") { store.closeSession(store.selection) }
                    .keyboardShortcut("w")
                    .disabled(store.selection == nil)
            }
        }

        Settings {
            SettingsView(store: store)
        }
    }
}

/// Keyboard shortcuts for the launchers, from their position in the menu.
enum LauncherShortcut {
    static func forPosition(_ index: Int) -> KeyboardShortcut? {
        switch index {
        case 0: return KeyboardShortcut("t")
        case 1: return KeyboardShortcut("t", modifiers: [.command, .shift])
        case 2: return KeyboardShortcut("t", modifiers: [.command, .option])
        case 3...8: return KeyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command, .control])
        default: return nil
        }
    }

    static func label(_ index: Int) -> String? {
        switch index {
        case 0: return "⌘T"
        case 1: return "⇧⌘T"
        case 2: return "⌥⌘T"
        case 3...8: return "⌃⌘\(index + 1)"
        default: return nil
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var termSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // SIGTERM (for example from `build.sh --run`) saves the terminals and quits without the confirmation alert.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            AppStore.shared.saveForQuit()
            exit(0)
        }
        source.resume()
        termSource = source

        // A bare executable from `swift run` needs these two calls to get a Dock icon and keyboard focus.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let running = AppStore.shared.runningCount
        if running > 0 {
            let alert = NSAlert()
            alert.messageText = "Quit TerminalSpace?"
            alert.informativeText = "\(running) terminal\(running == 1 ? " is" : "s are") still running. "
                + "Quit stops the running commands. The terminals open again at the next start."
            alert.addButton(withTitle: "Quit")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        }
        AppStore.shared.saveForQuit()
        return .terminateNow
    }
}
