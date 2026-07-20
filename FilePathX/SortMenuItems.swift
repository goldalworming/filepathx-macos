import SwiftUI

/// Shared "Sort By" menu contents: used by the header toolbar and by the
/// empty-area context menu, so the icon views (which have no clickable column
/// headers) can still change the sort.
struct SortMenuItems: View {
    @ObservedObject var tab: BrowserTab

    var body: some View {
        ForEach(SortColumn.allCases) { column in
            Button {
                tab.setSort(column: column)
            } label: {
                if tab.sortColumn == column {
                    Label(column.label,
                          systemImage: tab.sortAscending ? "chevron.up" : "chevron.down")
                } else {
                    Text(column.label)
                }
            }
        }

        Divider()

        Button("Ascending") { tab.setSort(column: tab.sortColumn, ascending: true) }
            .disabled(tab.sortAscending)
        Button("Descending") { tab.setSort(column: tab.sortColumn, ascending: false) }
            .disabled(!tab.sortAscending)
    }
}
