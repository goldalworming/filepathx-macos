import Foundation
import Combine
import AppKit

/// Independent file-browser pane. Owns its own tabs + active tab.
/// `AppModel.panels` holds one or two of these (single-pane vs dual-pane mode).
@MainActor
final class Panel: ObservableObject, Identifiable {
    let id = UUID()
    @Published var tabs: [BrowserTab] = []
    @Published var activeTabID: BrowserTab.ID?

    var activeTab: BrowserTab? {
        tabs.first { $0.id == activeTabID }
    }

    init(url: URL? = nil) {
        let start = url ?? FileManager.default.homeDirectoryForCurrentUser
        let tab = BrowserTab(url: start)
        tabs = [tab]
        activeTabID = tab.id
    }

    func openTab(url: URL? = nil) {
        let start = url ?? activeTab?.url ?? FileManager.default.homeDirectoryForCurrentUser
        let tab = BrowserTab(url: start)
        tabs.append(tab)
        activeTabID = tab.id
    }

    func closeTab(id: BrowserTab.ID) {
        guard tabs.count > 1 else { return }
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: idx)
        if activeTabID == id {
            activeTabID = tabs[max(0, idx - 1)].id
        }
    }

    func closeActiveTab() {
        guard let id = activeTabID else { return }
        closeTab(id: id)
    }
}
