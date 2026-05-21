import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var app: AppModel
    @State private var showSidebar: Bool = true
    @State private var sidebarWidth: CGFloat = 170

    var body: some View {
        HStack(spacing: 0) {
            if showSidebar {
                SidebarView()
                    .frame(width: sidebarWidth)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                ResizeHandle(width: $sidebarWidth, minWidth: 160, maxWidth: 320)
                    .transition(.opacity)
            }

            HStack(spacing: 0) {
                ForEach(Array(app.panels.enumerated()), id: \.element.id) { idx, panel in
                    PanelView(panel: panel,
                              showSidebar: $showSidebar,
                              isLeftmost: idx == 0,
                              isActive: idx == app.activePanelIndex)
                    if idx < app.panels.count - 1 {
                        Divider()
                    }
                }
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .task {
            // Move first responder onto the initial NSTableView so launch-time
            // keyboard nav works and the first row shows blue (focused).
            try? await Task.sleep(nanoseconds: 150_000_000)
            app.transferFocusToActivePanel()
        }
    }
}

private struct PanelView: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var panel: Panel
    @Binding var showSidebar: Bool
    let isLeftmost: Bool
    let isActive: Bool

    var body: some View {
        VStack(spacing: 0) {
            HeaderToolbar(panel: panel,
                          showSidebar: $showSidebar,
                          isLeftmost: isLeftmost)
            Divider()
            TabBarView(panel: panel)
            Divider()
            if let tab = panel.activeTab {
                BrowserView(tab: tab,
                            isActive: isActive,
                            onActivate: { app.setActivePanel(panel) })
                    .id(tab.id)
                    .dropDestination(for: URL.self) { urls, _ in
                        handleDrop(urls: urls, into: tab.url)
                        return true
                    }
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 400, maxWidth: .infinity)
        .overlay(
            // Accent border on active panel when split
            Rectangle()
                .strokeBorder(isActive && app.isSplit ? Color.accentColor.opacity(0.7) : .clear,
                              lineWidth: 2)
                .allowsHitTesting(false)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isActive { app.setActivePanel(panel) }
        }
    }

    private func handleDrop(urls: [URL], into destination: URL) {
        let moveMode = NSEvent.modifierFlags.contains(.command)
        let filtered = urls.filter { $0.deletingLastPathComponent() != destination }
        guard !filtered.isEmpty else { return }
        if moveMode {
            FileSystemService.move(urls: filtered, to: destination)
        } else {
            FileSystemService.copy(urls: filtered, to: destination)
        }
        panel.activeTab?.reload()
        // Also refresh the other panel if it might be the source.
        for other in app.panels where other.id != panel.id {
            if let activeURL = other.activeTab?.url,
               urls.contains(where: { $0.deletingLastPathComponent() == activeURL }) {
                other.activeTab?.reload()
            }
        }
    }
}

private struct ResizeHandle: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    @State private var startWidth: CGFloat?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(width: 1)
            Color.clear
                .frame(width: 8)
                .contentShape(Rectangle())
        }
        .onHover { hovering in
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if startWidth == nil { startWidth = width }
                    if let s = startWidth {
                        width = max(minWidth, min(maxWidth, s + value.translation.width))
                    }
                }
                .onEnded { _ in startWidth = nil }
        )
    }
}
