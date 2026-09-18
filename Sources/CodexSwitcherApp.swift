import SwiftUI
import AppKit

@main
struct CodexSwitcherApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent().environmentObject(model)
        } label: {
            Image(nsImage: AppModel.menuBarIcon)
                .help(model.activeLabel)
        }
        .menuBarExtraStyle(.menu)
    }
}

enum AutoRestart {
    private static let key = "autoRestartChatGPT"
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

final class AppModel: ObservableObject {
    @Published var activeKey: String = "chatgpt"
    @Published var lastMessage: String = ""

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        refresh()
    }

    var activeLabel: String {
        switch activeKey {
        case "deepseek-flash": return "Codex: DeepSeek Flash"
        case "deepseek-v4-pro": return "Codex: DeepSeek Pro"
        default: return "Codex: ChatGPT"
        }
    }

    /// Fixed template icon for the menu bar (renders black/white to match the
    /// menu bar's appearance). Loaded from the app bundle with an SF Symbol
    /// fallback for bare-binary runs.
    static let menuBarIcon: NSImage = {
        let img: NSImage
        if let url = Bundle.main.url(forResource: "menu-bar-icon", withExtension: "png"),
           let loaded = NSImage(contentsOf: url) {
            img = loaded
        } else {
            img = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "CodexSwitcher") ?? NSImage()
        }
        img.isTemplate = true
        img.size = NSSize(width: 18, height: 18)
        return img
    }()

    func refresh() {
        let detected = SwitcherCore.detectSwitcherKey()
        let stored = StateStore.load().activeSwitcherKey
        activeKey = (stored != "chatgpt") ? stored : detected
    }

    func switchTo(_ p: ProviderDef) {
        if !p.isChatGPT && KeychainStore.get(account: p.keychainAccount) == nil {
            promptForKey(p) { [weak self] in self?.switchTo(p) }
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result: SwitchResult
                if p.isChatGPT {
                    result = try SwitcherCore.switchToChatGPT()
                } else {
                    result = try SwitcherCore.switchToProvider(p)
                }
                DispatchQueue.main.async {
                    self.activeKey = p.switcherKey
                    self.lastMessage = "Switched to \(result.activeId)"
                }
                if AutoRestart.enabled {
                    SwitcherCore.restartChatGPT()
                }
            } catch {
                DispatchQueue.main.async {
                    self.lastMessage = error.localizedDescription
                }
            }
        }
    }

    func promptForKey(_ p: ProviderDef, onSave: (() -> Void)? = nil) {
        let alert = NSAlert()
        alert.messageText = "\(p.displayName) API Key"
        alert.informativeText = "Stored in your macOS Keychain only — never written to config.toml."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "sk-…"
        if let existing = KeychainStore.get(account: p.keychainAccount) {
            field.stringValue = existing
        }
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)

        if alert.runModal() == .alertFirstButtonReturn {
            let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if key.hasPrefix("sk-") {
                try? KeychainStore.set(key, account: p.keychainAccount)
                lastMessage = "API key saved for \(p.displayName)"
                onSave?()
            } else {
                lastMessage = "Key must start with sk-"
            }
        }
    }
}

struct MenuContent: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ForEach(Providers.all) { p in
            Button {
                model.switchTo(p)
            } label: {
                HStack {
                    Image(systemName: model.activeKey == p.switcherKey ? "checkmark" : "circle")
                        .frame(width: 16)
                    Text(p.displayName)
                }
            }
        }

        Divider()

        Toggle("Auto-restart ChatGPT after switch", isOn: Binding(
            get: { AutoRestart.enabled },
            set: { AutoRestart.enabled = $0 }
        ))

        Button("Set DeepSeek API Key…") {
            model.promptForKey(Providers.deepseekFlash)
        }

        Divider()

        if !model.lastMessage.isEmpty {
            Text(model.lastMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 230, alignment: .leading)
                .lineLimit(4)
        }

        Button("Quit CodexSwitcher") {
            NSApp.terminate(nil)
        }
    }
}
