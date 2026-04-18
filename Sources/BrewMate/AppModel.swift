import Foundation
import AppKit
import Observation

@Observable
@MainActor
final class AppModel {
    enum Tab: Hashable { case installed, outdated, search }

    // 数据
    var installed: [Package] = []
    var outdated: [OutdatedItem] = []
    var searchResults: [SearchResult] = []

    // UI 状态
    var selectedTab: Tab = .installed
    var selectedPackageID: String? = nil
    var searchQuery: String = ""
    var searchKind: PackageKind? = nil

    var isLoadingInstalled = false
    var isLoadingOutdated = false
    var isSearching = false

    // 错误提示
    var lastError: String? = nil

    // Job 日志
    var jobs: [JobLog] = []
    var showLogPanel: Bool = false

    // 密码重试跟踪（按 job id，记录错误尝试次数）
    private var pwdAttempts: [UUID: Int] = [:]
    // PTY 输出中检测到 "try again" 的 job 集合
    private var sudoRetryFlags: Set<UUID> = []

    private let service = BrewService.shared
    private var searchTask: Task<Void, Never>? = nil

    // MARK: - Refresh

    func refreshAll() async {
        await refreshInstalled()
        await refreshOutdated()
    }

    func refreshInstalled() async {
        isLoadingInstalled = true
        defer { isLoadingInstalled = false }
        do {
            installed = try await service.listInstalled()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshOutdated() async {
        isLoadingOutdated = true
        defer { isLoadingOutdated = false }
        do {
            outdated = try await service.outdated()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Search

    func scheduleSearch() {
        searchTask?.cancel()
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let kind = searchKind
        guard !q.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            await self?.performSearch(q, kind: kind)
        }
    }

    private func performSearch(_ q: String, kind: PackageKind?) async {
        defer { isSearching = false }
        do {
            let results = try await service.search(q, kind: kind)
            if q == searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) {
                searchResults = results
            }
        } catch is CancellationError {
        } catch {
            lastError = error.localizedDescription
            searchResults = []
        }
    }

    // MARK: - Password prompt dialog

    private func requestPassword(for jobID: UUID, isRetry: Bool) async -> String? {
        if isRetry {
            CredentialStore.shared.delete()
            pwdAttempts[jobID, default: 0] += 1
        } else {
            if pwdAttempts[jobID] == nil { pwdAttempts[jobID] = 0 }
        }
        guard (pwdAttempts[jobID] ?? 0) <= 2 else { return nil }

        // 优先走 Keychain + Touch ID（仅首次，重试时说明缓存密码有误）
        if !isRetry, CredentialStore.shared.hasStoredPassword {
            if let pwd = await CredentialStore.shared.load(
                reason: "BrewMate 需要验证身份以执行 Homebrew 操作"
            ) {
                return pwd
            }
            // 用户取消 Touch ID → 降级到密码框
        }

        return showPasswordDialog(isRetry: isRetry)
    }

    private func showPasswordDialog(isRetry: Bool) -> String? {
        let alert = NSAlert()
        alert.messageText = "需要管理员密码"
        alert.informativeText = isRetry
            ? "密码错误，请重试"
            : "此操作需要 sudo 权限，请输入密码"
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")

        let hasTouch = CredentialStore.shared.isBiometricsAvailable
        let containerH: CGFloat = hasTouch ? 52 : 24
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: containerH))

        let secure = NSSecureTextField(frame: NSRect(x: 0, y: containerH - 24, width: 260, height: 22))
        secure.isBezeled = true
        secure.focusRingType = .default
        container.addSubview(secure)

        var rememberBox: NSButton?
        if hasTouch {
            let cb = NSButton(checkboxWithTitle: "使用 Touch ID 记住密码", target: nil, action: nil)
            cb.frame = NSRect(x: 2, y: 2, width: 260, height: 18)
            cb.state = .on
            container.addSubview(cb)
            rememberBox = cb
        }

        alert.accessoryView = container
        // layout() 后 window 已存在，设置 initialFirstResponder 才有效
        alert.layout()
        alert.window.initialFirstResponder = secure

        let resp = alert.runModal()
        guard resp == .alertFirstButtonReturn, !secure.stringValue.isEmpty else { return nil }

        let password = secure.stringValue
        if rememberBox?.state == .on {
            try? CredentialStore.shared.save(password)
        }
        return password
    }

    // MARK: - Jobs

