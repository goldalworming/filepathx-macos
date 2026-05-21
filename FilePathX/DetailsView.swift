import SwiftUI

struct DetailsView: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject var tab: BrowserTab
    let isActive: Bool
    var onActivate: () -> Void = {}

    @FocusState private var renameFocused: Bool

    /// Selection writes auto-activate the panel; reads always reflect the real
    /// `tab.selection` so Table keeps its scroll/cursor state across switches.
    /// URLs to vend when this row is dragged: the full multi-selection if the
    /// row is part of it, otherwise just this row.
    private func dragURLs(for entry: FileEntry) -> [URL] {
        if tab.selection.contains(entry.id) && tab.selection.count > 1 {
            return tab.selectedURLs
        }
        return [entry.url]
    }

    private var selectionBinding: Binding<Set<FileEntry.ID>> {
        Binding(
            get: { tab.selection },
            set: { newValue in
                if !isActive { onActivate() }
                tab.selection = newValue
            }
        )
    }

    var body: some View {
        Table(tab.entries, selection: selectionBinding) {
            TableColumn("Name") { entry in
                HStack(spacing: 6) {
                    FileIcon(url: entry.url, size: 16)
                    if tab.renamingID == entry.id {
                        TextField("", text: $tab.renameText)
                            .textFieldStyle(.roundedBorder)
                            .focused($renameFocused)
                            .onSubmit {
                                tab.commitRename()
                                // TextField hands up first responder on submit;
                                // restore it to the data table so the renamed
                                // row keeps its blue (active) highlight.
                                app.transferFocusToActivePanel()
                            }
                            .onExitCommand {
                                tab.cancelRename()
                                app.transferFocusToActivePanel()
                            }
                    } else if tab.batchActive, tab.selection.contains(entry.id) {
                        BatchRenameInline(entry: entry,
                                          typed: tab.batchTyped,
                                          chop: tab.batchChop)
                    } else {
                        Text(entry.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .fileDragSource(dragURLs(for: entry))
            }
            .width(min: 180, ideal: 320)

            TableColumn("Kind") { entry in
                Text(entry.typeDescription)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 80, ideal: 120, max: 200)

            TableColumn("Date Modified") { entry in
                Text(entry.displayDate)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 140, ideal: 170, max: 220)

            TableColumn("Size") { entry in
                Text(entry.displaySize)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 80, max: 120)
        }
        .tableStyle(.inset)
        // Render selection as "inactive" (gray) when this panel isn't active,
        // matching the macOS default for non-key controls.
        .environment(\.controlActiveState, isActive ? .key : .inactive)
        .contextMenu(forSelectionType: FileEntry.ID.self) { selected in
            FileContextMenu(tab: tab, selectionIDs: selected)
        } primaryAction: { selected in
            if !isActive { onActivate() }
            for id in selected {
                if let entry = tab.entries.first(where: { $0.id == id }) {
                    tab.open(entry)
                    break
                }
            }
        }
        .onChange(of: tab.renamingID) { new in
            guard new != nil else { return }
            DispatchQueue.main.async { renameFocused = true }
        }
        .onChange(of: tab.pendingScrollToID) { id in
            guard id != nil else { return }
            // The icon-grid path uses ScrollViewReader; for the Table we go
            // through AppKit's scrollRowToVisible via AppModel.
            app.scrollActiveSelectionIntoView()
            tab.pendingScrollToID = nil
        }
    }
}
