# BrewMate

A lightweight native macOS app for managing [Homebrew](https://brew.sh) formulae and casks.

Zero third-party dependencies — built entirely with Apple frameworks (SwiftUI, Foundation, Observation).

![macOS](https://img.shields.io/badge/macOS-14%2B-blue?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange?logo=swift)
![License](https://img.shields.io/badge/License-MIT-green)

## Features

| Feature | Description |
|---|---|
| **Installed** | Browse all installed formulae and casks, filter by name and type |
| **Outdated** | See upgradable packages at a glance; upgrade individually or all at once |
| **Search** | Real-time search across the Homebrew repository with formula/cask/all filters |
| **Live Logs** | Stream output from `install` / `uninstall` / `upgrade` commands in real-time |
| **Native Auth** | Uses macOS system authorization dialog (with Touch ID support) for privileged operations |
| **Proxy Support** | Configure HTTP/HTTPS and SOCKS5 proxy for Homebrew downloads, with one-click connectivity test |
| **Auto-Refresh** | Package lists refresh automatically after every operation |

## Screenshots

| Installed | Outdated |
|---|---|
| List installed packages with name, type, version, and description; outdated items highlighted in green | Shows upgradable packages with version comparison; supports individual and batch upgrade |
| Search | Logs |
| Real-time keyword search with formula/cask filtering and one-click install | Real-time streaming output for all commands, multi-task support |

## Requirements

- **macOS 14 or later**
- **Homebrew** installed (at `/opt/homebrew/bin/brew` or `/usr/local/bin/brew`)
- **Swift 5.9+** (from Xcode or Command Line Tools, for building from source)

## Installation

### Homebrew (recommended)

```bash
brew tap MIN202299/brewmate
brew install --cask brewmate
```

> **Note:** BrewMate is not notarized. On first launch macOS Gatekeeper may block it.
> Run the following command once to allow it:
> ```bash
> xattr -dr com.apple.quarantine /Applications/BrewMate.app
> ```
> Or right-click the app icon and choose **Open**.

### Build from Source

```bash
git clone https://github.com/MIN202299/BrewMate.git
cd BrewMate
bash build.sh
open BrewMate.app
```

After building, drag `BrewMate.app` into `/Applications` or run directly.

### Development Mode

```bash
swift run
```

## Architecture

```
Sources/BrewMate/
├── BrewMateApp.swift          # @main App, window & menu bar
├── AppModel.swift             # @Observable root state + Job lifecycle
├── BrewService.swift          # actor: brew subprocess (osascript streaming + JSON parsing)
├── ProxySettings.swift        # @Observable proxy config, UserDefaults-backed
├── Models.swift               # Package / OutdatedItem / SearchResult / JobLog
├── Views/
│   ├── ContentView.swift       # NavigationSplitView scaffold + toolbar
│   ├── InstalledView.swift     # Installed packages list
│   ├── OutdatedView.swift      # Outdated packages list
│   ├── SearchView.swift        # Search + install
│   ├── SettingsView.swift      # Proxy settings sheet
│   └── JobLogView.swift        # Bottom log panel (multi-task tabs + auto-scroll)
└── Resources/
    └── Info.plist              # Bundle metadata
```

### Technical Highlights

- **Native Authorization**: Uses `osascript` with `do shell script ... with administrator privileges` to trigger the macOS system auth dialog (supports Touch ID). Brew is then run as the original user via `sudo -u <user>` to satisfy Homebrew's no-root requirement
- **Streaming Output**: Brew output is written to a temp file; a background thread polls it with `pread` at 50 ms intervals for real-time log display. ANSI escape codes are stripped automatically
- **Concurrent Search**: Uses `async let` to run formula and cask searches in parallel, then merges results
- **Proxy Support**: Injects `http_proxy`, `https_proxy`, and `all_proxy` env vars into the brew subprocess; settings persist via `UserDefaults`
- **No Sandbox**: App is unsandboxed to enable subprocess spawning for `brew`

## Known Limitations

- Privileged operations (certain cask installs/uninstalls) show the native macOS system authorization dialog. The OS handles credential caching; no passwords are stored by the app
- The app uses ad-hoc code signing (for local use). First launch may trigger Gatekeeper — right-click → Open to bypass
- All data comes directly from `brew` itself (read-only JSON); the app maintains no local persistent state

## License

MIT
