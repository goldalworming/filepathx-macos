import SwiftUI
import AppKit

/// Horizontal scroll container that also redirects vertical mouse-wheel /
/// trackpad scroll into horizontal movement. Trackpad two-finger horizontal
/// swipe is left to the default `NSScrollView` behavior.
///
/// The hosted SwiftUI content lives inside an `NSHostingView`, so any
/// `@EnvironmentObject` it relies on must be injected into `content` by the
/// caller (e.g. `.environmentObject(app)`).
struct HorizontalWheelScroller<Content: View>: NSViewRepresentable {
    @ViewBuilder var content: () -> Content

    func makeNSView(context: Context) -> WheelRedirectScrollView {
        let scroll = WheelRedirectScrollView()
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.horizontalScrollElasticity = .allowed
        scroll.verticalScrollElasticity = .none
        scroll.usesPredominantAxisScrolling = false

        let host = NSHostingView(rootView: content())
        host.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = host

        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            host.bottomAnchor.constraint(equalTo: scroll.contentView.bottomAnchor),
            host.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            // Intentionally no trailing/width constraint — the HStack drives
            // its own intrinsic width so we can scroll horizontally.
        ])

        return scroll
    }

    func updateNSView(_ nsView: WheelRedirectScrollView, context: Context) {
        if let host = nsView.documentView as? NSHostingView<Content> {
            host.rootView = content()
        }
    }
}

final class WheelRedirectScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        // Trackpad horizontal swipe → let default behavior handle.
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            super.scrollWheel(with: event)
            return
        }

        guard let doc = documentView else {
            super.scrollWheel(with: event)
            return
        }

        let visible = contentView.bounds
        let maxX = max(0, doc.frame.width - visible.width)
        guard maxX > 0 else { return }

        // Mouse wheels report `scrollingDeltaY` in lines (usually ±1 per click)
        // so they need a big amplifier; trackpads report pixel-precise deltas
        // that need only a mild boost to feel snappy.
        let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 2.5 : 40.0

        var origin = visible.origin
        // Scroll-up (perceived) → tabs left, scroll-down → tabs right.
        origin.x = max(0, min(maxX, origin.x - event.scrollingDeltaY * multiplier))
        contentView.scroll(to: origin)
        reflectScrolledClipView(contentView)
    }
}