    func startJob(title: String, args: [String], onComplete: (@Sendable () async -> Void)? = nil) {
        // 幂等：已有同名任务在运行/已成功 → 直接展开日志不重复触发；失败的允许重试
        if let existing = jobs.last(where: { $0.title == title }) {
            switch existing.status {
            case .running, .succeeded:
                showLogPanel = true
                return
            case .failed:
                break
            }
        }

        let log = JobLog(title: title)
        jobs.append(log)
        showLogPanel = true
        let id = log.id

        // 启动 PTY 流
        let result: (stream: AsyncThrowingStream<StreamEvent, Error>, controller: PTYController)
        do {
            result = try service.runStreamingPTY(args: args)
        } catch {
            appendLine(jobID: id, "❌ 启动失败: \(error.localizedDescription)")
            finishJob(id: id, exitCode: -1)
            return
        }
        let (stream, ctrl) = result

        Task { [weak self] in
            do {
                for try await event in stream {
                    guard let self else { ctrl.closeMaster(); return }
                    switch event {
                    case .started(let pid):
                        self.appendLine(jobID: id, "[pid \(pid)] brew \(args.joined(separator: " "))")
                    case .line(let line):
                        self.appendLine(jobID: id, line)
                        if line.lowercased().contains("try again") {
                            self.sudoRetryFlags.insert(id)
                        }
                    case .passwordPrompt:
                        let isRetry = self.sudoRetryFlags.remove(id) != nil
                        let password = await self.requestPassword(for: id, isRetry: isRetry)
                        if let password, !password.isEmpty {
                            writePTYPassword(password, toFD: ctrl.masterFD)
                            self.appendLine(jobID: id, "→ [密码已提交]")
                        } else {
                            // 用户取消或超过重试次数
                            ctrl.terminate()
                            self.appendLine(jobID: id, "→ [密码已取消]")
                        }
                    case .done(let code):
                        self.finishJob(id: id, exitCode: code)
                    }
                }
                // Stream 正常完成
                self?.finishJob(id: id, exitCode: 0)
                await onComplete?()
            } catch let BrewError.exit(code, _) {
                self?.finishJob(id: id, exitCode: code)
                await onComplete?()
            } catch {
                self?.appendLine(jobID: id, "❌ \(error.localizedDescription)")
                self?.finishJob(id: id, exitCode: -1)
            }
            self?.pwdAttempts.removeValue(forKey: id)
            self?.sudoRetryFlags.remove(id)
            ctrl.closeMaster()
        }
    }

    private func appendLine(jobID: UUID, _ line: String) {
        guard let idx = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[idx].lines.append(line)
    }

    private func finishJob(id: UUID, exitCode: Int32) {
        guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
        if jobs[idx].status == .running {
            jobs[idx].exitCode = exitCode
            jobs[idx].status = exitCode == 0 ? .succeeded : .failed
            jobs[idx].endedAt = Date()
        }
    }

    // MARK: - 具体操作封装

    /// 判断某包是否正在被操作（install/uninstall/upgrade）
    func isWorkingOn(_ name: String) -> Bool {
        jobs.contains { $0.status == .running && ($0.title.contains(" \(name)") || $0.title.hasSuffix(" \(name)")) }
    }

    /// 判断是否有批量升级任务在运行
    var hasBatchUpgradeRunning: Bool {
        jobs.contains { $0.title == "upgrade (all)" && $0.status == .running }
    }

    func install(_ name: String, cask: Bool) {
        var args = ["install"]
        if cask { args.append("--cask") }
        args.append(name)
        startJob(title: "install \(name)", args: args) { [weak self] in
            await self?.refreshInstalled()
            await self?.refreshOutdated()
        }
    }

    func uninstall(_ name: String, cask: Bool) {
        var args = ["uninstall"]
        if cask { args.append("--cask") }
        args.append(name)
        startJob(title: "uninstall \(name)", args: args) { [weak self] in
            await self?.refreshInstalled()
        }
    }

    func upgrade(_ name: String? = nil) {
        var args = ["upgrade"]
        if let n = name { args.append(n) }
        startJob(title: name.map { "upgrade \($0)" } ?? "upgrade (all)", args: args) { [weak self] in
            await self?.refreshInstalled()
            await self?.refreshOutdated()
        }
    }

    func update() {
        startJob(title: "update", args: ["update"]) { [weak self] in
            await self?.refreshOutdated()
        }
    }
}

@Observable
final class JobLog: Identifiable {
    let id = UUID()
    let title: String
    let startedAt: Date = Date()
    var endedAt: Date? = nil
    var lines: [String] = []
    var exitCode: Int32? = nil
    var status: Status = .running

    enum Status: Sendable { case running, succeeded, failed }

    init(title: String) {
        self.title = title
    }
}
