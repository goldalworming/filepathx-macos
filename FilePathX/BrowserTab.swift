import Foundation
import Combine
import AppKit

@MainActor
final class BrowserTab: ObservableObject, Identifiable {
    let id = UUID()

    @Published var url: URL
    @Published private(set) var entries: [FileEntry] = []
    @Published var viewMode: ViewMode = .details {
        didSet { savePrefsIfNeeded() }
    }
    @Published var selection: Set<FileEntry.ID> = []

    @Published var sortColumn: SortColumn = .name {
        didSet { savePrefsIfNeeded() }
    }
    @Published var sortAscending: Bool = true {
        didSet { savePrefsIfNeeded() }
    }

    /// How many columns the icon grid is currently showing (kept in sync by
    /// `IconGridView` via GeometryReader). Used by the keyboard monitor so
    /// ↑/↓ moves a whole row in icon modes.
    @Published var iconGridColumns: Int = 1

    /// Set while we're applying persisted prefs to avoid re-saving them.
    private var applyingPrefs = false

    @Published var renamingID: FileEntry.ID? = nil
    @Published var renameText: String = ""

    /// Set before `reload()` runs so that, once entries arrive, we can auto-
    /// select the entry whose name matches (e.g. for "go up to parent" we want
    /// the folder we came from to stay focused).
    private var pendingFocusName: String? = nil

    // Inline batch rename state (C-source style): each selected row shows
    // `<original stem minus chop><typed><cursor>.<ext>`.
    @Published var batchActive: Bool = false
    @Published var batchTyped: String = ""
    @Published var batchChop: Int = 0

    private var history: [URL] = []
    private var historyIndex: Int = 0
    private var loadTask: Task<Void, Never>? = nil

