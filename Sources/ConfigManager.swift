import Foundation

/// One top-level key we want to set (value != nil) or ensure is absent
/// (value == nil).
struct KeySetting {
    let key: String
    let value: String?
}

/// The `[model_providers.<id>]` block we append when a third-party provider is active.
struct ProviderBlock {
    let id: String
    let baseURL: String
    let wireAPI: String
    let bearerToken: String
}

enum ConfigError: LocalizedError {
    case notFound(String)
    var errorDescription: String? {
        switch self {
        case .notFound(let m): return m
        }
    }
}

/// Surgical editor for `~/.codex/config.toml`. It only touches a small, known
/// set of top-level keys plus the managed `[model_providers.*]` section, and
/// leaves everything else (MCP servers, plugins, project trust, etc.) intact.
enum ConfigManager {

    static let codexHome: String = {
        if let h = ProcessInfo.processInfo.environment["CODEX_HOME"], !h.isEmpty {
            return h
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex").path
    }()

    static var configPath: String {
        (codexHome as NSString).appendingPathComponent("config.toml")
    }

    static var modelsPath: String {
        (codexHome as NSString).appendingPathComponent("models.json")
    }

    /// Top-level keys the switcher manages.
    static let managedKeys: [String] = [
        "model",
        "model_reasoning_effort",
        "web_search",
        "service_tier",
        "model_provider",
        "preferred_auth_method",
        "forced_login_method",
        "model_catalog_json",
    ]

    static func isSectionHeader(_ trimmed: String) -> Bool {
        trimmed.hasPrefix("[") && trimmed.hasSuffix("]") && trimmed.count >= 2
    }

    static func sectionName(_ trimmedHeader: String) -> String {
        var s = String(trimmedHeader.dropFirst().dropLast())
        s = s.replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
        return s.trimmingCharacters(in: .whitespaces)
    }

    static func stripQuotes(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.count >= 2 {
            let f = t.first!, l = t.last!
            if (f == "\"" && l == "\"") || (f == "'" && l == "'") {
                t = String(t.dropFirst().dropLast())
            }
        }
        return t
    }

    /// Parse a simple `key = value` line (top-level keys only, in practice).
    static func parseKeyValue(_ line: String) -> (key: String, value: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("#") { return nil }
        guard let eq = trimmed.firstIndex(of: "=") else { return nil }
        var key = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
        let value = String(trimmed[trimmed.index(after: eq)...])
            .trimmingCharacters(in: .whitespaces)
        if key.count >= 2 {
            let f = key.first!, l = key.last!
            if (f == "\"" && l == "\"") || (f == "'" && l == "'") {
                key = String(key.dropFirst().dropLast())
            }
        }
        return (key, value)
    }

    static func readFile(_ path: String) throws -> String {
        if FileManager.default.fileExists(atPath: path) {
            return try String(contentsOfFile: path, encoding: .utf8)
        }
        return ""
    }

    /// Atomically write content, preserving 0600 permissions.
    static func atomicWrite(_ content: String, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = dir.appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        try content.write(to: tmp, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmp.path)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: url)
        }
    }

    /// Returns the active third-party provider id (e.g. "deepseek"), or nil
    /// when no custom provider is configured.
    static func detectProviderId(_ content: String) -> String? {
        var inLeading = true
        for line in content.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if isSectionHeader(t) {
                inLeading = false
                let name = sectionName(t)
                if name.hasPrefix("model_providers.") {
                    let rest = String(name.dropFirst("model_providers.".count))
                    let id = rest.components(separatedBy: ".").first ?? rest
                    if !id.isEmpty { return id }
                }
                continue
            }
            if inLeading, let (k, v) = parseKeyValue(line), k == "model_provider" {
                let id = stripQuotes(v)
                if !id.isEmpty { return id }
            }
        }
        return nil
    }

    /// Rewrite the config: apply top-level `settings`, drop the section for
    /// `removeProviderId` (if any), and optionally append a provider block.
    static func applySettings(
        to content: String,
        settings: [KeySetting],
        removeProviderId: String?,
        addBlock: ProviderBlock?
    ) throws -> (String, [String]) {
        var changes: [String] = []
        let lines = content.components(separatedBy: "\n")

        // Leading area = everything before the first section header.
        var firstSection = lines.count
        for (i, line) in lines.enumerated() {
            if isSectionHeader(line.trimmingCharacters(in: .whitespaces)) {
                firstSection = i
                break
            }
        }
        let leading = Array(lines[0..<firstSection])
        let body = Array(lines[firstSection...])

        let setValues: [String: String] = Dictionary(uniqueKeysWithValues: settings.compactMap { s in
            s.value.map { (s.key, $0) }
        })
        let removeKeys = Set(settings.filter { $0.value == nil }.map { $0.key })

        var outLeading: [String] = []
        var handled = Set<String>()

        for line in leading {
            if let (k, v) = parseKeyValue(line),
               ConfigManager.managedKeys.contains(k),
               setValues[k] != nil || removeKeys.contains(k) {
                handled.insert(k)
                if let newVal = setValues[k] {
                    if newVal != v {
                        changes.append("set \(k) = \(newVal)")
                    }
                    outLeading.append("\(k) = \(newVal)")
                } else {
                    changes.append("removed \(k)")
                }
                continue
            }
            outLeading.append(line)
        }

        for s in settings {
            if handled.contains(s.key) { continue }
            if let v = s.value {
                changes.append("added \(s.key) = \(v)")
                outLeading.append("\(s.key) = \(v)")
            }
        }

        var outBody: [String] = []
        var dropping = false
        for line in body {
            let t = line.trimmingCharacters(in: .whitespaces)
            if isSectionHeader(t) {
                let name = sectionName(t)
                if let rid = removeProviderId,
                   name == "model_providers.\(rid)" || name.hasPrefix("model_providers.\(rid).") {
                    dropping = true
                    changes.append("removed [\(name)]")
                    continue
                }
                dropping = false
            }
            if !dropping { outBody.append(line) }
        }

        var result = outLeading
        if !outBody.isEmpty, result.last?.isEmpty == false {
            result.append("")
        }
        result.append(contentsOf: outBody)

        if let block = addBlock {
            if result.last?.isEmpty == false { result.append("") }
            result.append("[model_providers.\(block.id)]")
            result.append("name = \"\(block.id)\"")
            result.append("base_url = \"\(block.baseURL)\"")
            result.append("wire_api = \"\(block.wireAPI)\"")
            result.append("experimental_bearer_token = \"\(block.bearerToken)\"")
            changes.append("added [model_providers.\(block.id)]")
        }

        var text = result.joined(separator: "\n")
        if !text.hasSuffix("\n") { text += "\n" }
        return (text, changes)
    }
}
