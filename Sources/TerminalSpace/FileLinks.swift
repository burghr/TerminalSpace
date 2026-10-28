import AppKit
import SwiftTerm

/// A terminal view that opens local files on Command-click, as Terminal.app does.
/// SwiftTerm finds only URLs with a scheme, so a plain path such as `Sources/App.swift:12` goes here.
final class FileLinkTerminalView: LocalProcessTerminalView {
    /// The folder for relative paths. The session sets it.
    var directory: () -> String = { NSHomeDirectory() }

    override func mouseUp(with event: NSEvent) {
        if event.modifierFlags.contains(.command), event.clickCount == 1,
           let url = fileURL(at: convert(event.locationInWindow, from: nil)) {
            NSWorkspace.shared.open(url)
            return
        }
        super.mouseUp(with: event)
    }

    /// The URL of an existing file under the point, or nil.
    private func fileURL(at point: NSPoint) -> URL? {
        guard let (text, index) = logicalLine(at: point) else { return nil }
        for candidate in Self.candidates(in: text, at: index) {
            if let url = resolve(candidate) { return url }
        }
        return nil
    }

    /// The text of the line under the point, with the lines that wrap into it, and the index of the clicked character.
    private func logicalLine(at point: NSPoint) -> (text: [Character], index: Int)? {
        let scale = window?.backingScaleFactor ?? 1
        guard let cell = cellSizeInPixels(source: terminal), cell.width > 0, cell.height > 0 else { return nil }
        let cellWidth = CGFloat(cell.width) / scale
        let cellHeight = CGFloat(cell.height) / scale
        let col = Int(point.x / cellWidth)
        let row = Int((frame.height - point.y) / cellHeight)
        guard col >= 0, col < terminal.cols, terminal.getLine(row: row) != nil else { return nil }

        var first = row
        while first > 0, terminal.getLine(row: first)?.isWrapped == true { first -= 1 }
        var last = row
        while terminal.getLine(row: last + 1)?.isWrapped == true { last += 1 }

        var text: [Character] = []
        var index = 0
        for line in first...last {
            guard let bufferLine = terminal.getLine(row: line) else { break }
            if line == row { index = text.count + col }
            text += Array(bufferLine.translateToString(endCol: terminal.cols))
        }
        return index < text.count ? (text, index) : nil
    }

    /// The characters that end a path. A path with a space in it is not found.
    private static let delimiters = Set<Character>(" \t\0\"'`()[]{}<>|,;")

    /// Possible paths around the index, from the longest to the shortest.
    static func candidates(in text: [Character], at index: Int) -> [String] {
        guard !delimiters.contains(text[index]) else { return [] }
        var start = index
        while start > 0, !delimiters.contains(text[start - 1]) { start -= 1 }
        var end = index + 1
        while end < text.count, !delimiters.contains(text[end]) { end += 1 }

        var word = String(text[start..<end])
        // Remove punctuation at the end of a sentence, for example "see App.swift.".
        while let lastChar = word.last, ".:".contains(lastChar) { word.removeLast() }
        // Remove a line and column suffix, for example "App.swift:12" or "App.swift:12:5".
        let path = word.replacingOccurrences(of: #"(:\d+){1,2}$"#, with: "", options: .regularExpression)
        guard !path.isEmpty, !path.contains("://") else { return [] }

        var result = [path]
        // A git diff writes "a/path" and "b/path".
        if path.hasPrefix("a/") || path.hasPrefix("b/") { result.append(String(path.dropFirst(2))) }
        return result
    }

    private func resolve(_ path: String) -> URL? {
        let expanded = (path as NSString).expandingTildeInPath
        let full = expanded.hasPrefix("/") ? expanded : (directory() as NSString).appendingPathComponent(expanded)
        let standardized = (full as NSString).standardizingPath
        return FileManager.default.fileExists(atPath: standardized) ? URL(fileURLWithPath: standardized) : nil
    }
}
