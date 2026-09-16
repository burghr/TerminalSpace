import AppKit
import SwiftTerm

/// A color set for the terminal. The names and colors follow the profiles of the macOS Terminal app.
struct TerminalTheme: Identifiable, Hashable {
    let id: String
    let name: String
    let background: String
    let foreground: String
    let cursor: String
    let selection: String

    /// The 16 ANSI colors of the macOS Terminal app.
    static let terminalANSI = [
        "000000", "990000", "00A600", "999900", "0000B2", "B200B2", "00A6B2", "BFBFBF",
        "666666", "E50000", "00D900", "E5E500", "0000FF", "E500E5", "00E5E5", "E5E5E5",
    ]

    static let basicLight = TerminalTheme(id: "basic", name: "Basic", background: "FFFFFF", foreground: "000000",
                                          cursor: "929292", selection: "B4D5FE")
    static let basicDark = TerminalTheme(id: "basic", name: "Basic", background: "1E1E1E", foreground: "FFFFFF",
                                         cursor: "929292", selection: "3F638B")

    /// "Basic" follows the light or dark appearance of macOS, as in the Terminal app.
    static let all: [TerminalTheme] = [
        basicLight,
        TerminalTheme(id: "pro", name: "Pro", background: "000000", foreground: "F2F2F2", cursor: "4D4D4D", selection: "414141"),
        TerminalTheme(id: "homebrew", name: "Homebrew", background: "000000", foreground: "28FE14", cursor: "23FF18", selection: "083905"),
        TerminalTheme(id: "ocean", name: "Ocean", background: "224FBC", foreground: "FFFFFF", cursor: "7F7F7F", selection: "216DFF"),
        TerminalTheme(id: "grass", name: "Grass", background: "13773D", foreground: "FFF0A5", cursor: "8E2800", selection: "B64926"),
        TerminalTheme(id: "manpage", name: "Man Page", background: "FEF49C", foreground: "000000", cursor: "7F7F7F", selection: "A4C9CD"),
        TerminalTheme(id: "novel", name: "Novel", background: "DFDBC3", foreground: "3B2322", cursor: "3A2322", selection: "A4A38C"),
        TerminalTheme(id: "redsands", name: "Red Sands", background: "7A251E", foreground: "D7C9A7", cursor: "FFFFFF", selection: "3F0000"),
        TerminalTheme(id: "silveraerogel", name: "Silver Aerogel", background: "929292", foreground: "000000", cursor: "D9D9D9", selection: "7A7A7A"),
    ]

    /// The sidebar color for a workspace with this theme. "Basic" has none, so the workspace keeps its own color.
    /// Themes with a colored background use a clear version of that color. Pro and Homebrew use their text color.
    var accentHex: String? {
        switch id {
        case "pro": return "A6A6A6"
        case "homebrew": return "28FE14"
        case "ocean": return "3B73F0"
        case "grass": return "2EA35F"
        case "manpage": return "E6CF3C"
        case "novel": return "B39C6B"
        case "redsands": return "C4473C"
        case "silveraerogel": return "929292"
        default: return nil
        }
    }

    static var systemIsDark: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    /// Finds a theme by its ID. An unknown ID gives "Basic".
    static func named(_ id: String) -> TerminalTheme {
        if id == "basic" { return systemIsDark ? basicDark : basicLight }
        return all.first { $0.id == id } ?? (systemIsDark ? basicDark : basicLight)
    }
}

enum CursorShape: String, CaseIterable, Identifiable {
    case block, bar, underline

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    func style(blink: Bool) -> CursorStyle {
        switch self {
        case .block: return blink ? .blinkBlock : .steadyBlock
        case .bar: return blink ? .blinkBar : .steadyBar
        case .underline: return blink ? .blinkUnderline : .steadyUnderline
        }
    }
}

/// The settings that control how all terminals look.
struct TerminalAppearance {
    var theme: TerminalTheme
    var fontName: String
    var fontSize: Double
    var cursor: CursorShape
    var cursorBlink: Bool

    var font: NSFont {
        let size = CGFloat(fontSize)
        if !fontName.isEmpty, let font = NSFont(name: fontName, size: size) { return font }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

extension NSColor {
    convenience init(hex: String) {
        let value = UInt32(hex, radix: 16) ?? 0
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}

extension SwiftTerm.Color {
    convenience init(hex: String) {
        let value = UInt32(hex, radix: 16) ?? 0
        self.init(red: UInt16((value >> 16) & 0xFF) * 257,
                  green: UInt16((value >> 8) & 0xFF) * 257,
                  blue: UInt16(value & 0xFF) * 257)
    }
}

extension LocalProcessTerminalView {
    func apply(_ appearance: TerminalAppearance) {
        let theme = appearance.theme
        installColors(TerminalTheme.terminalANSI.map { SwiftTerm.Color(hex: $0) })
        nativeBackgroundColor = NSColor(hex: theme.background)
        nativeForegroundColor = NSColor(hex: theme.foreground)
        caretColor = NSColor(hex: theme.cursor)
        selectedTextBackgroundColor = NSColor(hex: theme.selection)
        if font != appearance.font { font = appearance.font }
        getTerminal().setCursorStyle(appearance.cursor.style(blink: appearance.cursorBlink))

        // The container around the terminal uses the same background, so no gap shows at the edge.
        superview?.wantsLayer = true
        superview?.layer?.backgroundColor = nativeBackgroundColor.cgColor
    }
}
