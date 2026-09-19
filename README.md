# CodexSwitcher

A tiny native macOS menu bar app that switches the ChatGPT Codex app between
your OpenAI account and DeepSeek (Flash / V4 Pro) with one click.

## Demo

https://github.com/user-attachments/assets/6bf1cfd0-ade7-4374-b4fc-43f119a3e75e

## Features

- Menu bar dropdown: **ChatGPT** / **DeepSeek · Flash** / **DeepSeek · V4 Pro**
- API keys stored in **macOS Keychain** — never written to `config.toml`
- Surgical config editing: preserves your MCP servers, plugins, and project trust
- Auto-restarts ChatGPT after a switch; backs up `config.toml` before every change
- Includes a CLI with the same logic (`codex-switcher`)

## Install

Download `CodexSwitcher-0.1.0-macOS.zip` from
[Releases](https://github.com/mangoappstudio/codex-switcher/releases), unzip,
move to `/Applications`, and open.

The app is self-signed (not notarized), so on first launch right-click it and choose **Open**.

## Use

1. Open the app and click its menu bar icon.
2. Click **Set DeepSeek API Key…** and paste your `sk-…` key.
3. Click a provider to switch.

```bash
# CLI
codex-switcher status
codex-switcher switch deepseek        # or: deepseek-pro / chatgpt
codex-switcher switch deepseek --restart
echo sk-… | codex-switcher key deepseek
codex-switcher restart
```

## Build from source

```bash
./scripts/setup-signing.sh   # once: stable code-signing identity so Keychain keys survive rebuilds
./build.sh
```

## Adding a provider

Add an entry to `Providers.all` in `Sources/Providers.swift`, then rebuild.
Providers must speak the OpenAI **Responses API** (`wire_api = "responses"`).

## License

[MIT](LICENSE)
