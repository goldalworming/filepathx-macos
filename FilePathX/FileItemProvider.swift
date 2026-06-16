import SwiftUI
import AppKit

/// Bypasses SwiftUI's `.onDrag`, which always re-vends file URLs through a
/// promise that materializes the file under `~/Library/Caches/com.apple.SwiftUI.Drag-…`.
/// Instead we start an AppKit `beginDraggingSession` with the URL as a
/// `NSPasteboardWriting`, so receivers get the real `file://` URL.
struct FileDragSource: ViewModifier {
    let urls: () -> [URL]
    @State private var dragging = false

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .global)
                    .onChanged { _ in
                        guard !dragging else { return }
                        dragging = true
                        let list = urls()
                        guard !list.isEmpty else { return }
                        AppKitFileDrag.begin(urls: list)
                    }
                    .onEnded { _ in
                        dragging = false
                    }
            )
    }
}

extension View {
    func fileDragSource(_ urls: @autoclosure @escaping () -> [URL]) -> some View {
        modifier(FileDragSource(urls: urls))
    }
}

enum AppKitFileDrag {
    static func begin(urls: [URL]) {
        guard let window = NSApp.keyWindow,
              let contentView = window.contentView,
              let event = NSApp.currentEvent else { return }

        let size = NSSize(width: 64, height: 64)
        let mouse = contentView.convert(event.locationInWindow, from: nil)

        var items: [NSDraggingItem] = []
        for (idx, url) in urls.enumerated() {
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let offset = CGFloat(idx) * 6
            item.draggingFrame = NSRect(
                x: mouse.x - size.width / 2 + offset,
                y: mouse.y - size.height / 2 - offset,
                width: size.width,
                height: size.height)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            item.imageComponentsProvider = {
                let component = NSDraggingImageComponent(key: .icon)
                component.contents = icon
                component.frame = NSRect(origin: .zero, size: size)
                return [component]
            }
            items.append(item)
        }

        contentView.beginDraggingSession(with: items,
                                         event: event,
                                         source: FileDragSourceObject.shared)
    }
}

final class FileDragSourceObject: NSObject, NSDraggingSource {
    static let shared = FileDragSourceObject()

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        switch context {
        case .outsideApplication: return .copy
        case .withinApplication:  return [.copy, .move]
        @unknown default:         return .copy
        }
    }
}
