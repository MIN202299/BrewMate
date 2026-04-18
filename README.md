# BrewMate

一款 macOS 原生 SwiftUI 桌面应用，用于可视化管理 [Homebrew](https://brew.sh) 安装的 formulae 与 casks。

零第三方依赖，零构建工具链 —— 只依赖 Apple 内置框架（SwiftUI、Foundation、Observation）和 Homebrew 本身。

![preview](https://img.shields.io/badge/macOS-14%2B-blue?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange?logo=swift)
![License](https://img.shields.io/badge/License-MIT-green)

## 功能

| 功能 | 说明 |
|---|---|
| **已安装** | 列出所有 formulae 与 casks，按名称过滤，按类型筛选 |
| **过期** | 仅展示可升级的包，单个或批量一键升级 |
| **搜索** | 实时搜索 Homebrew 仓库，Formula / Cask / 全部切换 |
| **实时日志** | 所有操作（install / uninstall / upgrade）以流式方式输出，可多任务并行 |
| **密码交互** | 需要 sudo 的操作（如部分 cask 卸载）会弹出系统密码对话框 |
| **自动刷新** | 操作完成后自动刷新列表，无需手动干预 |
| **操作防重** | 正在运行或已成功的任务不会重复触发 |

## 截图

| 已安装 | 过期 |
|---|---|
| 列表展示已装包的名称、类型、版本、描述，过期项红色高亮 | 展示可升级的包及版本对比，支持单个升级和全部升级 |
| 搜索 | 日志 |
| 关键字实时搜索，支持 formula/cask 过滤，一键安装 | 所有命令的实时流式输出，多任务并行，密码自动弹出 |

## 要求

- **macOS 14 或更新**
- **Homebrew**（`/opt/homebrew/bin/brew` 或 `/usr/local/bin/brew`）
- **Swift 5.9+**（来自 Xcode 或 Command Line Tools）

## 快速开始

### 从源码构建

```bash
git clone https://github.com/YOUR_USERNAME/BrewMate.git
cd BrewMate
bash build.sh
open BrewMate.app
```

构建完成后会产出 `BrewMate.app`，可拖入 `/Applications` 使用。

### 开发期运行

```bash
swift run
```

### 重新生成图标（可选）

```bash
swift tools/make_icon.swift
iconutil -c icns assets/BrewMate.iconset -o assets/BrewMate.icns
```

## 架构

```
Sources/BrewMate/
├── BrewMateApp.swift          # @main App，窗口与菜单栏
├── AppModel.swift             # @Observable 根状态 + Job 生命周期管理
├── BrewService.swift          # actor，封装 brew 子进程（PTY 流式 + JSON 解析）
├── PTYRunner.swift            # openpty + posix_spawn，提供 sudo 密码交互能力
├── Models.swift               # Package / OutdatedItem / SearchResult / JobLog
├── Views/
│   ├── ContentView.swift       # NavigationSplitView 骨架 + 工具栏
│   ├── InstalledView.swift     # 已安装列表
│   ├── OutdatedView.swift      # 过期包列表
│   ├── SearchView.swift        # 搜索 + 安装
│   └── JobLogView.swift        # 底部日志面板（多任务标签 + 自动滚动）
└── Resources/
    └── Info.plist              # Bundle 元数据
```

### 技术要点

- **PTY 子进程**：使用 `openpty` + `posix_spawn` 给 brew 分配伪终端，使 `sudo` 能正常读密码；日志按行拆分并实时推送
- **并发搜索**：`async let` 并行调用 formula / cask 搜索（`brew search` 非 TTY 不输出章节头），合并结果
- **操作幂等**：同名任务正在运行或已成功时拒绝重复触发；失败的任务允许重试
- **无沙盒**：为了 spawn 子进程调用 `brew`，应用未启用 App Sandbox

## 已知限制

- 部分 cask 在安装/卸载时需要 `sudo`，当前通过 `NSAlert` + `NSSecureTextField` 弹密码对话框；若连续输错 3 次则终止任务
- 应用使用 ad-hoc 签名（本机自用），首次运行 Gatekeeper 可能弹窗，右键 → 打开 即可
- 所有数据直接来自 `brew` 本身（只读 JSON），应用不维护任何本地持久化状态

## 许可证

MIT
