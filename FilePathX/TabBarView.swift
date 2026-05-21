import SwiftUI

struct TabBarView: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var panel: Panel

    var body: some View {
        HStack(spacing: 4) {
            HorizontalWheelScroller {
                HStack(spacing: 4) {
                    ForEach(panel.tabs) { tab in
                        TabItemView(panel: panel, tab: tab)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .environmentObject(app)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 18)

            Button {
                panel.openTab()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("New Tab (⌘T)")
        }
        .padding(.horizontal, 6)
        .frame(height: 32)
        .background(.bar)
    }
}

private struct TabItemView: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var panel: Panel
    @ObservedObject var tab: BrowserTab
    @State private var hovered = false

    var isActive: Bool { panel.activeTabID == tab.id }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.system(size: 11))
                .foregroundStyle(isActive ? Color.accentColor : .secondary)

            Text(tab.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            if hovered || isActive {
                Button {
                    panel.closeTab(id: tab.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 14, height: 14)
                        .background(
                            Circle().fill(Color.secondary.opacity(hovered ? 0.18 : 0))
                        )
                }
                .buttonStyle(.borderless)
                .help("Close Tab (⌘W)")
            } else {
                Color.clear.frame(width: 14, height: 14)
            }
        }
        .padding(.horizontal, 8)
        .frame(width: 170, height: 24)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive
                      ? Color.accentColor.opacity(0.18)
                      : (hovered ? Color.secondary.opacity(0.12) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isActive ? Color.accentColor.opacity(0.55) : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            panel.activeTabID = tab.id
            // The new tab's NSTableView mounts asynchronously; wait one runloop
            // tick before grabbing first responder so it actually exists.
            app.transferFocusToActivePanel()
        }
        .onHover { hovered = $0 }
    }
}
