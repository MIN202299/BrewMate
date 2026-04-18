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

    // MARK: 写命令：PTY 流式（支持 sudo 密码交互）

    nonisolated func runStreamingPTY(args: [String]) throws -> (stream: AsyncThrowingStream<StreamEvent, Error>, controller: PTYController) {
        let brewURL = self.brewURL
        guard FileManager.default.isExecutableFile(atPath: brewURL.path) else {
            throw BrewError.brewNotFound
        }

        var env = ProcessInfo.processInfo.environment
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        env["HOMEBREW_COLOR"] = "never"
        env["HOMEBREW_NO_EMOJI"] = "1"
        env["NO_COLOR"] = "1"
        env["TERM"] = "dumb"

        let ctrl = try spawnPTY(executable: brewURL.path, args: args, env: env)

        let stream = AsyncThrowingStream<StreamEvent, Error> { continuation in
            continuation.yield(.started(pid: ctrl.pid))

            continuation.onTermination = { @Sendable _ in
                ctrl.terminate()
            }

            Thread.detachNewThread {
                let master = ctrl.masterFD
                var buffer = [UInt8](repeating: 0, count: 4096)
                var lineBuffer = ""  // 未终结的部分行（可能是 "Password:" 提示）
                var lastPromptEmitAt: Date = .distantPast

                while true {
                    let n = read(master, &buffer, buffer.count)
                    if n <= 0 { break }
                    guard let chunk = String(bytes: buffer[0..<n], encoding: .utf8) else { continue }
                    lineBuffer += chunk

                    // 切出完整行
                    while let nl = lineBuffer.firstIndex(of: "\n") {
                        var line = String(lineBuffer[..<nl])
                        lineBuffer.removeSubrange(...nl)
                        // 清掉 PTY 的 \r
                        if line.hasSuffix("\r") { line.removeLast() }
                        if !line.isEmpty {
                            continuation.yield(.line(line))
                        }
                    }

                    // 剩余未终结行：检测是否是密码提示
                    if Self.looksLikePasswordPrompt(lineBuffer) {
                        // 至少相隔 200ms，避免同一提示重复触发
                        if Date().timeIntervalSince(lastPromptEmitAt) > 0.2 {
                            lastPromptEmitAt = Date()
                            continuation.yield(.passwordPrompt(text: lineBuffer))
                        }
                    }
                }

                // flush 残余
                if !lineBuffer.isEmpty {
                    continuation.yield(.line(lineBuffer))
                }

                let code = ctrl.waitForExit()
                ctrl.closeMaster()
                continuation.yield(.done(code))
                continuation.finish()
            }
        }

        return (stream, ctrl)
    }

    /// 判断缓冲区末尾是否像 sudo 密码提示
    static func looksLikePasswordPrompt(_ buffer: String) -> Bool {
        // 取末尾最多 120 字节做匹配
        let tail = String(buffer.suffix(120)).lowercased()
        // 典型 sudo 提示："Password:" 或 "password:" 行末
        // macOS 本地化后可能是 "密码:" 或 "口令:"
        if tail.hasSuffix("password:") || tail.hasSuffix("password: ") { return true }
        if tail.contains("[sudo] password") && (tail.hasSuffix(":") || tail.hasSuffix(": ")) { return true }
        if tail.hasSuffix("密码：") || tail.hasSuffix("密码:") { return true }
        if tail.hasSuffix("口令：") || tail.hasSuffix("口令:") { return true }
        return false
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
    case started(pid: pid_t)
    case line(String)
    case passwordPrompt(text: String)
    case done(Int32)
}
