// TerminalSpace: update check and install from GitHub releases.
// The code comes from MacMixer's Updater.swift (same checks), with TerminalSpace names.
//
// The order: read the latest release from the GitHub API, compare its version
// with this build, download the zip, check the SHA-256 that GitHub gives for
// the file, unpack it, check the app in it (bundle ID, version, valid code
// signature), replace this app bundle in one step, then quit and open the new
// version.
//
// A release must be signed with the Developer ID Application certificate of
// team 3YULF6FJ6W and notarized by Apple. A file from GitHub that has a
// different signer is refused, also when the GitHub checksum matches.

import AppKit
import CryptoKit
import Foundation
import Security

// MARK: - Release data

struct ReleaseAsset: Decodable, Equatable, Sendable {
    let name: String
    let url: String
    let size: Int64
    /// GitHub's checksum, for example "sha256:3101...".
    let digest: String?

    enum CodingKeys: String, CodingKey {
        case name, url = "browser_download_url", size, digest
    }

    /// The SHA-256 from the digest, in lowercase hex, or nil.
    var sha256: String? {
        guard let digest, digest.hasPrefix("sha256:") else { return nil }
        let hex = digest.dropFirst("sha256:".count).lowercased()
        return hex.count == 64 && hex.allSatisfy(\.isHexDigit) ? hex : nil
    }
}

struct ReleaseInfo: Decodable, Equatable, Sendable {
    let tagName: String
    let htmlURL: String
    let draft: Bool
    let prerelease: Bool
    let assets: [ReleaseAsset]
    /// The release notes (Markdown), if any.
    let body: String?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name", htmlURL = "html_url", draft, prerelease, assets, body
    }

    /// The release notes as plain text for a dialog: no Markdown marks, at
    /// most 600 characters.
    var shortNotes: String? {
        guard let body, !body.isEmpty else { return nil }
        var text = body.replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "\r", with: "")
        text = text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            var l = String(line)
            while l.hasPrefix("#") { l.removeFirst() }
            if l.hasPrefix("- ") { l = "• " + l.dropFirst(2) }
            return l.trimmingCharacters(in: .whitespaces)
        }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > 600 { text = String(text.prefix(600)) + "…" }
        return text.isEmpty ? nil : text
    }

    /// "v2.1.0" -> "2.1.0"
    var version: String {
        tagName.hasPrefix("v") || tagName.hasPrefix("V") ? String(tagName.dropFirst()) : tagName
    }

    /// The app as a zip file: "TerminalSpace-<version>.zip" or "TerminalSpace.zip".
    var appArchive: ReleaseAsset? {
        assets.first { $0.name == "TerminalSpace-\(version).zip" }
            ?? assets.first { $0.name == "TerminalSpace.zip" }
    }
}

// MARK: - Errors

enum UpdateError: LocalizedError {
    case network(String)
    case noArchive
    case checksum
    case unpack
    case notSigned
    case wrongSigner
    case notNotarized
    case wrongApp
    case wrongVersion(String)
    case location(String)
    case notWritable(String)

    var errorDescription: String? {
        switch self {
        case .network(let text): "TerminalSpace could not read the release: \(text)"
        case .noArchive: "The release has no app file (TerminalSpace.zip)."
        case .checksum: "The downloaded file does not match the checksum of the release."
        case .unpack: "TerminalSpace could not unpack the downloaded file."
        case .notSigned: "The downloaded app has no valid code signature."
        case .wrongSigner: "The downloaded app is not signed by the TerminalSpace developer."
        case .notNotarized: "Apple did not notarize the downloaded app."
        case .wrongApp: "The downloaded file does not contain TerminalSpace."
        case .wrongVersion(let v): "The downloaded app has a different version (\(v))."
        case .location(let path):
            "TerminalSpace runs from \(path). Move TerminalSpace to the Applications folder to update it."
        case .notWritable(let folder): "TerminalSpace cannot write to \(folder). Install the update from the release page."
        }
    }
}

// MARK: - Pure helpers

enum UpdateCheck {
    static let repository = "burghr/TerminalSpace"
    static let bundleID = "com.coconetlabs.terminalspace"
    /// The Apple Developer team that signs TerminalSpace releases.
    static let teamID = "3YULF6FJ6W"

    static var latestURL: URL {
        URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    }

