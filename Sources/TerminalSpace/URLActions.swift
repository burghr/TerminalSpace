import Foundation

/// One parameter of a link action. A link must give a value that matches the whole pattern.
struct LinkParameter: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var pattern: String
}

/// A link of the form terminalspace://<name>?<parameter>=<value>, for example from a browser plugin.
/// Any web page can open such a link. So a link only gives values: the action sets the workspace,
/// the folder, the launcher, and the arguments.
struct LinkAction: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var parameters: [LinkParameter]
    /// The link can also bring JSON data: data=<base64url>, or source=download for a file in Downloads.
    var acceptsData = false
    var workspaceName: String
    var folder: String
    var launcherID: UUID
    /// One argument for each line. TerminalSpace puts each line in shell quotes.
    var arguments: String
    var askBeforeOpen = true

    static func new(launcherID: UUID) -> LinkAction {
        LinkAction(name: "open", parameters: [LinkParameter(name: "id", pattern: "^[A-Za-z0-9]{1,64}$")],
                   workspaceName: "Link {id:8}", folder: "~", launcherID: launcherID, arguments: "")
    }
}

/// A link after the checks: the action, the parameter values, and where the data is.
struct LinkRequest {
    var action: LinkAction
    var values: [String: String]
    var inlineData: String?
    var dataFromDownload = false

    /// The first parameter names the data file.
    var key: String { values[action.parameters[0].name] ?? "" }
}

enum LinkActions {
    static let scheme = "terminalspace"
    static let dataName = "data"
    static let sourceName = "source"
    static let dataFilePlaceholder = "data_file"

    static let dataDirectory = AppPaths.support.appendingPathComponent("link-data", isDirectory: true)
    static let linkDataLimit = 64 * 1024
    static let fileDataLimit = 1024 * 1024

    private static let placeholderRegex = try! NSRegularExpression(pattern: #"\{([A-Za-z0-9_]+)(?::([0-9]+))?\}"#)

    // MARK: Checks

    /// True when the pattern matches the whole value. An empty or a bad pattern matches nothing.
    static func fullMatch(_ value: String, pattern: String) -> Bool {
        guard !pattern.isEmpty, let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(value.startIndex..., in: value)
        return regex.firstMatch(in: value, range: range)?.range == range
    }

    static func isValidPattern(_ pattern: String) -> Bool {
        !pattern.isEmpty && (try? NSRegularExpression(pattern: pattern)) != nil
    }

    /// A value that becomes part of a file name must have letters, digits, "-", and "_" only.
    static func isSafeFileName(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 128
            && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    private static func isName(_ value: String, extra: Set<Character>) -> Bool {
        !value.isEmpty && value.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isUppercase || $0.isNumber || extra.contains($0)) }
    }

    /// The problems in the settings of an action. The settings view shows them, and a link to an action
    /// with problems does not open.
    static func problems(_ action: LinkAction, among actions: [LinkAction], launchers: [Launcher]) -> [String] {
        var result: [String] = []
        if !isName(action.name, extra: ["-"]) || action.name != action.name.lowercased() {
            result.append("The name must have lowercase letters, digits, and \"-\" only.")
        }
        if actions.contains(where: { $0.id != action.id && $0.name == action.name }) {
            result.append("Another action has the same name.")
        }
        var seen = Set<String>()
        for parameter in action.parameters {
            if !isName(parameter.name, extra: ["_"]) || parameter.name == dataFilePlaceholder {
                result.append("The parameter name \"\(parameter.name)\" must have letters, digits, and \"_\" only.")
            } else if [dataName, sourceName].contains(parameter.name) {
                result.append("The parameter name \"\(parameter.name)\" is reserved for the data.")
            } else if !seen.insert(parameter.name).inserted {
                result.append("The parameter name \"\(parameter.name)\" is used two times.")
            }
            if !isValidPattern(parameter.pattern) {
                result.append("The pattern of \"\(parameter.name)\" is empty or not valid.")
            }
        }
        if action.acceptsData && action.parameters.isEmpty {
            result.append("An action that accepts data needs one parameter at least. The first parameter names the data file.")
        }
        for name in placeholders(in: action.workspaceName + "\n" + action.arguments) {
            if name == dataFilePlaceholder {
                if !action.acceptsData { result.append("{data_file} needs \"Accept data\".") }
            } else if !seen.contains(name) {
                result.append("The placeholder {\(name)} is not a parameter.")
            }
        }
        if !launchers.contains(where: { $0.id == action.launcherID }) {
            result.append("Select a launcher.")
        }
        return result
    }

    // MARK: Templates

    static func placeholders(in template: String) -> [String] {
        let range = NSRange(template.startIndex..., in: template)
        return placeholderRegex.matches(in: template, range: range).compactMap { match in
            Range(match.range(at: 1), in: template).map { String(template[$0]) }
        }
    }

