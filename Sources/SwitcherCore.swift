import Foundation
import AppKit

struct SwitchResult {
    let activeId: String
    let changes: [String]
    let chatgptRestored: Bool
}

enum SwitchError: LocalizedError {
    case missingKey(String)
    case noSnapshot
    case catalog(String)

    var errorDescription: String? {
        switch self {
        case .missingKey(let name):
            return "No API key stored for \(name). Set it in the menu (Set DeepSeek API Key…) or run: echo sk-… | codex-switcher key deepseek"
        case .noSnapshot:
            return "No saved ChatGPT configuration to restore. Open Codex, pick your normal model, then switch away once to capture it."
        case .catalog(let m):
            return m
        }
    }
}

enum SwitcherCore {

    // MARK: - reading

    static func loadConfig() throws -> String {
        try ConfigManager.readFile(ConfigManager.configPath)
    }

    static func status() throws -> (providerId: String?, model: String?) {
        let c = try loadConfig()
        return (ConfigManager.detectProviderId(c), topLevelValue(c, key: "model"))
    }

    static func detectSwitcherKey() -> String {
        guard let c = try? loadConfig() else { return StateStore.load().activeSwitcherKey }
        guard let id = ConfigManager.detectProviderId(c) else { return "chatgpt" }
        let model = topLevelValue(c, key: "model") ?? ""
        if id == "deepseek" {
            return model.contains("pro") ? "deepseek-v4-pro" : "deepseek-flash"
        }
        return id
    }

