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

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: cellWidth, maximum: cellWidth * 1.6), spacing: 6)]
    }

    var body: some View {
        ScrollView {
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
                             onCommitRename: tab.commitRename,
                             onCancelRename: tab.cancelRename)
                        .frame(width: cellWidth, height: cellHeight)
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
                        .draggable(entry.url) {
                            VStack(spacing: 4) {
                                FileIcon(url: entry.url, size: 48)
                                Text(entry.name)
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(NSColor.controlBackgroundColor))
                                    .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                            )
                        }
                }
            }
            .padding(10)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .contentShape(Rectangle())
        .onTapGesture {
            if !isActive { onActivate() }
            tab.selection.removeAll()
        }
        .onChange(of: tab.renamingID) { new in
            guard new != nil else { return }
            DispatchQueue.main.async { renameFocused = true }
        }
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
