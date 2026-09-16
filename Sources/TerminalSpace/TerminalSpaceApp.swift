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
                Button("New Terminal") { store.newSession(.plain) }
                    .keyboardShortcut("t")
                Button("New Claude Terminal") { store.newSession(.claude) }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                Button("New opencode Terminal") { store.newSession(.opencode) }
                    .keyboardShortcut("t", modifiers: [.command, .option])
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
