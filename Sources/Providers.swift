import Foundation

/// A provider that Codex can switch to. `providerId` is the TOML table id
/// (`[model_providers.<providerId>]`), `switcherKey` is our stable identifier.
struct ProviderDef: Identifiable, Hashable {
    var id: String { switcherKey }
    let switcherKey: String
    let displayName: String
    let providerId: String
    let model: String
    let baseURL: String
    let wireAPI: String
    let keychainAccount: String
    let needsCatalog: Bool
    let catalogAsset: String?
    let isChatGPT: Bool
}

enum Providers {
    static let chatgpt = ProviderDef(
        switcherKey: "chatgpt",
        displayName: "ChatGPT (OpenAI)",
        providerId: "",
        model: "",
        baseURL: "",
        wireAPI: "",
        keychainAccount: "",
        needsCatalog: false,
        catalogAsset: nil,
        isChatGPT: true
    )

    static let deepseekFlash = ProviderDef(
        switcherKey: "deepseek-flash",
        displayName: "DeepSeek · Flash",
        providerId: "deepseek",
        model: "deepseek-flash",
        baseURL: "https://api.deepseek.com/",
        wireAPI: "responses",
        keychainAccount: "deepseek",
        needsCatalog: true,
        catalogAsset: "deepseek-models.json",
        isChatGPT: false
    )

    static let deepseekPro = ProviderDef(
        switcherKey: "deepseek-v4-pro",
        displayName: "DeepSeek · V4 Pro",
        providerId: "deepseek",
        model: "deepseek-v4-pro",
        baseURL: "https://api.deepseek.com/",
        wireAPI: "responses",
        keychainAccount: "deepseek",
        needsCatalog: true,
        catalogAsset: "deepseek-models.json",
        isChatGPT: false
    )

    static let all: [ProviderDef] = [chatgpt, deepseekFlash, deepseekPro]

    static func byKey(_ key: String) -> ProviderDef? {
        all.first { $0.switcherKey == key }
    }
}
