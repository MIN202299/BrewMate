import SwiftUI

struct SearchView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var bindable = model

        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索 formula 或 cask...", text: $bindable.searchQuery)
                    .textFieldStyle(.plain)
                    .onChange(of: bindable.searchQuery) { _, _ in
                        model.scheduleSearch()
                    }
                    .onSubmit { model.scheduleSearch() }

                if model.isSearching {
                    ProgressView().controlSize(.small)
                }

                Picker("", selection: $bindable.searchKind) {
                    Text("全部").tag(PackageKind?.none)
                    Text("Formula").tag(PackageKind?.some(.formula))
                    Text("Cask").tag(PackageKind?.some(.cask))
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .onChange(of: bindable.searchKind) { _, _ in
                    model.scheduleSearch()
                }
            }
            .padding(10)
            .background(.bar)

            if model.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                VStack(spacing: 0) {
                    Spacer()
                    ContentUnavailableView(
                        "搜索 Homebrew",
                        systemImage: "magnifyingglass",
                        description: Text("输入关键字以查找 formulae 或 casks")
                    )
                    Spacer()
                }
                .frame(maxHeight: .infinity)
            } else if model.searchResults.isEmpty && !model.isSearching {
                VStack(spacing: 0) {
                    Spacer()
                    ContentUnavailableView(
                        "无结果",
                        systemImage: "questionmark.circle",
                        description: Text("\"\(model.searchQuery)\" 没有匹配")
                    )
                    Spacer()
                }
                .frame(maxHeight: .infinity)
            } else {
                let installedNames = Set(model.installed.map { $0.id })
                List(model.searchResults) { r in
                    SearchRow(result: r, isInstalled: installedNames.contains(r.id))
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
    }
}

private struct SearchRow: View {
    @Environment(AppModel.self) private var model
    let result: SearchResult
    let isInstalled: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: result.kind == .formula ? "terminal" : "app.badge")
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.name).fontWeight(.medium)
                Text(result.kind.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isInstalled {
                if model.isWorkingOn(result.name) {
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
                    Button("卸载", role: .destructive) {
                        model.uninstall(result.name, cask: result.kind == .cask)
                    }
                    .controlSize(.small)
                }
            } else {
                if model.isWorkingOn(result.name) {
                    Button { } label: {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.mini)
                            Text("安装中")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(true)
                } else {
                    Button("安装") {
                        model.install(result.name, cask: result.kind == .cask)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
