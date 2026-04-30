import Foundation
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

    // MARK: - Jobs

    func startJob(title: String, args: [String], onComplete: (@Sendable () async -> Void)? = nil) {
        // 运行中的同名任务不重复触发，避免并发冲突；已完成/失败的均允许重试
        if let existing = jobs.last(where: { $0.title == title }),
           existing.status == .running {
            showLogPanel = true
            return
        }

        let log = JobLog(title: title)
        jobs.append(log)
        showLogPanel = true
        let id = log.id
        appendLine(jobID: id, "brew \(args.joined(separator: " "))")
        let proxy = ProxySettings.shared
        if proxy.enabled {
            let http = proxy.httpProxy.isEmpty ? "(未设置)" : proxy.httpProxy
            let socks = proxy.allProxy.isEmpty ? "" : "  all_proxy: \(proxy.allProxy)"
            appendLine(jobID: id, "→ 代理: \(http)\(socks)")
        }

        let stream: AsyncThrowingStream<StreamEvent, Error>
        do {
            stream = try service.runStreamingAdmin(args: args, proxyEnv: proxy.shellEnvArgs)
        } catch {
            appendLine(jobID: id, "❌ 启动失败: \(error.localizedDescription)")
            finishJob(id: id, exitCode: -1)
            return
        }

        Task { [weak self] in
            do {
                for try await event in stream {
                    guard let self else { return }
                    switch event {
                    case .line(let line):
                        self.appendLine(jobID: id, line)
                    case .done(let code):
                        if code != 0 {
                            self.appendLine(jobID: id, "→ [失败，退出码 \(code)]")
                        }
                        self.finishJob(id: id, exitCode: code)
                    }
                }
                self?.finishJob(id: id, exitCode: 0)
            } catch {
                self?.appendLine(jobID: id, "❌ \(error.localizedDescription)")
                self?.finishJob(id: id, exitCode: -1)
            }
            // 无论成功还是失败都刷新列表，确保 UI 与实际状态一致
            await onComplete?()
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

    func upgrade(_ name: String? = nil, cask: Bool? = nil) {
        var args = ["upgrade"]
        if let n = name {
            // 单包升级：明确 --cask/--formula 避免歧义
            if let c = cask { args.append(c ? "--cask" : "--formula") }
            args.append(n)
        } else {
            // 全量升级：必须加 --greedy 才会处理 auto_updates/version:latest 类型的 cask
            args.append("--greedy")
        }
        let jobTitle = name.map { "upgrade \($0)" } ?? "upgrade (all)"
        startJob(title: jobTitle, args: args) { [weak self] in
            // 升级成功后立即从待升级列表中移除，无需等待 refreshOutdated 完成
            if let n = name {
                await MainActor.run { [weak self] in
                    if self?.jobs.last(where: { $0.title == "upgrade \(n)" })?.status == .succeeded {
                        self?.outdated.removeAll { $0.name == n }
                    }
                }
            }
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
