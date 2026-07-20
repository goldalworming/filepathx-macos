import SwiftUI
import AppKit

struct FileContextMenu: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var tab: BrowserTab
    let selectionIDs: Set<FileEntry.ID>

    private var selectedEntries: [FileEntry] {
        tab.entries.filter { selectionIDs.contains($0.id) }
    }

    private var selectedURLs: [URL] {
        selectedEntries.map(\.url)
    }

    var body: some View {
        Group {
            if selectionIDs.isEmpty {
                emptyAreaMenu
            } else {
                selectionMenu
            }
        }
    }

    @ViewBuilder
    private var selectionMenu: some View {
        Button("Open") { selectedEntries.forEach(tab.open) }
        Button("Open in New Tab") {
            for entry in selectedEntries where entry.isDirectory {
                app.openTab(url: entry.url)
            }
        }
        .disabled(!selectedEntries.contains(where: { $0.isDirectory }))

        Divider()
        Button("Cut") { app.cut(urls: selectedURLs) }
        Button("Copy") { app.copy(urls: selectedURLs) }
        Button("Paste") { app.paste(into: tab.url) }
            .disabled(!app.canPaste)

        Divider()
        if selectionIDs.count >= 2 {
            Button("Rename \(selectionIDs.count) Items") {
                tab.beginBatchRename(urls: selectedURLs)
            }
        } else {
            Button("Rename") {
                if let first = selectionIDs.first {
                    tab.beginRename(id: first)
                }
            }
            .disabled(selectionIDs.count != 1)
        }

        Button("Move to Trash", role: .destructive) {
            FileSystemService.trash(urls: selectedURLs)
            tab.selection.removeAll()
            tab.reload()
        }

        Divider()
        Button("Copy Path") {
            let joined = selectedURLs.map(\.path).joined(separator: "\n")
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(joined, forType: .string)
        }
        Button("Reveal in Finder") {
            FileSystemService.revealInFinder(selectedURLs)
        }
    }

    @ViewBuilder
    private var emptyAreaMenu: some View {
        Button("New Folder") {
            if let url = FileSystemService.createFolder(in: tab.url) {
                tab.reload()
                // Begin rename on the newly-created folder once it appears
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    if let entry = tab.entries.first(where: { $0.url == url }) {
                        tab.selection = [entry.id]
                        tab.beginRename(id: entry.id)
                    }
                }
            }
        }
        Button("New File") {
            if let url = FileSystemService.createFile(in: tab.url) {
                tab.reload()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    if let entry = tab.entries.first(where: { $0.url == url }) {
                        tab.selection = [entry.id]
                        tab.beginRename(id: entry.id)
                    }
                }
            }
        }

        Divider()
        Button("Paste") { app.paste(into: tab.url) }
            .disabled(!app.canPaste)

        Divider()
        Menu("Sort By") {
            SortMenuItems(tab: tab)
        }

        Divider()
        Button("Refresh") { tab.reload() }
        Button("Open in Terminal") {
            FileSystemService.openInTerminal(tab.url)
        }

        Divider()
        Button(app.isBookmarked(tab.url) ? "Remove Bookmark" : "Add to Bookmarks") {
            app.toggleBookmark(tab.url)
        }
    }
}
