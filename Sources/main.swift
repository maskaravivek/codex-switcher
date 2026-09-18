import Foundation

func providerForArg(_ s: String) -> ProviderDef? {
    switch s.lowercased() {
    case "chatgpt", "gpt", "openai":
        return Providers.chatgpt
    case "deepseek", "deepseek-flash", "flash":
        return Providers.deepseekFlash
    case "deepseek-pro", "deepseek-v4-pro", "pro":
        return Providers.deepseekPro
    default:
        return nil
    }
}

func printHelp() {
    print("""
    codex-switcher — switch Codex between ChatGPT and third-party providers

    usage:
      codex-switcher status
      codex-switcher switch <chatgpt|deepseek|deepseek-pro> [--restart]
      codex-switcher key <account>       read an sk-… key from stdin
      codex-switcher restart             quit + relaunch the ChatGPT app
      codex-switcher where               print the paths it manages
    """)
}

let args = Array(CommandLine.arguments.dropFirst())
let cmd = args.first ?? "help"

switch cmd {
case "status":
    let s = (try? SwitcherCore.status()) ?? (nil, nil)
    print("provider: \(s.0 ?? "chatgpt")")
    print("model: \(s.1 ?? "(unset)")")
    print("deepseek key: \(KeychainStore.get(account: "deepseek") != nil ? "stored" : "missing")")

case "switch":
    guard args.count > 1, let p = providerForArg(args[1]) else {
        print("error: specify a provider: chatgpt | deepseek | deepseek-pro")
        exit(1)
    }
    let restart = args.contains("--restart")
    do {
        let result = p.isChatGPT
            ? try SwitcherCore.switchToChatGPT()
            : try SwitcherCore.switchToProvider(p)
        for c in result.changes { print("  • \(c)") }
        print("active: \(result.activeId)")
        if restart {
            SwitcherCore.restartChatGPT()
            print("ChatGPT restarted")
        } else {
            print("note: fully quit and reopen ChatGPT (⌘Q) for the change to take effect")
        }
    } catch {
        print("error: \(error.localizedDescription)")
        exit(1)
    }

case "key":
    let account = args.count > 1 ? args[1] : "deepseek"
    var key = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"] ?? ""
    if key.isEmpty { key = readLine() ?? "" }
    key = key.trimmingCharacters(in: .whitespacesAndNewlines)
    guard key.hasPrefix("sk-") else {
        print("error: key must start with sk-")
        exit(1)
    }
    do {
        try KeychainStore.set(key, account: account)
        print("saved key for \(account)")
    } catch {
        print("error: \(error.localizedDescription)")
        exit(1)
    }

case "restart":
    SwitcherCore.restartChatGPT()
    print("ChatGPT restarted")

case "where":
    print("config: \(ConfigManager.configPath)")
    print("models: \(ConfigManager.modelsPath)")
    print("state:  \(StateStore.fileURL().path)")

default:
    printHelp()
}
