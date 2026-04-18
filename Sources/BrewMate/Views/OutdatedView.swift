import SwiftUI

struct OutdatedView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(model.outdated.count) 个过期包")
                    .font(.headline)
                Spacer()
                if model.hasBatchUpgradeRunning {
                    Button { } label: {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.mini)
                            Text("升级中…")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(true)
                } else {
                    Button {
                        model.upgrade(nil)
                    } label: {
                        Label("全部升级", systemImage: "arrow.up.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.outdated.isEmpty)
                }
            }
            .padding(10)
            .background(.bar)

            if model.isLoadingOutdated && model.outdated.isEmpty {
                ProgressView("检查过期包...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.outdated.isEmpty {
                ContentUnavailableView(
                    "全部已是最新",
                    systemImage: "checkmark.circle",
                    description: Text("没有需要升级的包")
                )
            } else {
                List(model.outdated) { item in
                    OutdatedRow(item: item)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
    }
}

private struct OutdatedRow: View {
    @Environment(AppModel.self) private var model
    let item: OutdatedItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.kind == .formula ? "terminal" : "app.badge")
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name).fontWeight(.medium)
                    if item.isPinned {
                        Image(systemName: "pin.fill").foregroundStyle(.orange).font(.caption)
                    }
                    Text(item.kind.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Text(item.installedVersion).monospaced().font(.caption).foregroundStyle(.secondary)
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                    Text(item.latestVersion).monospaced().font(.caption).foregroundStyle(.green)
                }
            }

            Spacer()

            if model.isWorkingOn(item.name) || model.hasBatchUpgradeRunning {
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
                Button("升级") { model.upgrade(item.name) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(item.isPinned)
            }
        }
        .padding(.vertical, 4)
    }
}