    static func topLevelValue(_ content: String, key: String) -> String? {
        for line in content.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if ConfigManager.isSectionHeader(t) { break }
            if let (k, v) = ConfigManager.parseKeyValue(line), k == key {
                return ConfigManager.stripQuotes(v)
            }
        }
        return nil
    }

    static func captureSnapshot(_ content: String) -> ChatGPTSnapshot {
        var present: [String: String] = [:]
        var seen = Set<String>()
        for line in content.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if ConfigManager.isSectionHeader(t) { break }
            if let (k, v) = ConfigManager.parseKeyValue(line),
               ConfigManager.managedKeys.contains(k) {
                present[k] = v
                seen.insert(k)
            }
        }
        return ChatGPTSnapshot(
            present: present,
            absent: ConfigManager.managedKeys.filter { !seen.contains($0) }
        )
    }

    static func catalogValue() -> String {
        if ProcessInfo.processInfo.environment["CODEX_HOME"] != nil {
            return ConfigManager.modelsPath
        }
        return "~/.codex/models.json"
    }

    // MARK: - switching

    static func switchToProvider(_ p: ProviderDef) throws -> SwitchResult {
        let content = try loadConfig()
        let currentId = ConfigManager.detectProviderId(content)

        var state = StateStore.load()
        if currentId == nil {
            // We're on ChatGPT now, so snapshot the values we'll need to restore.
            state.chatgptSnapshot = captureSnapshot(content)
        }

        guard let key = KeychainStore.get(account: p.keychainAccount), key.hasPrefix("sk-") else {
            throw SwitchError.missingKey(p.displayName)
        }

        let settings: [KeySetting] = [
            KeySetting(key: "model", value: "\"\(p.model)\""),
            KeySetting(key: "model_reasoning_effort", value: "\"high\""),
            KeySetting(key: "web_search", value: "\"disabled\""),
            KeySetting(key: "model_provider", value: "\"\(p.providerId)\""),
            KeySetting(key: "preferred_auth_method", value: "\"apikey\""),
            KeySetting(key: "forced_login_method", value: "\"api\""),
            KeySetting(key: "service_tier", value: nil),
            KeySetting(key: "model_catalog_json",
                      value: p.needsCatalog ? "\"\(catalogValue())\"" : nil),
        ]

        try backupConfig()
        let (newContent, changes) = try ConfigManager.applySettings(
            to: content,
            settings: settings,
            removeProviderId: p.providerId,
            addBlock: ProviderBlock(
                id: p.providerId,
                baseURL: p.baseURL,
                wireAPI: p.wireAPI,
                bearerToken: key
            )
        )
        try ConfigManager.atomicWrite(newContent, to: ConfigManager.configPath)

        if p.needsCatalog {
            try writeCatalog(asset: p.catalogAsset)
            state.createdModelsJson = true
        }

        state.activeSwitcherKey = p.switcherKey
        StateStore.save(state)
        return SwitchResult(activeId: p.displayName, changes: changes, chatgptRestored: false)
    }

    static func switchToChatGPT() throws -> SwitchResult {
        let content = try loadConfig()
        let currentId = ConfigManager.detectProviderId(content)
        var state = StateStore.load()

        var snapshot = state.chatgptSnapshot
        if !snapshot.hasContent {
            // Fallback for people who installed DeepSeek via the official script.
            snapshot = deriveChatGPTSnapshot()
        }
        guard snapshot.hasContent else {
            throw SwitchError.noSnapshot
        }

        try backupConfig()
        var settings: [KeySetting] = []
        for k in ConfigManager.managedKeys {
            settings.append(KeySetting(key: k, value: snapshot.present[k]))
        }
        let (newContent, changes) = try ConfigManager.applySettings(
            to: content,
            settings: settings,
            removeProviderId: currentId,
            addBlock: nil
        )
        try ConfigManager.atomicWrite(newContent, to: ConfigManager.configPath)

        if state.createdModelsJson {
            try? FileManager.default.removeItem(atPath: ConfigManager.modelsPath)
            state.createdModelsJson = false
        }

        state.activeSwitcherKey = "chatgpt"
        StateStore.save(state)
        return SwitchResult(activeId: "ChatGPT (OpenAI)", changes: changes, chatgptRestored: true)
    }

    static func deriveChatGPTSnapshot() -> ChatGPTSnapshot {
        let backup = (ConfigManager.codexHome as NSString)
            .appendingPathComponent("backup-deepseek/config.toml")
        if FileManager.default.fileExists(atPath: backup),
           let c = try? String(contentsOfFile: backup, encoding: .utf8) {
            return captureSnapshot(c)
        }
        return ChatGPTSnapshot(present: [:], absent: ConfigManager.managedKeys)
    }

    static func writeCatalog(asset: String?) throws {
        guard let asset = asset else { return }
        let ns = asset as NSString
        let content: String

        if let url = Bundle.main.url(forResource: ns.deletingPathExtension,
                                     withExtension: ns.pathExtension),
           let c = try? String(contentsOf: url, encoding: .utf8) {
            content = c
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let dev = (home as NSString).appendingPathComponent("CodexSwitcher/Assets/\(asset)")
            if FileManager.default.fileExists(atPath: dev),
               let c = try? String(contentsOfFile: dev, encoding: .utf8) {
                content = c
            } else if let env = ProcessInfo.processInfo.environment["CODEX_SWITCHER_ASSETS"] {
                let p = (env as NSString).appendingPathComponent(asset)
                if FileManager.default.fileExists(atPath: p),
                   let c = try? String(contentsOfFile: p, encoding: .utf8) {
                    content = c
                } else {
                    throw SwitchError.catalog("Catalog asset not found: \(asset)")
                }
            } else {
                throw SwitchError.catalog("Catalog asset not found: \(asset)")
            }
        }
        try ConfigManager.atomicWrite(content, to: ConfigManager.modelsPath)
    }

    // MARK: - backups

    static func backupConfig() throws {
        let dir = StateStore.dir().appendingPathComponent("backups")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let stamp = formatter.string(from: Date()) + "-" + UUID().uuidString.prefix(6)
        let dest = dir.appendingPathComponent("config.toml.\(stamp)")

        if FileManager.default.fileExists(atPath: ConfigManager.configPath) {
            try FileManager.default.copyItem(atPath: ConfigManager.configPath, toPath: dest.path)
        }

        // Keep the most recent 20 backups.
        let backups = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [])) ?? []
        let ours = backups.filter { $0.lastPathComponent.hasPrefix("config.toml.") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        if ours.count > 20 {
            for f in ours.prefix(ours.count - 20) {
                try? FileManager.default.removeItem(at: f)
            }
        }
    }

    // MARK: - restart ChatGPT

    static func restartChatGPT() {
        let bundleId = "com.openai.codex"
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        if apps.isEmpty {
            _ = runProcess("/usr/bin/open", ["-b", bundleId])
            return
        }
        for app in apps { app.terminate() }

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty {
                break
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleId) {
            app.forceTerminate()
        }
        Thread.sleep(forTimeInterval: 0.8)
        _ = runProcess("/usr/bin/open", ["-b", bundleId])
    }

    @discardableResult
    static func runProcess(_ path: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try? p.run()
        p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }
}
