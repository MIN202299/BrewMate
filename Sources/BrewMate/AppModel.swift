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

    private func requestPassword(for jobID: UUID, promptText: String) -> String? {
        // 检测到 "Sorry, try again." → 清掉缓存的尝试
        let isRetry = promptText.lowercased().contains("try again")
        if isRetry {
            pwdAttempts[jobID] = (pwdAttempts[jobID] ?? 0) + 1
        } else if pwdAttempts[jobID] == nil {
            pwdAttempts[jobID] = 0
        }
        // 最多允许 3 次输入（含首次）
        guard (pwdAttempts[jobID] ?? 0) <= 2 else {
            return nil
        }

        let alert = NSAlert()
        alert.messageText = "需要管理员密码"
        alert.informativeText = isRetry
            ? "密码错误，请重试"
            : "此操作需要 sudo 权限，请输入密码"
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")

        let secure = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 22))
        secure.isBezeled = true
        secure.focusRingType = .default

        // 把输入框放到 alert 的 accessory view 里
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 250, height: 22))
        container.addSubview(secure)
        alert.accessoryView = container

        // 让对话框弹出时自动聚焦
        secure.becomeFirstResponder()

        let resp = alert.runModal()
        guard resp == .alertFirstButtonReturn else { return nil }
        return secure.stringValue
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
                    case .passwordPrompt(let promptText):
                        let password = self.requestPassword(for: id, promptText: promptText)
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
            // 清理重试计数
            await MainActor.run {
                self?.pwdAttempts.removeValue(forKey: id)
                ctrl.closeMaster()
            }
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
