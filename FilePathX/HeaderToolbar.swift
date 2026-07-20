import SwiftUI

/// Per-panel header toolbar, sits above that panel's tab bar.
/// The sidebar toggle and split toggle only render on the leftmost panel.
struct HeaderToolbar: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var panel: Panel
    @Binding var showSidebar: Bool
    let isLeftmost: Bool

    var body: some View {
        HStack(spacing: 6) {
            if isLeftmost {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showSidebar.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Toggle Sidebar")

                Divider().frame(height: 18)
            }

            if let tab = panel.activeTab {
                ActiveTabSection(tab: tab)
            } else {
                Spacer()
            }

            if isLeftmost {
                Divider().frame(height: 18)

                Button {
                    app.toggleSplit()
                } label: {
                    Image(systemName: app.isSplit ? "rectangle" : "rectangle.split.2x1")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help(app.isSplit ? "Single Pane" : "Split View (⌘\\)")
            }
        }
        .padding(.leading, (isLeftmost && !showSidebar) ? 80 : 8)   // traffic-light room
        .padding(.trailing, 10)
        .frame(height: 42)
        .background(.bar)
    }
}

private struct ActiveTabSection: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var tab: BrowserTab

    var body: some View {
        HStack(spacing: 6) {
            Button(action: tab.goBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .disabled(!tab.canGoBack)
            .help("Back")

            Button(action: tab.goForward) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .disabled(!tab.canGoForward)
            .help("Forward")

            Button(action: tab.goUp) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .disabled(!tab.canGoUp)
            .help("Enclosing Folder")

            Divider().frame(height: 18)

            Button {
                app.toggleBookmark(tab.url)
            } label: {
                Image(systemName: app.isBookmarked(tab.url) ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 13))
                    .foregroundStyle(app.isBookmarked(tab.url) ? Color.yellow : Color.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Toggle Bookmark")

            Button(action: tab.reload) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Refresh")

            Divider().frame(height: 18)

            BreadcrumbView(tab: tab)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 24)

            Menu {
                SortMenuItems(tab: tab)
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 13, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Sort By")

            Picker("", selection: $tab.viewMode) {
                ForEach(ViewMode.allCases) { mode in
                    Image(systemName: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .labelsHidden()
            .help("View Mode")
        }
    }
}
