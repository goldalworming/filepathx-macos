import SwiftUI
import AppKit
import QuickLookThumbnailing

struct FileIcon: View {
    let url: URL
    let size: CGFloat

    @StateObject private var loader = ThumbnailLoader()

    var body: some View {
        Group {
            if let thumb = loader.image {
                Image(nsImage: thumb)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: max(2, size * 0.04)))
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size, height: size)
            }
        }
        .onAppear { tryLoad() }
        .onChange(of: url) { _ in tryLoad() }
        .onChange(of: size) { _ in tryLoad() }
    }

    private func tryLoad() {
        // Skip directories (folder icon is what we want anyway) and very small
        // sizes (details/table view at 16px — QL overhead not worth it).
        guard size >= 24 else { return }
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        guard !isDir else { return }
        loader.load(url: url, size: size)
    }
}

// MARK: - Cache + loader

private final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()
    init() { cache.countLimit = 512 }

    func image(forKey key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }
    func set(_ image: NSImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
}

@MainActor
final class ThumbnailLoader: ObservableObject {
    @Published var image: NSImage?
    private var currentKey: String?

    func load(url: URL, size: CGFloat) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let key = "\(url.path)|\(Int(size * scale))"

        if let cached = ThumbnailCache.shared.image(forKey: key) {
            if currentKey != key {
                currentKey = key
                image = cached
            }
            return
        }
        if currentKey == key { return }
        currentKey = key
        image = nil

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: size, height: size),
            scale: scale,
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] rep, _ in
            guard let rep else { return }
            let nsImage = rep.nsImage
            Task { @MainActor [weak self] in
                ThumbnailCache.shared.set(nsImage, forKey: key)
                guard let self, self.currentKey == key else { return }
                self.image = nsImage
            }
        }
    }
}
