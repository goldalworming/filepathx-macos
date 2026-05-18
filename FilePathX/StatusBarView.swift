import SwiftUI

struct StatusBarView: View {
    @ObservedObject var tab: BrowserTab

    private var summary: String {
        let total = tab.entries.count
        let sel = tab.selection.count
        if sel == 0 {
            return "\(total) item\(total == 1 ? "" : "s")"
        }
        let bytes = tab.selectedEntries
            .filter { !$0.isDirectory }
            .reduce(Int64(0)) { $0 + $1.size }
        let sizeStr = bytes > 0
            ? " — \(FileEntry.byteFormatter.string(fromByteCount: bytes))"
            : ""
        return "\(sel) of \(total) selected\(sizeStr)"
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(summary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(tab.url.path)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 10)
        .frame(height: 22)
        .background(.bar)
    }
}
