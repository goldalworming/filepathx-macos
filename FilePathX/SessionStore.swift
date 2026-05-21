import Foundation

struct SessionState: Codable {
    struct PanelState: Codable {
        var tabPaths: [String]
        var activeTabIndex: Int
    }
    var panels: [PanelState]
    var activePanelIndex: Int
}

/// Persists which folders were open across launches. All writes are debounced
/// so rapid changes (navigate-spam, open-close tabs) coalesce into one disk
/// write.
@MainActor
final class SessionStore {
    static let shared = SessionStore()
    weak var app: AppModel?

    private let key = "FilePathX.session.v1"
    private var pending = false

    func load() -> SessionState? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SessionState.self, from: data)
    }

    /// Coalesce multiple mutations within ~400ms into a single write.
    func scheduleSave() {
        guard !pending else { return }
        pending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.flush()
        }
    }

    private func flush() {
        pending = false
        guard let app else { return }
        let snapshot = SessionState(
            panels: app.panels.map { panel in
                let active = panel.tabs.firstIndex { $0.id == panel.activeTabID } ?? 0
                return SessionState.PanelState(
                    tabPaths: panel.tabs.map { $0.url.standardizedFileURL.path },
                    activeTabIndex: active
                )
            },
            activePanelIndex: app.activePanelIndex
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
