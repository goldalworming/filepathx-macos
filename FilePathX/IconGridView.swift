import SwiftUI

struct IconGridView: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var tab: BrowserTab
    let iconSize: CGFloat
    let cellWidth: CGFloat
    let cellHeight: CGFloat
    let isActive: Bool
    var onActivate: () -> Void = {}

    @FocusState private var renameFocused: Bool

    // Marquee (rubber-band) selection state. Lives in the "grid" coordinate
    // space so it survives scrolling.
    @State private var marqueeStart: CGPoint? = nil
    @State private var marqueeCurrent: CGPoint? = nil
    @State private var marqueeBaseSelection: Set<FileEntry.ID> = []
    @State private var cellFrames: [FileEntry.ID: CGRect] = [:]

    private func dragURLs(for entry: FileEntry) -> [URL] {
        if tab.selection.contains(entry.id) && tab.selection.count > 1 {
            return tab.selectedURLs
        }
        return [entry.url]
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: cellWidth, maximum: cellWidth * 1.6), spacing: 6)]
    }

    private var marqueeRect: CGRect? {
        guard let s = marqueeStart, let c = marqueeCurrent else { return nil }
        return CGRect(x: min(s.x, c.x),
                      y: min(s.y, c.y),
                      width: abs(c.x - s.x),
                      height: abs(c.y - s.y))
    }

    var body: some View {
        GeometryReader { geo in
            gridContent(viewportHeight: geo.size.height)
                .onAppear { updateColumnCount(width: geo.size.width) }
                .onChange(of: geo.size.width) { w in updateColumnCount(width: w) }
        }
    }

    private func updateColumnCount(width: CGFloat) {
        // LazyVGrid with .adaptive(minimum: cellWidth) + spacing 6, inside 10pt padding.
        let usable = max(0, width - 20)
        let pitch = cellWidth + 6
        let cols = max(1, Int((usable + 6) / pitch))
        if tab.iconGridColumns != cols {
            tab.iconGridColumns = cols
        }
    }

    private func gridContent(viewportHeight: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    // Marquee gesture layer. Sits behind the grid so cell taps /
                    // drags win for cell-area events, while empty space hands
                    // events here for marquee + click-to-deselect.
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(minHeight: viewportHeight)
                        .gesture(marqueeGesture)
                        .onTapGesture {
                            if !isActive { onActivate() }
                            tab.selection.removeAll()
                        }

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                        ForEach(tab.entries) { entry in
                            GridCell(entry: entry,
                                 iconSize: iconSize,
                                 cellHeight: cellHeight,
                                 selected: tab.selection.contains(entry.id),
                                 panelIsActive: isActive,
                                 renaming: tab.renamingID == entry.id,
                                 batchActive: tab.batchActive && tab.selection.contains(entry.id),
                                 batchTyped: tab.batchTyped,
                                 batchChop: tab.batchChop,
                                 renameBinding: $tab.renameText,
                                 renameFocused: $renameFocused,
                                 onCommitRename: {
                                     tab.commitRename()
                                     app.transferFocusToActivePanel()
                                 },
                                 onCancelRename: {
                                     tab.cancelRename()
                                     app.transferFocusToActivePanel()
                                 })
                            .frame(width: cellWidth, height: cellHeight)
                            .opacity(entry.isHidden ? 0.8 : 1.0)
                            .background(
                                GeometryReader { cellGeo in
                                    Color.clear.preference(
                                        key: CellFramesKey.self,
                                        value: [entry.id: cellGeo.frame(in: .named("grid"))]
                                    )
                                }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                if !isActive { onActivate() }
                                tab.open(entry)
                            }
                            .onTapGesture {
                                if !isActive { onActivate() }
                                if NSEvent.modifierFlags.contains(.command) {
                                    if tab.selection.contains(entry.id) {
                                        tab.selection.remove(entry.id)
                                    } else {
                                        tab.selection.insert(entry.id)
                                    }
                                } else {
                                    tab.selection = [entry.id]
                                }
                            }
                            .contextMenu {
                                FileContextMenu(
                                    tab: tab,
                                    selectionIDs: tab.selection.contains(entry.id) ? tab.selection : [entry.id]
                                )
                            }
                            .fileDragSource(dragURLs(for: entry))
                        }
                    }

                    if let rect = marqueeRect, rect.width > 1 || rect.height > 1 {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.18))
                            .overlay(
                                Rectangle().strokeBorder(Color.accentColor.opacity(0.8),
                                                         lineWidth: 1)
                            )
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            .allowsHitTesting(false)
                    }
                }
                .coordinateSpace(name: "grid")
                .padding(10)
                .onPreferenceChange(CellFramesKey.self) { cellFrames = $0 }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .onChange(of: tab.renamingID) { new in
                guard new != nil else { return }
                DispatchQueue.main.async { renameFocused = true }
            }
            .onChange(of: tab.pendingScrollToID) { id in
                guard let id else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    proxy.scrollTo(id, anchor: .center)
                }
                tab.pendingScrollToID = nil
            }
        }
    }

    private var marqueeGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("grid"))
            .onChanged { value in
                if marqueeStart == nil {
                    if !isActive { onActivate() }
                    marqueeStart = value.startLocation
                    // Shift / Cmd held when the drag starts → add to existing
                    // selection. Otherwise the marquee replaces it.
                    let flags = NSEvent.modifierFlags
                    marqueeBaseSelection = (flags.contains(.shift) || flags.contains(.command))
                        ? tab.selection : []
                }
                marqueeCurrent = value.location
                guard let rect = marqueeRect else { return }
                var newSel = marqueeBaseSelection
                for (id, frame) in cellFrames where frame.intersects(rect) {
                    newSel.insert(id)
                }
                if newSel != tab.selection {
                    tab.selection = newSel
                }
            }
            .onEnded { _ in
                marqueeStart = nil
                marqueeCurrent = nil
                marqueeBaseSelection = []
            }
    }
}

private struct CellFramesKey: PreferenceKey {
    static var defaultValue: [FileEntry.ID: CGRect] = [:]
    static func reduce(value: inout [FileEntry.ID: CGRect],
                       nextValue: () -> [FileEntry.ID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct GridCell: View {
    let entry: FileEntry
    let iconSize: CGFloat
    let cellHeight: CGFloat
    let selected: Bool
    let panelIsActive: Bool
    let renaming: Bool
    let batchActive: Bool
    let batchTyped: String
    let batchChop: Int
    @Binding var renameBinding: String
    @FocusState.Binding var renameFocused: Bool
    var onCommitRename: () -> Void
    var onCancelRename: () -> Void

    /// Active panel: accent (blue) selection. Inactive panel: subdued gray.
    private var fillColor: Color {
        guard selected else { return .clear }
        return panelIsActive ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.18)
    }
    private var strokeColor: Color {
        guard selected else { return .clear }
        return panelIsActive ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.45)
    }

    var body: some View {
        VStack(spacing: 6) {
            FileIcon(url: entry.url, size: iconSize)
                .frame(height: iconSize)

            if renaming {
                TextField("", text: $renameBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .focused($renameFocused)
                    .onSubmit { onCommitRename() }
                    .onExitCommand { onCancelRename() }
            } else if batchActive {
                BatchRenameInline(entry: entry,
                                  typed: batchTyped,
                                  chop: batchChop,
                                  font: .system(size: 11))
            } else {
                Text(entry.name)
                    .font(.system(size: 11))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(fillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(strokeColor, lineWidth: 1)
        )
    }
}
