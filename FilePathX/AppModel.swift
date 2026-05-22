import Foundation
import Combine
import AppKit

@MainActor
final class AppModel: ObservableObject {
    @Published var panels: [Panel]
    @Published var activePanelIndex: Int = 0
    @Published var sidebarItems: [SidebarItem] = SidebarItem.defaults
    @Published var bookmarks: [SidebarItem] = []
    @Published var clipboard = FileClipboard()

    private let bookmarksKey = "FilePathX.bookmarks.v1"
    private var keyboardMonitor: KeyboardShortcutMonitor?

    var activePanel: Panel { panels[activePanelIndex] }
    var activeTab: BrowserTab? { activePanel.activeTab }
    var isSplit: Bool { panels.count >= 2 }

    init() {
        if let saved = SessionStore.shared.load(), !saved.panels.isEmpty {
            self.panels = saved.panels.map { Panel(state: $0) }
            self.activePanelIndex = min(max(0, saved.activePanelIndex), saved.panels.count - 1)
        } else {
            self.panels = [Panel()]
            self.activePanelIndex = 0
        }
        SessionStore.shared.app = self
        loadBookmarks()
        keyboardMonitor = KeyboardShortcutMonitor(app: self)
    }

    // MARK: - Tabs (route to active panel)

    func openTab(url: URL? = nil) {
        activePanel.openTab(url: url)
    }

    func closeActiveTab() {
        activePanel.closeActiveTab()
    }

    // MARK: - Split mode

    func toggleSplit() {
        if isSplit {
            panels = [panels[0]]
            activePanelIndex = 0
        } else {
            let startUrl = activeTab?.url
            panels.append(Panel(url: startUrl))
            activePanelIndex = 1
        }
        SessionStore.shared.scheduleSave()
    }

    func setActivePanel(_ panel: Panel) {
        // Click on a Table cell already transfers AppKit first-responder to
        // that Table, so we don't call transferFocusToActivePanel here —
        // doing so would race with the click and clobber the new selection.
        // Tab keyboard switching is where transferFocus is needed; that path
        // calls it explicitly from the monitor.
        if let idx = panels.firstIndex(where: { $0.id == panel.id }) {
            activePanelIndex = idx
            SessionStore.shared.scheduleSave()
        }
    }

    /// Scrolls the active panel's view so the current selection is on screen.
    /// Used by `⌘N` / `⌘⇧N` since "untitled file"/"untitled folder" usually
    /// sorts deep in the list and would otherwise appear off-screen.
    func scrollActiveSelectionIntoView() {
        DispatchQueue.main.async {
            guard let tab = self.activeTab,
                  let id = tab.selection.first else { return }

            if tab.viewMode == .details {
                guard let row = tab.entries.firstIndex(where: { $0.id == id }),
                      let window = NSApp.keyWindow else { return }
                let allTables = Self.allTableViews(in: window.contentView)
                let panelCount = self.panels.count
                guard allTables.count >= panelCount,
                      self.activePanelIndex < panelCount else { return }
                let dataTables = Array(allTables.suffix(panelCount))
                dataTables[self.activePanelIndex].scrollRowToVisible(row)
            } else {
                // Icon modes use SwiftUI's ScrollViewReader; publish the id
                // and let IconGridView react.
                tab.pendingScrollToID = id
            }
        }
    }

    /// Transfers AppKit first responder to the active panel's NSTableView so
    /// the row selection actually renders as "focused" (blue) and arrow keys
    /// drive the right table. SwiftUI's `.environment(\.controlActiveState)`
    /// alone doesn't do this — Cocoa decides selection color from first
    /// responder, not from environment values.
    func transferFocusToActivePanel() {
        DispatchQueue.main.async {
            guard let window = NSApp.keyWindow else { return }
            let allTables = Self.allTableViews(in: window.contentView)
            // Sidebar's List is also an NSTableView (subclass NSOutlineView)
            // and shows up earlier in DFS order. The actual panel data tables
            // are the *last* N tables — one per panel, in left→right order.
            let panelCount = self.panels.count
            guard allTables.count >= panelCount,
                  self.activePanelIndex < panelCount else { return }
            let dataTables = Array(allTables.suffix(panelCount))
            window.makeFirstResponder(dataTables[self.activePanelIndex])
        }
    }

    private static func allTableViews(in view: NSView?) -> [NSTableView] {
        guard let view else { return [] }
        var result: [NSTableView] = []
        if let table = view as? NSTableView { result.append(table) }
        for sub in view.subviews {
            result.append(contentsOf: allTableViews(in: sub))
        }
        return result
    }

    // MARK: - Clipboard

    var canPaste: Bool {
        if !clipboard.isEmpty { return true }
        return NSPasteboard.general.canReadObject(forClasses: [NSURL.self], options: nil)
    }

    func cut(urls: [URL]) {
        guard !urls.isEmpty else { return }
        clipboard.urls = urls
        clipboard.operation = .cut
        writeFilesToPasteboard(urls)
    }

    func copy(urls: [URL]) {
        guard !urls.isEmpty else { return }
        clipboard.urls = urls
        clipboard.operation = .copy
        writeFilesToPasteboard(urls)
    }

    func paste(into destination: URL) {
        if !clipboard.isEmpty {
            let urls = clipboard.urls
            let prompter = CopyConflictPrompter()
            switch clipboard.operation {
            case .copy:
                FileSystemService.copy(urls: urls, to: destination) { target in
                    prompter.resolve(targetURL: target)
                }
            case .cut:
                FileSystemService.move(urls: urls, to: destination) { target in
                    prompter.resolve(targetURL: target, isMove: true)
                }
                clipboard.urls = []
            }
            activeTab?.reload()
            return
        }
        let pb = NSPasteboard.general
        if let objects = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           !objects.isEmpty {
            let prompter = CopyConflictPrompter()
            FileSystemService.copy(urls: objects, to: destination) { target in
                prompter.resolve(targetURL: target)
            }
            activeTab?.reload()
        }
    }

    private func writeFilesToPasteboard(_ urls: [URL]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls.map { $0 as NSURL })
    }

    // MARK: - Bookmarks

    func addBookmark(url: URL, name: String? = nil) {
        if bookmarks.contains(where: { $0.path == url.path }) { return }
        let item = SidebarItem(
            name: name ?? url.lastPathComponent,
            url: url,
            systemImage: "bookmark.fill"
        )
        bookmarks.append(item)
        saveBookmarks()
    }

    func removeBookmark(_ item: SidebarItem) {
        bookmarks.removeAll { $0.id == item.id }
        saveBookmarks()
    }

    func moveBookmarks(from source: IndexSet, to destination: Int) {
        bookmarks.move(fromOffsets: source, toOffset: destination)
        saveBookmarks()
    }

    func persistBookmarks() {
        saveBookmarks()
    }

    func isBookmarked(_ url: URL) -> Bool {
        bookmarks.contains(where: { $0.path == url.path })
    }

    func toggleBookmark(_ url: URL) {
        if let existing = bookmarks.first(where: { $0.path == url.path }) {
            removeBookmark(existing)
        } else {
            addBookmark(url: url)
        }
    }

    private func loadBookmarks() {
        guard let data = UserDefaults.standard.data(forKey: bookmarksKey) else { return }
        if let decoded = try? JSONDecoder().decode([SidebarItem].self, from: data) {
            bookmarks = decoded
        }
    }

    private func saveBookmarks() {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        UserDefaults.standard.set(data, forKey: bookmarksKey)
    }
}
