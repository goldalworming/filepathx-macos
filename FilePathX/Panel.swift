import Foundation
import Combine
import AppKit

/// Independent file-browser pane. Owns its own tabs + active tab.
/// `AppModel.panels` holds one or two of these (single-pane vs dual-pane mode).
@MainActor
final class Panel: ObservableObject, Identifiable {
    let id = UUID()
    @Published var tabs: [BrowserTab] = []
    @Published var activeTabID: BrowserTab.ID? {
        didSet { SessionStore.shared.scheduleSave() }
    }

    var activeTab: BrowserTab? {
        tabs.first { $0.id == activeTabID }
    }

    init(url: URL? = nil) {
        let start = url ?? FileManager.default.homeDirectoryForCurrentUser
        let tab = BrowserTab(url: start)
        tabs = [tab]
        activeTabID = tab.id
    }

    /// Restore a panel from saved session state. Tabs are created without
    /// auto-loading their entries; only the active tab pays the I/O cost on
    /// launch (others load when first activated). Missing paths fall back to
    /// the user's home directory so a stale session never breaks startup.
    init(state: SessionState.PanelState) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let urls = state.tabPaths.map { path -> URL in
            let url = URL(fileURLWithPath: path)
            return FileManager.default.fileExists(atPath: path) ? url : home
        }
        let activeIdx = min(max(0, state.activeTabIndex), max(0, urls.count - 1))
        let activeKnown = !urls.isEmpty

        let built = urls.enumerated().map { idx, url in
            BrowserTab(url: url, autoLoad: activeKnown && idx == activeIdx)
        }
        self.tabs = built.isEmpty ? [BrowserTab(url: home)] : built
        self.activeTabID = self.tabs[activeKnown ? activeIdx : 0].id
    }

    func openTab(url: URL? = nil) {
        let start = url ?? activeTab?.url ?? FileManager.default.homeDirectoryForCurrentUser
        let tab = BrowserTab(url: start)
        tabs.append(tab)
        activeTabID = tab.id
        SessionStore.shared.scheduleSave()
    }

    func closeTab(id: BrowserTab.ID) {
        guard tabs.count > 1 else { return }
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: idx)
        if activeTabID == id {
            activeTabID = tabs[max(0, idx - 1)].id
        }
        SessionStore.shared.scheduleSave()
    }

    func closeActiveTab() {
        guard let id = activeTabID else { return }
        closeTab(id: id)
    }

    func nextTab() {
        guard tabs.count > 1,
              let cur = activeTabID,
              let idx = tabs.firstIndex(where: { $0.id == cur }) else { return }
        activeTabID = tabs[(idx + 1) % tabs.count].id
    }

    func prevTab() {
        guard tabs.count > 1,
              let cur = activeTabID,
              let idx = tabs.firstIndex(where: { $0.id == cur }) else { return }
        activeTabID = tabs[(idx - 1 + tabs.count) % tabs.count].id
    }
}
