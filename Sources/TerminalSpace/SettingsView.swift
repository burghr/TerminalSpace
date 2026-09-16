import SwiftUI

struct SettingsView: View {
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