    /// Replaces {name} with the value of a parameter, {name:8} with its first 8 characters,
    /// and {data_file} with the path of the data file.
    static func expand(_ template: String, values: [String: String], dataFile: String?) -> String {
        let range = NSRange(template.startIndex..., in: template)
        var result = ""
        var last = template.startIndex
        for match in placeholderRegex.matches(in: template, range: range) {
            guard let whole = Range(match.range, in: template), let nameRange = Range(match.range(at: 1), in: template) else { continue }
            let name = String(template[nameRange])
            var value = name == dataFilePlaceholder ? dataFile : values[name]
            if let limitRange = Range(match.range(at: 2), in: template), let limit = Int(template[limitRange]) {
                value = value.map { String($0.prefix(limit)) }
            }
            result += template[last..<whole.lowerBound]
            result += value ?? String(template[whole])
            last = whole.upperBound
        }
        return result + template[last...]
    }

    /// The arguments for the launcher: one for each line that is not empty.
    static func arguments(_ action: LinkAction, values: [String: String], dataFile: String?) -> [String] {
        action.arguments.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { expand($0, values: values, dataFile: dataFile) }
    }

    // MARK: Links

    /// Checks a link against the actions. Returns the request, or the reason for a rejection.
    static func request(for url: URL, actions: [LinkAction], launchers: [Launcher]) -> Result<LinkRequest, LinkError> {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == scheme else { return .failure(LinkError("This is not a TerminalSpace link.")) }
        let name = components.host?.lowercased() ?? ""
        guard let action = actions.first(where: { $0.name == name }) else {
            return .failure(LinkError("No link action has the name \"\(name.prefix(64))\". Add one in Settings > Links."))
        }
        guard problems(action, among: actions, launchers: launchers).isEmpty else {
            return .failure(LinkError("The link action \"\(name)\" has problems. Fix them in Settings > Links."))
        }

        var values: [String: String] = [:]
        var inlineData: String?
        var source: String?
        for item in components.queryItems ?? [] {
            guard let value = item.value, values[item.name] == nil else {
                return .failure(LinkError("The link gives \"\(item.name.prefix(64))\" two times, or without a value."))
            }
            if action.acceptsData && item.name == dataName && inlineData == nil {
                inlineData = value
            } else if action.acceptsData && item.name == sourceName && source == nil {
                source = value
            } else if let parameter = action.parameters.first(where: { $0.name == item.name }) {
                guard fullMatch(value, pattern: parameter.pattern) else {
                    return .failure(LinkError("The value of \"\(parameter.name)\" does not match its pattern in Settings > Links."))
                }
                values[item.name] = value
            } else {
                return .failure(LinkError("The action \"\(name)\" has no parameter \"\(item.name.prefix(64))\"."))
            }
        }
        if let missing = action.parameters.first(where: { values[$0.name] == nil }) {
            return .failure(LinkError("The link has no value for \"\(missing.name)\"."))
        }

        var request = LinkRequest(action: action, values: values)
        if action.acceptsData {
            guard (inlineData == nil) != (source == nil), source == nil || source == "download" else {
                return .failure(LinkError("The link must have data=… or source=download, but not both."))
            }
            guard isSafeFileName(request.key) else {
                return .failure(LinkError("The value of \"\(action.parameters[0].name)\" names the data file, so it must have letters, digits, \"-\", and \"_\" only."))
            }
            request.inlineData = inlineData
            request.dataFromDownload = source != nil
        }
        return .success(request)
    }

    // MARK: Data

    static func dataFile(_ request: LinkRequest) -> URL {
        dataDirectory.appendingPathComponent(request.action.name, isDirectory: true)
            .appendingPathComponent("\(request.key).json")
    }

    /// The file that the browser plugin saves when the data is too large for a link.
    static func downloadFile(_ request: LinkRequest) -> URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("terminalspace-\(request.action.name)-\(request.key).json")
    }

    static func decodeBase64URL(_ text: String) -> Data? {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }

    /// Reads the data from the link or from the Downloads folder, checks that it is JSON, then saves it.
    /// A file from the Downloads folder is removed after the save.
    static func saveData(_ request: LinkRequest) -> Result<URL, LinkError> {
        let data: Data
        let download = downloadFile(request)
        if let inline = request.inlineData {
            guard inline.utf8.count <= linkDataLimit * 4 / 3 + 4, let decoded = decodeBase64URL(inline),
                  decoded.count <= linkDataLimit else {
                return .failure(LinkError("The data in the link is not valid base64url, or it is larger than \(linkDataLimit / 1024) KB."))
            }
            data = decoded
        } else {
            guard let size = (try? download.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else {
                return .failure(LinkError("TerminalSpace did not find \(download.lastPathComponent) in the Downloads folder."))
            }
            guard size <= fileDataLimit, let contents = try? Data(contentsOf: download) else {
                return .failure(LinkError("\(download.lastPathComponent) is larger than \(fileDataLimit / 1024) KB, or TerminalSpace cannot read it."))
            }
            data = contents
        }
        guard (try? JSONSerialization.jsonObject(with: data)) != nil else {
            return .failure(LinkError("The data is not valid JSON."))
        }

        let file = dataFile(request)
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
        } catch {
            return .failure(LinkError("TerminalSpace could not save the data: \(error.localizedDescription)"))
        }
        if request.dataFromDownload { try? FileManager.default.removeItem(at: download) }
        return .success(file)
    }
}

/// The reason why TerminalSpace did not open a link.
struct LinkError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
