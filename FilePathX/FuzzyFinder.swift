import Foundation
import Combine

/// State behind the ⌘F fuzzy finder overlay, ported from the C source's
/// `g_ff_*` globals. One instance lives on `AppModel`; it remembers which
/// panel opened it so the overlay only dims that pane.
///
/// The index starts as the active tab's already-loaded entries (zero I/O).
/// Turning on Recursive kicks a cancellable background BFS that streams
/// results in, so the list stays usable while a deep tree is still walking.
@MainActor
final class FuzzyFinder: ObservableObject {

    struct Entry: Identifiable, Sendable {
        let url: URL
        let name: String
        /// Path from the search root to the parent folder, "" at the root.
        let relative: String
        let isDirectory: Bool
        var id: URL { url }
    }

    struct Result: Identifiable {
        let entry: Entry
        let score: Int
        let marks: [Int]
        var id: URL { entry.url }
    }

    nonisolated static let maxIndex = 20_000
    nonisolated static let maxResults = 200

    @Published private(set) var isOpen = false
    @Published var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            selected = 0
            refresh()
        }
    }
    /// Sticky across opens, like the C version's `g_ff_recursive`.
    @Published private(set) var recursive = false
    @Published private(set) var results: [Result] = []
    @Published var selected = 0
    @Published private(set) var isScanning = false
    @Published private(set) var indexCount = 0

    private(set) var panelID: Panel.ID?

    private var index: [Entry] = []
    private var root: URL = FileManager.default.homeDirectoryForCurrentUser
    private var scanTask: Task<Void, Never>?

    var currentResult: Result? {
        results.indices.contains(selected) ? results[selected] : nil
    }

    // MARK: - Open / close

    func open(tab: BrowserTab, panelID: Panel.ID) {
        self.panelID = panelID
        isOpen = true
        query = ""
        selected = 0
        root = tab.url
        buildIndex(from: tab)
        if recursive { startScan() } else { refresh() }
    }

    func close() {
        isOpen = false
        panelID = nil
        stopScan()
        index = []
        indexCount = 0
        results = []
        query = ""
        selected = 0
    }

    func toggleRecursive() {
        recursive.toggle()
        if recursive {
            startScan()
        } else {
            stopScan()
            // Fall back to the flat, already-loaded listing.
            index = index.filter { $0.relative.isEmpty }
            indexCount = index.count
            refresh()
        }
    }

    // MARK: - Selection

    func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        selected = min(max(0, selected + delta), results.count - 1)
    }

    /// Enter / click. Folders are entered; files are revealed and selected in
    /// the tab that opened the finder.
    func activate(in tab: BrowserTab) {
        guard let result = currentResult else { return }
        let entry = result.entry
        close()
        if entry.isDirectory {
            tab.navigate(to: entry.url)
        } else {
            tab.reveal(entry.url)
        }
    }

    // MARK: - Index

    private func buildIndex(from tab: BrowserTab) {
        index = tab.entries.prefix(Self.maxIndex).map {
            Entry(url: $0.url, name: $0.name, relative: "", isDirectory: $0.isDirectory)
        }
        indexCount = index.count
    }

    private func startScan() {
        stopScan()
        isScanning = true
        let root = self.root
        // Keep the flat listing we already have; the walk re-emits it anyway,
        // so start from empty to avoid duplicates.
        index = []
        indexCount = 0

        scanTask = Task { [weak self] in
            let stream = Self.walk(root: root)
            for await batch in stream {
                if Task.isCancelled { return }
                guard let self else { return }
                await MainActor.run {
                    guard self.index.count < Self.maxIndex else { return }
                    self.index.append(contentsOf: batch.prefix(Self.maxIndex - self.index.count))
                    self.indexCount = self.index.count
                    self.refresh()
                }
            }
            await MainActor.run { self?.isScanning = false }
        }
    }

    func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    /// Breadth-first walk off the main actor, emitting entries in batches so
    /// the UI updates while a big tree is still being read.
    private nonisolated static func walk(root: URL) -> AsyncStream<[Entry]> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                let fm = FileManager.default
                var frontier: [(url: URL, relative: String)] = [(root, "")]
                var emitted = 0
                var batch: [Entry] = []

                while !frontier.isEmpty, !Task.isCancelled, emitted < maxIndex {
                    var next: [(url: URL, relative: String)] = []
                    for dir in frontier {
                        if Task.isCancelled { break }
                        guard let urls = try? fm.contentsOfDirectory(
                            at: dir.url,
                            includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
                            options: []
                        ) else { continue }

                        for url in urls {
                            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .nameKey])
                            let name = values?.name ?? url.lastPathComponent
                            let isDir = values?.isDirectory ?? false
                            batch.append(Entry(url: url, name: name,
                                               relative: dir.relative, isDirectory: isDir))
                            emitted += 1
                            if batch.count >= 500 {
                                continuation.yield(batch)
                                batch = []
                            }
                            if emitted >= maxIndex { break }
                            if isDir, !shouldSkip(name) {
                                let rel = dir.relative.isEmpty ? name : "\(dir.relative)/\(name)"
                                next.append((url, rel))
                            }
                        }
                        if emitted >= maxIndex { break }
                    }
                    frontier = next
                }
                if !batch.isEmpty { continuation.yield(batch) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Heavy noise directories the C version skips too.
    private nonisolated static func shouldSkip(_ name: String) -> Bool {
        if name.hasPrefix(".") { return true }   // .git, .svn, .venv, …
        return ["node_modules", "__pycache__", "target", "build", "DerivedData"].contains(name)
    }

    // MARK: - Matching

    func refresh() {
        let q = query.trimmingCharacters(in: .whitespaces)
        var scored: [Result] = []
        scored.reserveCapacity(min(index.count, Self.maxResults))

        for entry in index {
            guard let m = FuzzyMatcher.match(name: entry.name, query: q) else { continue }
            // Directories rank a little higher, as in the C source.
            let score = m.score + (entry.isDirectory ? 5 : 0)
            scored.append(Result(entry: entry, score: score, marks: m.marks))
        }

        scored.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            return a.entry.name.localizedStandardCompare(b.entry.name) == .orderedAscending
        }
        results = Array(scored.prefix(Self.maxResults))
        selected = min(max(0, selected), max(0, results.count - 1))
    }
}
