import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        TabView {
            AppearanceSettingsView(store: store)
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            LaunchersSettingsView(store: store)
                .tabItem { Label("Launchers", systemImage: "list.bullet.rectangle") }
        }
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
