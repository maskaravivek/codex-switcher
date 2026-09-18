# CodexSwitcher

A tiny, native macOS menu bar app that switches the ChatGPT Codex desktop app
between your OpenAI (ChatGPT) account and third-party providers (DeepSeek today,
others easy to add) with one click.

No third-party dependencies. Swift + SwiftUI only. API keys live in your macOS
Keychain and are never written to `config.toml`, logs, or state files.

## What it does

- Menu bar dropdown: **ChatGPT** / **DeepSeek · Flash** / **DeepSeek · V4 Pro**.
- One click switches `~/.codex/config.toml` surgically — it only touches a small
  set of model/auth keys and the `[model_providers.deepseek]` section, leaving
  your MCP servers, plugins, project trust levels, etc. untouched.
- Switching to a provider writes `~/.codex/models.json` (the DeepSeek catalog).
- Switching back restores your exact previous values (`model`, `service_tier`,
  `model_reasoning_effort`, …) and removes the provider section.
- Every switch backs up `config.toml` to `~/.codex/CodexSwitcher/backups/`
  (keeps the last 20).
- Optionally auto-restarts the ChatGPT app so the change takes effect.

## Build

```bash
cd ~/CodexSwitcher
./build.sh
```

Produces:

- `build/CodexSwitcher.app` — the menu bar app
- `build/codex-switcher` — a CLI with the same logic

## Use

Menu bar app:

1. `open build/CodexSwitcher.app`
2. Click **Set DeepSeek API Key…** and paste your `sk-…` key.
3. Click a provider to switch.

CLI:

```bash
build/codex-switcher status
build/codex-switcher switch deepseek        # or deepseek-pro
build/codex-switcher switch chatgpt
build/codex-switcher switch deepseek --restart
echo sk-… | build/codex-switcher key deepseek
build/codex-switcher restart
```

After a switch without `--restart` (or with auto-restart off), fully quit the
ChatGPT app with ⌘Q and reopen it. Codex CLI picks up the change on its next
launch.

## Notes / caveats

- Codex keeps session history in two groups (ChatGPT-subscription vs API-key).
  Switching providers shows one group at a time; nothing is deleted.
- With a third-party provider, built-in web search is disabled
  (`web_search = "disabled"`), and some OpenAI-only features (memories/goals)
  may be ignored by the remote model.
- On first quit/relaunch, macOS may ask you to allow CodexSwitcher to control
  ChatGPT. That's the Apple Events permission for the restart step.

## Adding a provider

Add an entry to `Providers.all` in `Sources/Providers.swift` (base_url,
wire_api, model slug, keychain account, optional models.json asset) and it
shows up in the menu automatically. Providers must speak the OpenAI
**Responses API** (`wire_api = "responses"`); chat-completions-only endpoints
will not start in recent Codex versions.
