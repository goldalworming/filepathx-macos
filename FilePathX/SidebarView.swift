import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var app: AppModel

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
    }
}

private struct SidebarRow: View {
    @EnvironmentObject var app: AppModel
    let item: SidebarItem
    @State private var hovered = false

    var body: some View {
        Button {
            app.activeTab?.navigate(to: item.url)
        } label: {
            Label(item.name, systemImage: item.systemImage)
                .lineLimit(1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
