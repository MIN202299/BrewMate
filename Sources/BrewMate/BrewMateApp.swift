import SwiftUI

@main
struct BrewMateApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("BrewMate") {
            ContentView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 580)
                .task {
                    await model.refreshAll()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Brew") {
                Button("Refresh Installed") {
                    Task { await model.refreshInstalled() }
                }
                .keyboardShortcut("r", modifiers: .command)
                Button("Refresh Outdated") {
                    Task { await model.refreshOutdated() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                Divider()
                Button("brew update") {
                    model.update()
                }
            }
        }
    }
}
