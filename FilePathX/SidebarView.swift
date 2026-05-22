import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @EnvironmentObject var app: AppModel
    @State private var draggingBookmark: SidebarItem? = nil
    @State private var mouseUpMonitor: Any? = nil

    var body: some View {
        List {
            Section("Favorites") {
                ForEach(app.sidebarItems) { item in
                    SidebarRow(item: item)
                }
            }

            if !app.bookmarks.isEmpty {
                Section("Bookmarks") {
                    ForEach(app.bookmarks) { item in
                        SidebarRow(item: item)
                            .opacity(draggingBookmark?.id == item.id ? 0.4 : 1)
                            .onDrag {
                                draggingBookmark = item
                                return NSItemProvider(object: item.id.uuidString as NSString)
                            }
                            .onDrop(of: [.text], delegate: BookmarkDropDelegate(
                                target: item,
                                dragging: $draggingBookmark,
                                app: app
                            ))
                            .contextMenu {
                                Button("Remove Bookmark", role: .destructive) {
                                    app.removeBookmark(item)
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            // Space for traffic lights overlaid by `.windowStyle(.hiddenTitleBar)`.
            Color.clear.frame(height: 28)
        }
        // SwiftUI only fires `performDrop` when the user releases over a valid
        // drop target. If they release elsewhere, the dragged row would keep
        // its 40% opacity. Catch every mouse-up here and reset.
        .onAppear {
            mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { event in
                if draggingBookmark != nil {
                    DispatchQueue.main.async {
                        draggingBookmark = nil
                        app.persistBookmarks()
                    }
                }
                return event
            }
        }
        .onDisappear {
            if let m = mouseUpMonitor {
                NSEvent.removeMonitor(m)
                mouseUpMonitor = nil
            }
        }
    }
}

private struct SidebarRow: View {
    @EnvironmentObject var app: AppModel
    let item: SidebarItem
    @State private var hovered = false

    var body: some View {
        Label(item.name, systemImage: item.systemImage)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                app.activeTab?.navigate(to: item.url)
            }
            .onHover { hovered = $0 }
    }
}

/// Live-reorder: as the dragged row passes over another, swap them in place
/// so the list visually rearranges while the user drags.
private struct BookmarkDropDelegate: DropDelegate {
    let target: SidebarItem
    @Binding var dragging: SidebarItem?
    let app: AppModel

    func dropEntered(info: DropInfo) {
        guard let drag = dragging, drag.id != target.id else { return }
        guard let from = app.bookmarks.firstIndex(where: { $0.id == drag.id }),
              let to = app.bookmarks.firstIndex(where: { $0.id == target.id })
        else { return }
        if from != to {
            withAnimation(.easeInOut(duration: 0.15)) {
                app.bookmarks.move(fromOffsets: IndexSet([from]),
                                   toOffset: to > from ? to + 1 : to)
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        app.persistBookmarks()
        return true
    }
}
