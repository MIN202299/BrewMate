import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var bindable = model

        NavigationSplitView {
            List(selection: $bindable.selectedTab) {
                NavigationLink(value: AppModel.Tab.installed) {
                    Label {
                        HStack {
                            Text("已安装")
                            Spacer()
                            Text("\(model.installed.count)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    } icon: { Image(systemName: "shippingbox") }
                }
                NavigationLink(value: AppModel.Tab.outdated) {
                    Label {
                        HStack {
                            Text("过期")
                            Spacer()
                            if model.outdated.count > 0 {
                                Text("\(model.outdated.count)")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.red, in: Capsule())
                                    .foregroundStyle(.white)
                            }
                        }
                    } icon: { Image(systemName: "arrow.up.circle") }
                }
                NavigationLink(value: AppModel.Tab.search) {
                    Label("搜索", systemImage: "magnifyingglass")
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .navigationTitle("BrewMate")
        } detail: {
            VStack(spacing: 0) {
                switch model.selectedTab {
                case .installed: InstalledView()
                case .outdated:  OutdatedView()
                case .search:    SearchView()
                }

                if model.showLogPanel && !model.jobs.isEmpty {
                    Divider()
                    JobLogView()
                        .frame(height: 220)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await model.refreshAll() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoadingInstalled || model.isLoadingOutdated)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.update()
                } label: {
                    Label("brew update", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.showLogPanel.toggle()
                } label: {
                    Label("日志", systemImage: model.showLogPanel ? "rectangle.bottomthird.inset.filled" : "rectangle")
                }
                .disabled(model.jobs.isEmpty)
            }
        }
        .alert("出错了", isPresented: Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )) {
            Button("OK") { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
    }
}
