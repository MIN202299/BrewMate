import SwiftUI

struct InstalledView: View {
    @Environment(AppModel.self) private var model
    @State private var filter: String = ""
    @State private var kindFilter: KindFilter = .all

    enum KindFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case formula = "Formula"
        case cask = "Cask"
        var id: String { rawValue }
    }

    var filtered: [Package] {
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        return model.installed.filter { pkg in
            if kindFilter == .formula && pkg.kind != .formula { return false }
            if kindFilter == .cask && pkg.kind != .cask { return false }
            if q.isEmpty { return true }
            return pkg.name.lowercased().contains(q) || (pkg.description?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "line.3.horizontal.decrease.circle").foregroundStyle(.secondary)
                TextField("过滤已安装...", text: $filter)
                    .textFieldStyle(.plain)
                Picker("", selection: $kindFilter) {
                    ForEach(KindFilter.allCases) { k in Text(k.rawValue).tag(k) }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            .padding(10)
            .background(.bar)

            if model.isLoadingInstalled && model.installed.isEmpty {
                ProgressView("加载已安装包...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.installed.isEmpty {
                ContentUnavailableView("没有已安装的包", systemImage: "shippingbox", description: Text("点击顶部刷新按钮再试"))
                    .frame(maxHeight: .infinity)
            } else if filtered.isEmpty {
                ContentUnavailableView("没有匹配", systemImage: "magnifyingglass", description: Text("调整过滤条件或类型筛选"))
                    .frame(maxHeight: .infinity)
            } else {
                List(filtered) { p in
                    InstalledRow(pkg: p)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
    }
}

private struct InstalledRow: View {
    @Environment(AppModel.self) private var model
    let pkg: Package

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: pkg.kind == .formula ? "terminal" : "app.badge")
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(pkg.name).fontWeight(.medium)
                    if pkg.isPinned {
                        Image(systemName: "pin.fill").foregroundStyle(.orange).font(.caption)
                    }
                    if pkg.isOutdated {
                        Text("过期")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.red, in: Capsule())
                    }
                    Text(pkg.kind.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let v = pkg.installedVersion {
                        Text(v).font(.caption).monospaced().foregroundStyle(.secondary)
                    }
                }
                if let desc = pkg.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 6) {
                if pkg.isOutdated {
                    upgradeButton(for: pkg)
                }
                uninstallButton(for: pkg)
                if let hp = pkg.homepage, let url = URL(string: hp) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: { Image(systemName: "safari") }
                        .buttonStyle(.borderless)
                        .help(hp)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func upgradeButton(for pkg: Package) -> some View {
        if model.isWorkingOn(pkg.name) || model.hasBatchUpgradeRunning {
            Button { } label: {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("升级中")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(true)
        } else {
            Button("升级") { model.upgrade(pkg.name) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }

    @ViewBuilder
    private func uninstallButton(for pkg: Package) -> some View {
        if model.isWorkingOn(pkg.name) {
            Button { } label: {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("卸载中")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(true)
        } else {
            Button(role: .destructive) {
                model.uninstall(pkg.name, cask: pkg.kind == .cask)
            } label: { Text("卸载") }
                .controlSize(.small)
        }
    }
}
