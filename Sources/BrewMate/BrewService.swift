import Foundation

// MARK: - brew --json=v2 解码辅助结构

private struct InfoV2: Decodable {
    let formulae: [InfoFormula]
    let casks: [InfoCask]
}

private struct InfoFormula: Decodable {
    let name: String
    let full_name: String?
    let desc: String?
    let homepage: String?
    let versions: Versions
    let installed: [InstalledSpec]
    let outdated: Bool?
    let pinned: Bool?

    struct Versions: Decodable {
        let stable: String?
    }
    struct InstalledSpec: Decodable {
        let version: String
    }
}

private struct InfoCask: Decodable {
    let token: String
    let name: [String]?
    let desc: String?
    let homepage: String?
    let version: String?         // 最新版本
    let installed: String?       // 已装版本；nil 则未装
    let outdated: Bool?
}

private struct OutdatedV2: Decodable {
    let formulae: [OutdatedFormula]
    let casks: [OutdatedCask]
}

private struct OutdatedFormula: Decodable {
    let name: String
    let installed_versions: [String]
    let current_version: String
    let pinned: Bool
}

private struct OutdatedCask: Decodable {
    let name: String
    let installed_versions: [String]
    let current_version: String
}

// MARK: - Service

actor BrewService {
    static let shared = BrewService()

    let brewURL: URL
    private let decoder = JSONDecoder()

    init() {
        let candidates = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew"
        ]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            self.brewURL = URL(fileURLWithPath: found)
        } else {
            // 暂存占位；调用处会 throw brewNotFound
            self.brewURL = URL(fileURLWithPath: "/usr/bin/false")
        }
    }

    var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: brewURL.path)
    }

    // MARK: 只读：已安装

    func listInstalled() async throws -> [Package] {
        let data = try await runCapture(["info", "--json=v2", "--installed"])
        let info: InfoV2
        do {
            info = try decoder.decode(InfoV2.self, from: data)
        } catch {
            throw BrewError.decode(error.localizedDescription)
        }

        var result: [Package] = []
        for f in info.formulae {
            let installed = f.installed.first?.version
            result.append(Package(
                name: f.name,
                kind: .formula,
                installedVersion: installed,
                latestVersion: f.versions.stable,
                description: f.desc,
                homepage: f.homepage,
                isOutdated: f.outdated ?? false,
                isPinned: f.pinned ?? false
            ))
        }
        for c in info.casks {
            result.append(Package(
                name: c.token,
                kind: .cask,
                installedVersion: c.installed,
                latestVersion: c.version,
                description: c.desc ?? c.name?.first,
                homepage: c.homepage,
                isOutdated: c.outdated ?? false,
                isPinned: false
            ))
        }
        return result.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    // MARK: 只读：过期

    func outdated() async throws -> [OutdatedItem] {
        let data = try await runCapture(["outdated", "--json=v2", "--greedy"])
        let parsed: OutdatedV2
        do {
            parsed = try decoder.decode(OutdatedV2.self, from: data)
        } catch {
            throw BrewError.decode(error.localizedDescription)
        }
        var out: [OutdatedItem] = []
        for f in parsed.formulae {
            out.append(OutdatedItem(
                name: f.name,
                kind: .formula,
                installedVersion: f.installed_versions.joined(separator: ", "),
                latestVersion: f.current_version,
                isPinned: f.pinned
            ))
        }
        for c in parsed.casks {
            out.append(OutdatedItem(
                name: c.name,
                kind: .cask,
                installedVersion: c.installed_versions.joined(separator: ", "),
                latestVersion: c.current_version,
                isPinned: false
            ))
        }
        return out.sorted { $0.name < $1.name }
    }

    // MARK: 只读：搜索

    func search(_ query: String, kind: PackageKind?) async throws -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // brew search 在非 TTY 时不输出 ==> 标题，所以我们分开调用以确定 kind。
        switch kind {
        case .formula:
            return try await searchOneKind(trimmed, kind: .formula)
        case .cask:
            return try await searchOneKind(trimmed, kind: .cask)
        case .none:
            async let fs = searchOneKind(trimmed, kind: .formula)
            async let cs = searchOneKind(trimmed, kind: .cask)
            let (formulae, casks) = try await (fs, cs)
            return formulae + casks
        }
    }

    private func searchOneKind(_ query: String, kind: PackageKind) async throws -> [SearchResult] {
        var args = ["search"]
        args.append(kind == .formula ? "--formula" : "--cask")
        args.append(query)
        let data: Data
        do {
            data = try await runCapture(args)
        } catch BrewError.exit {
            // brew search 未匹配时退出码非 0，按空结果处理
            return []
        }
        let text = String(data: data, encoding: .utf8) ?? ""
        var results: [SearchResult] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("==>") { continue }
            if line.hasPrefix("If you meant") { continue }
            if line.contains(":") { continue }
            for token in line.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
                let clean = token.replacingOccurrences(of: "✓", with: "")
                    .trimmingCharacters(in: .whitespaces)
                guard !clean.isEmpty else { continue }
                results.append(SearchResult(name: clean, kind: kind))
            }
        }
        return results
    }

    // MARK: 写命令：osascript 流式（原生系统授权对话框）
    //
    // do shell script ... with administrator privileges 以 root 身份运行；
    // Homebrew 拒绝以 root 执行，因此内部再用 sudo -u <originalUser> 降回原用户。
    // root sudo 到普通用户无需额外密码，授权完全由 macOS 原生弹窗处理。

    private static let ansiRegex = try! NSRegularExpression(pattern: "\u{1B}\\[[0-9;]*[A-Za-z]")

    nonisolated func runStreamingAdmin(args: [String], proxyEnv: [String] = []) throws -> AsyncThrowingStream<StreamEvent, Error> {
        let brewPath = self.brewURL.path
        guard FileManager.default.isExecutableFile(atPath: brewPath) else {
            throw BrewError.brewNotFound
        }

        let logPath = NSTemporaryDirectory() + "brewmate_\(UUID().uuidString).log"
        FileManager.default.createFile(atPath: logPath, contents: nil)

        let username = ProcessInfo.processInfo.userName

        // Shell single-quote escape
        func sq(_ s: String) -> String {
            "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }

        let shellCmd = (["sudo -u", sq(username), "-H", "env",
                         "HOMEBREW_NO_ENV_HINTS=1", "HOMEBREW_COLOR=never",
                         "HOMEBREW_NO_EMOJI=1", "NO_COLOR=1"]
                        + proxyEnv
                        + [sq(brewPath)] + args.map(sq) + [">", sq(logPath), "2>&1"])
            .joined(separator: " ")

        let asEscaped = shellCmd
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let appleScript = "do shell script \"\(asEscaped)\" with administrator privileges"

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", appleScript]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()

        return AsyncThrowingStream { continuation in
            continuation.onTermination = { @Sendable [proc] _ in
                if proc.isRunning { proc.terminate() }
            }

            do {
                try proc.run()
            } catch {
                try? FileManager.default.removeItem(atPath: logPath)
                continuation.finish(throwing: error)
                return
            }

            Thread.detachNewThread {
                let fd = open(logPath, O_RDONLY)
                guard fd >= 0 else {
                    proc.terminate()
                    continuation.finish(throwing: BrewError.exit(-1, "log open failed"))
                    return
                }

                var lineBuffer = ""
                var offset: off_t = 0

                func drain() {
                    var buf = [UInt8](repeating: 0, count: 65536)
                    while true {
                        let n = pread(fd, &buf, buf.count, offset)
                        guard n > 0 else { break }
                        offset += off_t(n)
                        guard let s = String(bytes: buf[0..<n], encoding: .utf8) else { continue }
                        let range = NSRange(s.startIndex..., in: s)
                        let clean = BrewService.ansiRegex.stringByReplacingMatches(in: s, range: range, withTemplate: "")
                        lineBuffer += clean
                        while let nl = lineBuffer.firstIndex(of: "\n") {
                            var line = String(lineBuffer[..<nl])
                            lineBuffer.removeSubrange(...nl)
                            if line.hasSuffix("\r") { line.removeLast() }
                            if !line.isEmpty { continuation.yield(.line(line)) }
                        }
                    }
                }

                while proc.isRunning {
                    drain()
                    Thread.sleep(forTimeInterval: 0.05)
                }
                drain()
                if !lineBuffer.isEmpty { continuation.yield(.line(lineBuffer)) }

                close(fd)
                try? FileManager.default.removeItem(atPath: logPath)
                continuation.yield(.done(proc.terminationStatus))
                continuation.finish()
            }
        }
    }

    // MARK: 私有：一次性抓取命令全部输出

    private func runCapture(_ args: [String]) async throws -> Data {
        guard isAvailable else { throw BrewError.brewNotFound }

        let proc = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.executableURL = brewURL
        proc.arguments = args
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        var env = ProcessInfo.processInfo.environment
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        env["HOMEBREW_COLOR"] = "never"
        env["NO_COLOR"] = "1"
        proc.environment = env

        try proc.run()

        async let outData = readAll(outPipe.fileHandleForReading)
        async let errData = readAll(errPipe.fileHandleForReading)
        let out = await outData
        let err = await errData

        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let tail = String(data: err, encoding: .utf8) ?? ""
            throw BrewError.exit(proc.terminationStatus, tail)
        }
        return out
    }

    private nonisolated func readAll(_ handle: FileHandle) async -> Data {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let data = (try? handle.readToEnd()) ?? Data()
                cont.resume(returning: data)
            }
        }
    }
}

enum StreamEvent: Sendable {
    case line(String)
    case done(Int32)
}
