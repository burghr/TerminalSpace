import Foundation

/// A Claude Code conversation on this Mac, found from its ID.
/// Claude keeps each conversation in ~/.claude/projects/<folder>/<id>.jsonl.
struct ClaudeConversation {
    let id: UUID
    /// The folder where the conversation ran. Claude resumes a conversation only in its own folder.
    let folder: String
    /// The custom title from /rename or --name, if the conversation has one.
    let title: String?

    /// The link host for terminalspace://resume?session=<id>.
    static let resumeLinkHost = "resume"

    /// Finds the conversation file and reads the folder and the title from it.
    /// Returns nil if no file has this ID or the file has no folder.
    static func find(_ id: UUID) -> ClaudeConversation? {
        let projects = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")
        let name = id.uuidString.lowercased() + ".jsonl"
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: projects.path)) ?? []
        for folder in folders {
            let file = projects.appendingPathComponent(folder).appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            guard let cwd = readFolder(file) else { return nil }
            return ClaudeConversation(id: id, folder: cwd, title: readTitle(file))
        }
        return nil
    }

    /// The first "cwd" value in the first 2 MB of the file.
    private static func readFolder(_ file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 2 * 1024 * 1024)) ?? Data()
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard let json = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let cwd = json["cwd"] as? String, !cwd.isEmpty else { continue }
            return cwd
        }
        return nil
    }

    /// The last custom title in the last 512 KB of the file. A conversation file can be large,
    /// and Claude writes the title again near the end after a rename.
    private static func readTitle(_ file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > 512 * 1024 ? size - 512 * 1024 : 0
        try? handle.seek(toOffset: start)
        let data = (try? handle.readToEnd()) ?? Data()
        var title: String?
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard line.count < 4096,
                  let json = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  json["type"] as? String == "custom-title",
                  let value = json["customTitle"] as? String, !value.isEmpty else { continue }
            title = value
        }
        return title
    }
}