    /// The version of this build, for example "2.1.0".
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Compares two versions part by part as numbers: "2.10.0" > "2.9.1".
    /// A suffix after "-" or "+" is ignored. A missing part counts as 0.
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        func parts(_ text: String) -> [Int] {
            var core = text.hasPrefix("v") || text.hasPrefix("V") ? String(text.dropFirst()) : text
            if let cut = core.firstIndex(where: { $0 == "-" || $0 == "+" }) { core = String(core[..<cut]) }
            return core.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p < q ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    /// Reads the latest release (GitHub excludes drafts and pre-releases).
    static func fetchLatest() async throws -> ReleaseInfo {
        var request = URLRequest(url: latestURL, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("TerminalSpace", forHTTPHeaderField: "User-Agent")
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw UpdateError.network(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw UpdateError.network("HTTP \(status)") }
        do {
            return try JSONDecoder().decode(ReleaseInfo.self, from: data)
        } catch {
            throw UpdateError.network("unexpected reply")
        }
    }
}

// MARK: - Download, check, install

enum AppUpdater {
    /// The app can replace itself only from an Applications folder. This stops
    /// an update of a debug build (DerivedData) or of a translocated copy.
    static func checkLocation(_ app: URL) throws {
        let path = app.standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let allowed = path.hasPrefix("/Applications/") || path.hasPrefix(home + "/Applications/")
        guard allowed, !path.contains("/AppTranslocation/") else { throw UpdateError.location(path) }
        let folder = app.deletingLastPathComponent().path
        let fm = FileManager.default
        guard fm.isWritableFile(atPath: folder), fm.isWritableFile(atPath: path) else {
            throw UpdateError.notWritable(folder)
        }
    }

    /// Downloads the zip, checks it, and unpacks it. Returns the new TerminalSpace.app.
    static func prepare(_ release: ReleaseInfo) async throws -> URL {
        guard let asset = release.appArchive, let url = URL(string: asset.url) else { throw UpdateError.noArchive }
        guard let expected = asset.sha256 else { throw UpdateError.checksum }

        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("TerminalSpace-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        let temp: URL, response: URLResponse
        do {
            (temp, response) = try await URLSession.shared.download(from: url)
        } catch {
            throw UpdateError.network(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw UpdateError.network("HTTP \(status)") }
        let zip = work.appendingPathComponent(asset.name)
        try FileManager.default.moveItem(at: temp, to: zip)

        guard try sha256(of: zip) == expected else { throw UpdateError.checksum }

        let unpacked = work.appendingPathComponent("unpacked")
        try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
        guard run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path]) == 0 else { throw UpdateError.unpack }
        let app = unpacked.appendingPathComponent("TerminalSpace.app")
        guard FileManager.default.fileExists(atPath: app.path) else { throw UpdateError.wrongApp }
        try verify(app: app, version: release.version)
        return app
    }

    static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The new app must have the TerminalSpace bundle ID and the release version.
    /// It must be signed by a Developer ID Application certificate of the
    /// TerminalSpace team, with the TerminalSpace identifier, and notarized.
    static func verify(app: URL, version: String) throws {
        let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        guard info?["CFBundleIdentifier"] as? String == UpdateCheck.bundleID else { throw UpdateError.wrongApp }
        let newVersion = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        guard UpdateCheck.compare(newVersion, version) == .orderedSame else {
            throw UpdateError.wrongVersion(newVersion)
        }

        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else {
            throw UpdateError.notSigned
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(code, flags, nil) == errSecSuccess else { throw UpdateError.notSigned }
        guard let requirement = developerIDRequirement(),
              SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess else {
            throw UpdateError.wrongSigner
        }
        // Gatekeeper: a Developer ID app must also be notarized.
        guard run("/usr/sbin/spctl", ["--assess", "--type", "execute", app.path]) == 0 else {
            throw UpdateError.notNotarized
        }
    }

    /// Apple's Developer ID chain (Developer ID CA and a Developer ID
    /// Application leaf), the TerminalSpace team, and the TerminalSpace identifier.
    static func developerIDRequirement() -> SecRequirement? {
        let text = """
            identifier "\(UpdateCheck.bundleID)" and anchor apple generic \
            and certificate 1[field.1.2.840.113635.100.6.2.6] exists \
            and certificate leaf[field.1.2.840.113635.100.6.1.13] exists \
            and certificate leaf[subject.OU] = "\(UpdateCheck.teamID)"
            """
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess else { return nil }
        return requirement
    }

    /// Replaces the bundle at `current` with `newApp`. The copy goes next to
    /// `current` first, so that the replacement is one rename on the same disk.
    static func install(_ newApp: URL, replacing current: URL) throws {
        try checkLocation(current)
        let folder = current.deletingLastPathComponent()
        let stage = folder.appendingPathComponent(".TerminalSpace-update-\(UUID().uuidString).app")
        guard run("/usr/bin/ditto", [newApp.path, stage.path]) == 0 else {
            try? FileManager.default.removeItem(at: stage)
            throw UpdateError.notWritable(folder.path)
        }
        do {
            _ = try FileManager.default.replaceItemAt(current, withItemAt: stage)
        } catch {
            try? FileManager.default.removeItem(at: stage)
            throw UpdateError.notWritable(folder.path)
        }
    }

    /// Opens `app` after this process ends. A small shell waits for this
    /// process ID, so that the new app does not start next to the old one.
    static func relaunch(_ app: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$0\"",
                             app.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    @discardableResult
    static func run(_ tool: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }
}

