import Foundation

/// Per-folder UI preferences (view mode + sort). Persisted in `UserDefaults`
/// keyed by absolute folder path so reopening a folder restores its last layout.
struct FolderPrefs: Codable, Equatable {
    var viewMode: ViewMode
    var sortColumn: SortColumn
    var sortAscending: Bool

    static let `default` = FolderPrefs(viewMode: .details,
                                       sortColumn: .name,
                                       sortAscending: true)

    var isDefault: Bool { self == .default }
}

@MainActor
final class FolderPreferences {
    static let shared = FolderPreferences()

    private let key = "FilePathX.folderPrefs.v1"
    private var store: [String: FolderPrefs] = [:]
    private var saveScheduled = false

    private init() {
        load()
    }

    func prefs(for url: URL) -> FolderPrefs? {
        store[normalize(url)]
    }

    func save(_ prefs: FolderPrefs, for url: URL) {
        let path = normalize(url)
        // Don't store default settings — keeps the store small and means a
        // user-cleared/default folder won't pin itself in UserDefaults.
        if prefs.isDefault {
            if store.removeValue(forKey: path) != nil {
                scheduleFlush()
            }
            return
        }
        if store[path] == prefs { return }
        store[path] = prefs
        scheduleFlush()
    }

    private func normalize(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        if let decoded = try? JSONDecoder().decode([String: FolderPrefs].self, from: data) {
            store = decoded
        }
    }

    /// Coalesce rapid changes (e.g. flipping view modes) into one write per ~250ms.
    private func scheduleFlush() {
        guard !saveScheduled else { return }
        saveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.flush()
        }
    }

    private func flush() {
        saveScheduled = false
        guard let data = try? JSONEncoder().encode(store) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