    var title: String {
        if url.path == "/" { return "Macintosh HD" }
        return url.lastPathComponent
    }

    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex < history.count - 1 }
    var canGoUp: Bool { url.path != "/" }

    /// Becomes true after the first `reload()` runs for this tab. We defer the
    /// initial load until `BrowserView.onAppear` so restored sessions with
    /// many tabs don't scan every directory at launch — only the currently
    /// active tab pays the I/O cost up front.
    private var hasLoaded = false

    init(url: URL, autoLoad: Bool = true) {
        self.url = url
        self.history = [url]
        self.historyIndex = 0
        applyPrefs(for: url)
        if autoLoad { loadIfNeeded() }
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        reload()
    }

    /// Loads persisted view-mode / sort prefs for `url` (or applies defaults).
    /// The `applyingPrefs` guard prevents the didSet observers from writing
    /// the same values back to disk.
    private func applyPrefs(for url: URL) {
        applyingPrefs = true
        defer { applyingPrefs = false }
        let prefs = FolderPreferences.shared.prefs(for: url) ?? .default
        viewMode = prefs.viewMode
        sortColumn = prefs.sortColumn
        sortAscending = prefs.sortAscending
    }

    private func savePrefsIfNeeded() {
        guard !applyingPrefs else { return }
        FolderPreferences.shared.save(
            FolderPrefs(viewMode: viewMode,
                        sortColumn: sortColumn,
                        sortAscending: sortAscending),
            for: url
        )
    }

    // MARK: - Navigation

    func navigate(to newURL: URL, focusName: String? = nil) {
        var resolved = newURL
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDir)
        guard exists else {
            NSSound.beep()
            return
        }
        if !isDir.boolValue {
            FileSystemService.open(resolved)
            return
        }
        resolved.standardize()

        if historyIndex < history.count - 1 {
            history.removeSubrange((historyIndex + 1)..<history.count)
        }
        if history.last != resolved {
            history.append(resolved)
            historyIndex = history.count - 1
        }
        url = resolved
        selection.removeAll()
        pendingFocusName = focusName
        applyPrefs(for: resolved)
        reload()
        SessionStore.shared.scheduleSave()
    }

    func goBack() {
        guard canGoBack else { return }
        historyIndex -= 1
        url = history[historyIndex]
        selection.removeAll()
        applyPrefs(for: url)
        reload()
        SessionStore.shared.scheduleSave()
    }

    func goForward() {
        guard canGoForward else { return }
        historyIndex += 1
        url = history[historyIndex]
        selection.removeAll()
        applyPrefs(for: url)
        reload()
        SessionStore.shared.scheduleSave()
    }

    func goUp() {
        guard canGoUp else { return }
        let comingFrom = url.lastPathComponent
        let parent = url.deletingLastPathComponent()
        navigate(to: parent, focusName: comingFrom)
    }

    // MARK: - Loading

    func reload() {
        hasLoaded = true
        loadTask?.cancel()
        let target = url
        loadTask = Task { [weak self] in
            let loaded: [FileEntry] = await Task.detached(priority: .userInitiated) {
                FileSystemService.contents(of: target)
            }.value

            if Task.isCancelled { return }
            await MainActor.run {
                guard let self else { return }
                guard self.url == target else { return }
                self.entries = self.applySort(loaded)
                if let name = self.pendingFocusName,
                   let entry = self.entries.first(where: { $0.name == name }) {
                    self.selection = [entry.id]
                } else if self.selection.isEmpty, let first = self.entries.first {
                    // No explicit focus target and nothing selected → focus first row
                    // so the keyboard user always has somewhere to arrow-from.
                    self.selection = [first.id]
                }
                self.pendingFocusName = nil
            }
        }
    }

    // MARK: - Sorting

    func setSort(column: SortColumn) {
        if sortColumn == column {
            sortAscending.toggle()
        } else {
            sortColumn = column
            sortAscending = true
        }
        entries = applySort(entries)
    }

    private func applySort(_ items: [FileEntry]) -> [FileEntry] {
        let cmp: (FileEntry, FileEntry) -> Bool
        switch sortColumn {
        case .name:
            cmp = { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .kind:
            cmp = { $0.typeDescription.localizedStandardCompare($1.typeDescription) == .orderedAscending }
        case .modified:
            cmp = { $0.modificationSortKey < $1.modificationSortKey }
        case .size:
            cmp = { $0.size < $1.size }
        }
        let sorted = items.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return sortAscending ? cmp(a, b) : !cmp(a, b)
        }
        return sorted
    }

    // MARK: - Selection helpers

    var selectedEntries: [FileEntry] {
        entries.filter { selection.contains($0.id) }
    }

    var selectedURLs: [URL] {
        selectedEntries.map(\.url)
    }

    // MARK: - Rename

    func beginRename(id: FileEntry.ID? = nil) {
        let target = id ?? selection.first
        guard let target,
              let entry = entries.first(where: { $0.id == target }) else { return }
        renameText = entry.name
        renamingID = target
    }

    /// Starts inline batch rename. Each selected row becomes an editor that shares
    /// the same `batchTyped` + `batchChop`. Falls back to single-file inline rename
    /// when only one item is selected.
    func beginBatchRename(urls: [URL]? = nil) {
        let targets = urls ?? selectedURLs
        guard targets.count >= 2 else {
            if let first = targets.first, let entry = entries.first(where: { $0.url == first }) {
                beginRename(id: entry.id)
            }
            return
        }
        batchActive = true
        batchTyped = ""
        batchChop = 0
    }

    func cancelBatchRename() {
        batchActive = false
        batchTyped = ""
        batchChop = 0
    }

    func commitBatchRename() {
        guard batchActive else { return }
        let active = batchActive
        let typed = batchTyped
        let chop = batchChop
        batchActive = false
        batchTyped = ""
        batchChop = 0

        guard active, typed.count > 0 || chop > 0 else { return }

        for entry in selectedEntries {
            let original = entry.name
            let stem = (original as NSString).deletingPathExtension
            let ext = (original as NSString).pathExtension
            let keep = max(0, stem.count - chop)
            let newStem = String(stem.prefix(keep)) + typed
            guard !newStem.isEmpty else { continue }
            let newName = ext.isEmpty ? newStem : "\(newStem).\(ext)"
            if newName != original {
                _ = FileSystemService.rename(entry.url, to: newName)
            }
        }
        reload()
    }

    func batchBackspace() {
        guard batchActive else { return }
        if !batchTyped.isEmpty {
            batchTyped.removeLast()
        } else {
            batchChop += 1
        }
    }

    func batchAppend(_ text: String) {
        guard batchActive else { return }
        batchTyped += text
    }

    func commitRename() {
        guard let id = renamingID,
              let entry = entries.first(where: { $0.id == id }) else {
            cancelRename()
            return
        }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        renamingID = nil
        renameText = ""
        guard !trimmed.isEmpty, trimmed != entry.name else { return }
        if FileSystemService.rename(entry.url, to: trimmed) != nil {
            reload()
        }
    }

    func cancelRename() {
        renamingID = nil
        renameText = ""
    }

    // MARK: - Open

    func open(_ entry: FileEntry) {
        if entry.isDirectory {
            navigate(to: entry.url)
        } else {
            FileSystemService.open(entry.url)
        }
    }

    func openSelection() {
        for entry in selectedEntries {
            if entry.isDirectory {
                navigate(to: entry.url)
                return
            }
            FileSystemService.open(entry.url)
        }
    }
}
