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
| **Password Prompts** | Native dialog for `sudo`-required operations (e.g. certain cask uninstalls) |
| **Auto-Refresh** | Package lists refresh automatically after every operation |
| **Deduplication** | Prevents duplicate task triggers; failed tasks can be retried |

## Screenshots

| Installed | Outdated |
|---|---|
| List installed packages with name, type, version, and description; outdated items highlighted in red | Shows upgradable packages with version comparison; supports individual and batch upgrade |
| Search | Logs |
| Real-time keyword search with formula/cask filtering and one-click install | Real-time streaming output for all commands, multi-task support, password auto-prompt |

## Requirements

- **macOS 14 or later**
- **Homebrew** installed (at `/opt/homebrew/bin/brew` or `/usr/local/bin/brew`)
- **Swift 5.9+** (from Xcode or Command Line Tools)

## Quick Start

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

### Regenerate Icon (optional)

```bash
swift tools/make_icon.swift
iconutil -c icns assets/BrewMate.iconset -o assets/BrewMate.icns
```

## Architecture

```
Sources/BrewMate/
├── BrewMateApp.swift          # @main App, window & menu bar
├── AppModel.swift             # @Observable root state + Job lifecycle
├── BrewService.swift          # actor: brew subprocess (PTY streaming + JSON parsing)
├── PTYRunner.swift            # openpty + posix_spawn for sudo password interaction
├── Models.swift               # Package / OutdatedItem / SearchResult / JobLog
├── Views/
│   ├── ContentView.swift       # NavigationSplitView scaffold + toolbar
│   ├── InstalledView.swift     # Installed packages list
│   ├── OutdatedView.swift      # Outdated packages list
│   ├── SearchView.swift        # Search + install
│   └── JobLogView.swift        # Bottom log panel (multi-task tabs + auto-scroll)
└── Resources/
    └── Info.plist              # Bundle metadata
```

### Technical Highlights

- **PTY Subprocess**: Uses `openpty` + `posix_spawn` to allocate a pseudo-terminal for brew, enabling `sudo` to read passwords; output is split by line and streamed in real-time
- **Concurrent Search**: Uses `async let` to run formula and cask searches in parallel (`brew search` produces no section headers in non-TTY mode), then merges results
- **Idempotent Operations**: Running or succeeded tasks prevent duplicate triggers; failed tasks allow retry
- **No Sandbox**: App is unsandboxed to enable subprocess spawning for `brew`

## Known Limitations

- Some cask install/uninstall operations require `sudo`. Currently handled via `NSAlert` + `NSSecureTextField` password dialog; task terminates after 3 failed attempts
- The app uses ad-hoc code signing (for local use). First launch may trigger Gatekeeper — right-click → Open to bypass
- All data comes directly from `brew` itself (read-only JSON); the app maintains no local persistent state

## License

MIT
