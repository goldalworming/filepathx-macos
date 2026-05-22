import Foundation
import AppKit

enum FileSystemService {

    private static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey,
        .fileSizeKey,
        .contentModificationDateKey,
        .localizedTypeDescriptionKey,
        .nameKey,
    ]
    private static let resourceKeySet = Set(resourceKeys)

    static func contents(of url: URL, includeHidden: Bool = false) -> [FileEntry] {
        let opts: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: resourceKeys,
            options: opts
        ) else {
            return []
        }
        return urls.compactMap { entry(for: $0) }
    }

    static func entry(for url: URL) -> FileEntry? {
        guard let values = try? url.resourceValues(forKeys: resourceKeySet) else { return nil }
        return FileEntry(
            url: url,
            name: values.name ?? url.lastPathComponent,
            isDirectory: values.isDirectory ?? false,
            size: Int64(values.fileSize ?? 0),
            modificationDate: values.contentModificationDate,
            typeDescription: values.localizedTypeDescription ?? (values.isDirectory == true ? "Folder" : "File")
        )
    }

    @discardableResult
    static func trash(urls: [URL]) -> Int {
        var ok = 0
        for url in urls {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                ok += 1
            } catch {
                NSLog("trash failed for \(url.path): \(error.localizedDescription)")
            }
        }
        if ok > 0 { trashSound?.play() }
        return ok
    }

    private static let trashSound: NSSound? = NSSound(
        contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/finder/move to trash.aif",
        byReference: true
    )

    @discardableResult
    static func rename(_ url: URL, to newName: String) -> URL? {
        let parent = url.deletingLastPathComponent()
        let target = parent.appendingPathComponent(newName)
        guard target != url else { return url }
        do {
            try FileManager.default.moveItem(at: url, to: target)
            return target
        } catch {
            NSLog("rename failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// What to do when a copy/move would overwrite an existing item.
    enum ConflictAction { case replace, keepBoth, skip }

    @discardableResult
    static func copy(urls: [URL], to destination: URL,
                     onConflict: (URL) -> ConflictAction = { _ in .keepBoth }) -> Int {
        transfer(urls: urls, to: destination, move: false, onConflict: onConflict)
    }

    @discardableResult
    static func move(urls: [URL], to destination: URL,
                     onConflict: (URL) -> ConflictAction = { _ in .keepBoth }) -> Int {
        transfer(urls: urls, to: destination, move: true, onConflict: onConflict)
    }

    /// Shared backbone for copy/move. Same-folder copy auto-renames (the
    /// classic "foo 2.txt" duplicate behavior). Cross-folder collisions ask
    /// the caller via `onConflict`. Same-folder move is a no-op.
    private static func transfer(urls: [URL], to destination: URL, move: Bool,
                                 onConflict: (URL) -> ConflictAction) -> Int {
        let fm = FileManager.default
        var ok = 0
        for source in urls {
            let sameFolder = source.deletingLastPathComponent().standardizedFileURL.path
                == destination.standardizedFileURL.path
            if move && sameFolder { continue }

            let naive = destination.appendingPathComponent(source.lastPathComponent)
            let exists = fm.fileExists(atPath: naive.path)

            let target: URL?
            if !exists {
                target = naive
            } else if sameFolder {
                target = uniqueDestination(in: destination, name: source.lastPathComponent)
            } else {
                switch onConflict(naive) {
                case .replace:
                    do { try fm.removeItem(at: naive) }
                    catch {
                        NSLog("replace: removeItem failed: \(error.localizedDescription)")
                        continue
                    }
                    target = naive
                case .keepBoth:
                    target = uniqueDestination(in: destination, name: source.lastPathComponent)
                case .skip:
                    target = nil
                }
            }

            guard let dest = target else { continue }
            do {
                if move {
                    try fm.moveItem(at: source, to: dest)
                } else {
                    try fm.copyItem(at: source, to: dest)
                }
                ok += 1
            } catch {
                NSLog("\(move ? "move" : "copy") failed: \(error.localizedDescription)")
            }
        }
        return ok
    }

    @discardableResult
    static func createFolder(in parent: URL, baseName: String = "untitled folder") -> URL? {
        let target = uniqueDestination(in: parent, name: baseName)
        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            return target
        } catch {
            NSLog("createFolder failed: \(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    static func createFile(in parent: URL, baseName: String = "untitled file") -> URL? {
        let target = uniqueDestination(in: parent, name: baseName)
        if FileManager.default.createFile(atPath: target.path, contents: nil) {
            return target
        }
        return nil
    }

    static func uniqueDestination(in parent: URL, name: String) -> URL {
        let fm = FileManager.default
        var target = parent.appendingPathComponent(name)
        if !fm.fileExists(atPath: target.path) { return target }

        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var i = 2
        while true {
            let candidate: String
            if ext.isEmpty {
                candidate = "\(stem) \(i)"
            } else {
                candidate = "\(stem) \(i).\(ext)"
            }
            target = parent.appendingPathComponent(candidate)
            if !fm.fileExists(atPath: target.path) { return target }
            i += 1
            if i > 9999 { return target }
        }
    }

    static func revealInFinder(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func openInTerminal(_ url: URL) {
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: terminal,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}
