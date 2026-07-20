import Foundation
import Combine
import AppKit

private func compare<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
    if a < b { return .orderedAscending }
    if b < a { return .orderedDescending }
    return .orderedSame
}

private extension ComparisonResult {
    var reversed: ComparisonResult {
        switch self {
        case .orderedAscending: return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame: return .orderedSame
        }
    }
}

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

    /// Set when something (e.g. ⌘N) needs the row/cell to scroll into view.
    /// `IconGridView` observes this via `ScrollViewReader`; the Details path
    /// is driven straight through AppKit on `NSTableView`.
    @Published var pendingScrollToID: FileEntry.ID? = nil

    /// Set while we're applying persisted prefs to avoid re-saving them.
    private var applyingPrefs = false

    @Published var renamingID: FileEntry.ID? = nil
    @Published var renameText: String = ""

    /// Set before `reload()` runs so that, once entries arrive, we can auto-
    /// select the entry whose name matches (e.g. for "go up to parent" we want
    /// the folder we came from to stay focused).
    private var pendingFocusName: String? = nil

    /// Set before a `reload()` triggered by ⌘N / ⌘⇧N. Once entries arrive we
    /// select that URL, scroll to it, and immediately enter rename. Removes
    /// the previous race against a fixed `asyncAfter` delay.
    private var pendingRenameURL: URL? = nil

    // Inline batch rename state (C-source style): every selected row shows the
    // same edit applied to its own name. `BatchEdit` carries the caret, so
    // ←/→/Home/End work like a normal text field.
    @Published var batchActive: Bool = false
    @Published var batchEdit = BatchEdit()

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

    /// Reload the directory and, once entries arrive, jump straight into
    /// rename for the given URL. Used by ⌘N / ⌘⇧N.
    func reloadAndRename(_ url: URL) {
        pendingRenameURL = url
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
                // Match by path so a folder URL like ".../foo/" (with the
                // trailing slash FileManager hands back from directory
                // enumeration) still matches ".../foo" returned by createFolder.
                if let url = self.pendingRenameURL,
                   let entry = self.entries.first(where: { $0.url.path == url.path }) {
                    self.selection = [entry.id]
                    self.pendingScrollToID = entry.id
                    self.renameText = entry.name
                    self.renamingID = entry.id
                } else if let name = self.pendingFocusName,
                          let entry = self.entries.first(where: { $0.name == name }) {
                    self.selection = [entry.id]
                } else if self.selection.isEmpty, let first = self.entries.first {
                    // No explicit focus target and nothing selected → focus first row
                    // so the keyboard user always has somewhere to arrow-from.
                    self.selection = [first.id]
                }
                self.pendingRenameURL = nil
                self.pendingFocusName = nil
            }
        }
    }

    // MARK: - Sorting

    /// Click-on-header behaviour: same column toggles direction, a new column
    /// starts ascending.
    func setSort(column: SortColumn) {
        if sortColumn == column {
            setSort(column: column, ascending: !sortAscending)
        } else {
            setSort(column: column, ascending: true)
        }
    }

    /// Explicit setter used by the sort menus and by the Table's `sortOrder`
    /// binding (where AppKit has already decided the direction for us).
    func setSort(column: SortColumn, ascending: Bool) {
        guard column != sortColumn || ascending != sortAscending else { return }
        applyingPrefs = true            // one write instead of two
        sortColumn = column
        applyingPrefs = false
        sortAscending = ascending       // didSet persists both values
        entries = applySort(entries)
    }

    /// Bridges our `SortColumn` + direction to the comparator array `Table`
    /// wants for its clickable, arrow-drawing headers.
    var tableSortOrder: [KeyPathComparator<FileEntry>] {
        let order: SortOrder = sortAscending ? .forward : .reverse
        switch sortColumn {
        case .name:
            return [KeyPathComparator(\FileEntry.name, order: order)]
        case .kind:
            return [KeyPathComparator(\FileEntry.typeDescription, order: order)]
        case .modified:
            return [KeyPathComparator(\FileEntry.modificationSortKey, order: order)]
        case .size:
            return [KeyPathComparator(\FileEntry.size, order: order)]
        }
    }

    /// Inverse of `tableSortOrder`: called when the user clicks a header.
    /// We re-sort ourselves rather than letting `Table` do it, so folders keep
    /// sorting ahead of files.
    func applyTableSortOrder(_ order: [KeyPathComparator<FileEntry>]) {
        guard let first = order.first else { return }
        let column: SortColumn
        switch first.keyPath {
        case \FileEntry.name: column = .name
        case \FileEntry.typeDescription: column = .kind
        case \FileEntry.modificationSortKey: column = .modified
        case \FileEntry.size: column = .size
        default: return
        }
        setSort(column: column, ascending: first.order == .forward)
    }

    private func applySort(_ items: [FileEntry]) -> [FileEntry] {
        // Returning a ComparisonResult (rather than a Bool we later negate)
        // keeps the ordering strict-weak in both directions — negating a `<`
        // predicate makes equal elements compare "less" both ways, which is an
        // invalid ordering and can trap inside sort().
        let cmp: (FileEntry, FileEntry) -> ComparisonResult
        switch sortColumn {
        case .name:
            cmp = { $0.name.localizedStandardCompare($1.name) }
        case .kind:
            cmp = { $0.typeDescription.localizedStandardCompare($1.typeDescription) }
        case .modified:
            cmp = { compare($0.modificationSortKey, $1.modificationSortKey) }
        case .size:
            cmp = { compare($0.size, $1.size) }
        }
        return items.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            var result = cmp(a, b)
            if !sortAscending { result = result.reversed }
            if result == .orderedSame {
                // Stable, direction-independent tiebreak so equal sizes/dates
                // don't shuffle between reloads.
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
            return result == .orderedAscending
        }
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
    /// the same `batchEdit`. Falls back to single-file inline rename
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
        batchEdit = BatchEdit()
    }

    func cancelBatchRename() {
        batchActive = false
        batchEdit = BatchEdit()
    }

    func commitBatchRename() {
        guard batchActive else { return }
        let edit = batchEdit
        batchActive = false
        batchEdit = BatchEdit()

        guard edit.hasChanges else { return }

        for entry in selectedEntries {
            let newName = edit.newName(for: entry.name)
            if newName != entry.name {
                _ = FileSystemService.rename(entry.url, to: newName)
            }
        }
        reload()
    }

    /// Mutates the shared edit, but only while batch rename is running.
    private func editBatch(_ body: (inout BatchEdit) -> Void) {
        guard batchActive else { return }
        body(&batchEdit)
    }

    func batchBackspace()          { editBatch { $0.deleteBackward() } }
    func batchAppend(_ text: String) { editBatch { $0.insert(text) } }
    func batchMoveLeft()           { editBatch { $0.moveLeft() } }
    func batchMoveRight()          { editBatch { $0.moveRight() } }
    func batchMoveToStart()        { editBatch { $0.moveToStart() } }
    func batchMoveToEnd()          { editBatch { $0.moveToEnd() } }

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
            // FileEntry.id == URL, so the old selection becomes stale after
            // rename. pendingFocusName re-binds selection to the new entry
            // once reload finishes.
            pendingFocusName = trimmed
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
