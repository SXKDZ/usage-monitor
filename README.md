# Usage Monitor

A minimal macOS menu bar app and set of desktop widgets that show how much of your
**Claude Code**, **Codex** and **Gemini (Antigravity)** subscription limits you've used —
5-hour and weekly windows, when each one resets, any limit resets you can redeem, and your Gemini AI credit balance.

It reuses the sign-ins those CLIs already keep on your Mac. There's no account to set up
and no API key to paste.

## Features

- **Menu bar**: the highest usage across all your limits at a glance; click for a card per tool
  with the signed-in account, plan, every limit (% used, a bar, and a reset countdown).
- **Desktop widgets** (right-click the desktop → *Edit Widgets…* → search "Usage"):
  - *AI Usage*: all three tools in one widget (small, medium, large)
  - *Claude Code Usage*, *Codex Usage*, *Gemini Usage*: one block per tool (small, medium)
- **Resets** you can redeem for Codex and Claude Code, and the **AI credit** balance for Gemini.
- Bars turn orange at 75% used and red at 90%.
- Refreshes every 5 minutes; keeps showing the last good numbers if a fetch fails.

## Where the data comes from

| Tool | Sign-in it reads | Usage source |
| --- | --- | --- |
| Claude Code | Keychain item `Claude Code-credentials` (or `~/.claude/.credentials.json`), account from `~/.claude.json` | `api.anthropic.com/api/oauth/usage` |
| Codex | `~/.codex/auth.json` | `chatgpt.com/backend-api/wham/usage` |
| Gemini | Antigravity CLI (`agy`) login in the Keychain item `gemini` | `daily-cloudcode-pa.googleapis.com` quota summary |

Credentials are **read only and never written back**, so the app can't interfere with the CLIs'
own logins. Google access tokens are refreshed in memory using the OAuth client that ships inside
your installed `agy` binary. Claude Code and Codex tokens are never refreshed by this app: if one
has expired, open that CLI once and it renews itself.

These are the same undocumented endpoints the CLIs use for their own usage screens, so a CLI
update can change them. Some of them only answer requests that identify as the CLI itself; the
client versions this app sends are in `Sources/UsageMonitor/Providers/`.

## Build and install

Requirements: macOS 15+, Xcode 16+ (or the matching Swift toolchain), and a code-signing
identity (*Developer ID Application* or *Apple Development*). WidgetKit won't load ad hoc–signed
widgets.

```sh
./build.sh            # builds "build/Usage Monitor.app"
./build.sh --install  # also copies it to /Applications and launches it
```

The build script picks your first signing identity and derives the shared app group
(`<TEAM_ID>.dev.usagemonitor.app`) that passes data from the menu bar app to the widgets.
Turn on **Launch at Login** from the ⋯ menu so the widgets stay current.

To debug a provider, print what it fetched:

```sh
"build/Usage Monitor.app/Contents/MacOS/UsageMonitor" --dump
```

## Layout

```
Sources/
  UsageKit/       shared models, snapshot file, and SwiftUI components
  UsageMonitor/   menu bar app and the three providers
  UsageWidget/    WidgetKit extension
build.sh          builds, signs, and bundles the app and widget
```
