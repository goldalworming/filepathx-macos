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

    /// Header clicks arrive here. `BrowserTab` owns the actual sort (it keeps
    /// folders first), so we just translate the comparator back and forth.
    private var sortOrderBinding: Binding<[KeyPathComparator<FileEntry>]> {
        Binding(
            get: { tab.tableSortOrder },
            set: { newValue in
                if !isActive { onActivate() }
                tab.applyTableSortOrder(newValue)
            }
        )
    }

    var body: some View {
        Table(tab.entries, selection: selectionBinding, sortOrder: sortOrderBinding) {
            TableColumn("Name", value: \.name) { entry in
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
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .opacity(entry.isHidden ? 0.8 : 1.0)
                // Explicit selection handling: Table's NSTableView under the
                // hood doesn't always receive clicks on cell content (it
                // mostly works for files but is unreliable for folder names),
                // so we drive the selection binding directly.
                .onTapGesture(count: 2) {
                    if !isActive { onActivate() }
                    tab.open(entry)
                }
                .onTapGesture {
                    if !isActive { onActivate() }
                    let flags = NSEvent.modifierFlags
                    if flags.contains(.command) {
                        if tab.selection.contains(entry.id) {
                            tab.selection.remove(entry.id)
                        } else {
                            tab.selection.insert(entry.id)
                        }
                    } else if flags.contains(.shift), !tab.selection.isEmpty {
                        let ids = tab.entries.map(\.id)
                        let selectedIdx = ids.enumerated()
                            .filter { tab.selection.contains($0.element) }
                            .map(\.offset)
                        if let here = ids.firstIndex(of: entry.id),
                           let lo = selectedIdx.min(),
                           let hi = selectedIdx.max() {
                            let anchor = here >= hi ? lo : hi
                            let range = min(anchor, here)...max(anchor, here)
                            tab.selection = Set(range.map { ids[$0] })
                        } else {
                            tab.selection = [entry.id]
                        }
                    } else {
                        tab.selection = [entry.id]
                    }
                }
                .fileDragSource(dragURLs(for: entry))
            }
            .width(min: 180, ideal: 320)

            TableColumn("Kind", value: \.typeDescription) { entry in
                Text(entry.typeDescription)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .opacity(entry.isHidden ? 0.8 : 1.0)
            }
            .width(min: 80, ideal: 120, max: 200)

            TableColumn("Date Modified", value: \.modificationSortKey) { entry in
                Text(entry.displayDate)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .opacity(entry.isHidden ? 0.8 : 1.0)
            }
            .width(min: 140, ideal: 170, max: 220)

            TableColumn("Size", value: \.size) { entry in
                Text(entry.displaySize)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .opacity(entry.isHidden ? 0.8 : 1.0)
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
