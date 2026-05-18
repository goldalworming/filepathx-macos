import SwiftUI

@main
struct FilePathXApp: App {
    @StateObject private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(app)
                .frame(minWidth: 900, minHeight: 560)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") { app.openTab() }
                    .keyboardShortcut("t", modifiers: .command)
                Button("Close Tab") { app.closeActiveTab() }
                    .keyboardShortcut("w", modifiers: .command)
            }
            CommandGroup(after: .sidebar) {
                Button("Back") { app.activeTab?.goBack() }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(app.activeTab?.canGoBack != true)
                Button("Forward") { app.activeTab?.goForward() }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(app.activeTab?.canGoForward != true)
                Button("Enclosing Folder") { app.activeTab?.goUp() }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                    .disabled(app.activeTab?.canGoUp != true)
                Button("Open") { app.activeTab?.openSelection() }
                    .keyboardShortcut(.downArrow, modifiers: .command)
                    .disabled(app.activeTab?.selection.isEmpty != false)
                Divider()
                Button("Refresh") { app.activeTab?.reload() }
                    .keyboardShortcut("r", modifiers: .command)
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("New Folder") {
                    guard let tab = app.activeTab else { return }
                    if let url = FileSystemService.createFolder(in: tab.url) {
                        tab.reload()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            if let entry = tab.entries.first(where: { $0.url == url }) {
                                tab.selection = [entry.id]
                                tab.beginRename(id: entry.id)
                            }
                        }
                    }
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }
    }
}
