import Foundation

/// A snapshot of the ChatGPT (OpenAI) top-level config keys, captured before we
/// switch away so we can restore them exactly on the way back.
struct ChatGPTSnapshot: Codable {
    var present: [String: String] = [:]   // key -> raw TOML value (as it appeared)
    var absent: [String] = []             // managed keys that were not present

    var hasContent: Bool { !present.isEmpty }
}

struct AppState: Codable {
    var activeSwitcherKey: String = "chatgpt"
    var chatgptSnapshot: ChatGPTSnapshot = ChatGPTSnapshot()
    var createdModelsJson: Bool = false
}

enum StateStore {
    static func dir() -> URL {
        let codex = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
        return codex.appendingPathComponent("CodexSwitcher")
    }

    static func fileURL() -> URL {
        dir().appendingPathComponent("state.json")
    }

    static func load() -> AppState {
        guard let data = try? Data(contentsOf: fileURL()),
              let s = try? JSONDecoder().decode(AppState.self, from: data) else {
            return AppState()
        }
        return s
    }

    static func save(_ s: AppState) {
        try? FileManager.default.createDirectory(at: dir(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(s) {
            try? data.write(to: fileURL(), options: .atomic)
        }
    }
}
