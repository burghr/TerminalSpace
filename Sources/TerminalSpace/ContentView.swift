import SwiftUI
import SwiftTerm

struct ContentView: View {
    @ObservedObject var store: AppStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var renameTarget: RenameTarget?
    @State private var renameText = ""
    @State private var commandText = ""

    enum RenameTarget {
        case workspace(UUID)
        case session(UUID)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItem {
                Button { store.addWorkspace() } label: {
                    Label("New Workspace", systemImage: "folder.badge.plus")
                }
                .help("New Workspace")
            }
            ToolbarItem {
                NewTerminalMenu(store: store, workspaceID: nil)
                    .help("New terminal in the current workspace")
            }
        }
        // The "Basic" theme follows the light or dark appearance of macOS.
        .onChange(of: colorScheme) { store.applyAppearance() }
        .alert("Rename", isPresented: Binding(get: { renameTarget != nil },
                                              set: { if !$0 { renameTarget = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") { applyRename() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Run Command", isPresented: Binding(get: { store.commandPromptWorkspaceID != nil },
                                                   set: { if !$0 { store.commandPromptWorkspaceID = nil } })) {
            TextField("ssh user@host", text: $commandText)
            Button("Run") { runCommand(save: false) }
            Button("Run and Save as Launcher") { runCommand(save: true) }
            Button("Cancel", role: .cancel) { commandText = "" }
        } message: {
            Text("The command starts in a new terminal. When the command stops, the terminal continues as a shell.")
        }
    }

    private var sidebar: some View {
        List(selection: $store.selection) {
            ForEach(store.workspaces) { workspace in
                Section {
                    ForEach(store.sessions(in: workspace)) { session in
                        SessionRow(session: session, tint: workspace.tint,
                                   inActiveWorkspace: store.activeWorkspaceID == workspace.id)
                            .tag(session.id)
                            .draggable(session.id.uuidString)
                            .contextMenu {
                                Button("Rename…") { beginRename(.session(session.id), session.displayName) }
                                Button("Close") { store.closeSession(session.id) }
                            }
                    }
                    .dropDestination(for: String.self) { items, index in
                        store.moveSessions(items.compactMap(UUID.init), to: workspace.id, at: index)
                    }
                } header: {
                    WorkspaceHeader(store: store, workspace: workspace)
                        .draggable(Workspace.dragPrefix + workspace.id.uuidString)
                        .contextMenu {
                            Button("Rename…") { beginRename(.workspace(workspace.id), workspace.name) }
                            Menu(workspace.themeAccent == nil ? "Color" : "Color (the theme sets it)") {
                                ForEach(WorkspaceColor.allCases) { color in
                                    Button {
                                        store.setWorkspaceColor(workspace.id, to: color)
                                    } label: {
                                        if (workspace.color ?? .blue) == color {
                                            Label(color.label, systemImage: "checkmark")
                                        } else {
                                            Text(color.label)
                                        }
                                    }
                                }
                            }
                            .disabled(workspace.themeAccent != nil)
                            Menu("Theme") {
                                themeButton(workspace, nil, "Default (\(TerminalTheme.named(store.defaultThemeID).name))")
                                Divider()
                                ForEach(TerminalTheme.all) { theme in
                                    themeButton(workspace, theme.id, theme.name)
                                }
                            }
                            Button("Show in Finder") {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: workspace.directory)
                            }
                            Divider()
                            Button("Move Up") { store.moveWorkspace(workspace.id, by: -1) }
                                .disabled(store.workspaces.first?.id == workspace.id)
                            Button("Move Down") { store.moveWorkspace(workspace.id, by: 1) }
                                .disabled(store.workspaces.last?.id == workspace.id)
                            Divider()
                            Button("Remove Workspace", role: .destructive) { store.removeWorkspace(workspace.id) }
                        }
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var detail: some View {
        if let session = store.selectedSession, let workspace = store.workspace(for: session) {
            VStack(spacing: 0) {
                WorkspaceBar(workspace: workspace, session: session)
                TerminalHost(session: session)
                    .id(session.id)
            }
            .navigationTitle(workspace.name)
            .navigationSubtitle(session.displayName)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "terminal").font(.system(size: 40)).foregroundStyle(.secondary)
                Text(store.activeWorkspace.map { "No terminal is open in \($0.name)." } ?? "No workspace")
                    .foregroundStyle(.secondary)
                HStack {
                    ForEach(store.launchers.prefix(4)) { launcher in
                        Button { store.newSession(launcher) } label: { Label(launcher.name, systemImage: launcher.symbol) }
                    }
                }
                .disabled(store.activeWorkspace == nil)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("TerminalSpace")
        }
    }

    private func themeButton(_ workspace: Workspace, _ themeID: String?, _ title: String) -> some View {
        Button {
            store.setWorkspaceTheme(workspace.id, to: themeID)
        } label: {
            if workspace.theme == themeID {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private func runCommand(save: Bool) {
        store.runCommand(commandText, in: store.commandPromptWorkspaceID, save: save)
        commandText = ""
    }

    private func beginRename(_ target: RenameTarget, _ current: String) {
        renameText = current
        renameTarget = target
    }

    private func applyRename() {
        switch renameTarget {
        case .workspace(let id): store.renameWorkspace(id, to: renameText)
        case .session(let id): store.renameSession(id, to: renameText)
        case nil: break
        }
        renameTarget = nil
    }
}

struct NewTerminalMenu: View {
    @ObservedObject var store: AppStore
    let workspaceID: UUID?

    var body: some View {
        Menu {
            ForEach(store.launchers) { launcher in
                Button { store.newSession(launcher, in: workspaceID) } label: {
                    Label(launcher.name, systemImage: launcher.symbol)
                }
            }
            Divider()
            Button { store.promptForCommand(in: workspaceID) } label: {
                Label("Run Command…", systemImage: "chevron.right")
            }
            SettingsLink {
                Label("Edit Launchers…", systemImage: "slider.horizontal.3")
            }
        } label: {
            Label("New Terminal", systemImage: "plus")
        }
    }
}

extension Workspace {
    /// A drag of a workspace carries this prefix before the ID. A drag of a terminal carries only the ID.
    static let dragPrefix = "workspace:"

    static func draggedID(_ item: String) -> UUID? {
        guard item.hasPrefix(dragPrefix) else { return nil }
        return UUID(uuidString: String(item.dropFirst(dragPrefix.count)))
    }

    /// The theme of the workspace sets the color, if the theme has one. Otherwise the workspace color applies.
    var themeAccent: SwiftUI.Color? {
        guard let theme, let hex = TerminalTheme.all.first(where: { $0.id == theme })?.accentHex else { return nil }
        return SwiftUI.Color(nsColor: NSColor(hex: hex))
    }

    var tint: SwiftUI.Color {
        if let themeAccent { return themeAccent }
        switch color ?? .blue {
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .teal: return .teal
        case .gray: return .gray
        }
    }
}

/// A gray bar above the terminal. It shows the workspace and the terminal.
struct WorkspaceBar: View {
    let workspace: Workspace
    @ObservedObject var session: TerminalSession

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .foregroundStyle(workspace.tint)
            Text(workspace.name)
                .fontWeight(.semibold)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Label(session.displayName, systemImage: session.launcher.symbol)
                .lineLimit(1)
            Spacer()
            Text((workspace.directory as NSString).abbreviatingWithTildeInPath)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(SwiftUI.Color.gray.opacity(0.15))
        .overlay(alignment: .bottom) {
            Rectangle().fill(SwiftUI.Color.gray.opacity(0.3)).frame(height: 1)
        }
    }
}

struct WorkspaceHeader: View {
    @ObservedObject var store: AppStore
    let workspace: Workspace

    @State private var dropTargeted = false

    var body: some View {
        let active = store.activeWorkspaceID == workspace.id
        HStack {
            Image(systemName: active ? "folder.fill" : "folder")
                .foregroundStyle(workspace.tint)
            Text(workspace.name)
                .fontWeight(active ? .bold : .regular)
                .foregroundStyle(active ? .primary : .secondary)
            Spacer()
            NewTerminalMenu(store: store, workspaceID: workspace.id)
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .labelStyle(.iconOnly)
                .fixedSize()
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(dropTargeted ? SwiftUI.Color.accentColor.opacity(0.35) : active ? workspace.tint.opacity(0.2) : .clear)
        }
        .overlay(alignment: .leading) {
            // A colored mark at the left edge of the current workspace.
            if active {
                RoundedRectangle(cornerRadius: 1.5).fill(workspace.tint).frame(width: 3).padding(.vertical, 3)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { store.activeWorkspaceID = workspace.id }
        // A drop on the header adds the terminal at the end. An empty workspace has no rows, so it needs this target.
        .dropDestination(for: String.self) { items, _ in
            // A dragged workspace takes the place of this workspace. A dragged terminal moves into this workspace.
            if let dragged = items.lazy.compactMap(Workspace.draggedID).first {
                store.moveWorkspace(dragged, onto: workspace.id)
            } else {
                store.moveSessions(items.compactMap(UUID.init), to: workspace.id, at: nil)
            }
            return true
        } isTargeted: { dropTargeted = $0 }
        .help(workspace.directory)
    }
}

struct SessionRow: View {
    @ObservedObject var session: TerminalSession
    let tint: SwiftUI.Color
    let inActiveWorkspace: Bool

    var body: some View {
        Label {
            Text(session.displayName)
                .lineLimit(1)
                .foregroundStyle(session.exited ? .secondary : .primary)
        } icon: {
            Image(systemName: session.launcher.symbol)
                .foregroundStyle(tint)
        }
        // Dim terminals a little in the other workspaces, and more after their process stops.
        .opacity(session.exited ? 0.6 : inActiveWorkspace ? 1 : 0.75)
        // Indent terminals under their workspace.
        .padding(.leading, 14)
    }
}

/// Hosts the long-lived terminal view of a session inside SwiftUI.
struct TerminalHost: NSViewRepresentable {
    let session: TerminalSession

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        let view = session.view
        container.wantsLayer = true
        container.layer?.backgroundColor = view.nativeBackgroundColor.cgColor
        view.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
