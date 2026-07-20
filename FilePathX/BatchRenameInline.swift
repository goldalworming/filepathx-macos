import SwiftUI

/// Per-row composite rendered when `BrowserTab.batchActive` is true and the row
/// is selected. Mirrors the C source's batch rename UI, with the caret drawn
/// wherever `BatchEdit` currently points:
/// `<stem before the edit>` (primary) + `<typed>` (green, split by the cursor)
/// + `<stem after the edit>` + `.<ext>` (dim).
struct BatchRenameInline: View {
    let entry: FileEntry
    let edit: BatchEdit
    var font: Font = .system(size: 12)

    private var stem: String { (entry.name as NSString).deletingPathExtension }

    private var extWithDot: String {
        let ext = (entry.name as NSString).pathExtension
        return ext.isEmpty ? "" : ".\(ext)"
    }

    var body: some View {
        let (head, tail) = edit.split(stem: stem)
        let (typedBefore, typedAfter) = edit.typedAroundCursor
        HStack(spacing: 0) {
            Text(head)
                .foregroundStyle(.primary)
            Text(typedBefore)
                .foregroundStyle(Color.green)
            BlinkingCursor()
                .padding(.horizontal, 1)
            Text(typedAfter)
                .foregroundStyle(Color.green)
            Text(tail)
                .foregroundStyle(.primary)
            Text(extWithDot)
                .foregroundStyle(.secondary)
        }
        .font(font)
        .lineLimit(1)
    }
}

private struct BlinkingCursor: View {
    @State private var visible = true

    var body: some View {
        Rectangle()
            .fill(Color.primary)
            .frame(width: 1, height: 14)
            .opacity(visible ? 1 : 0)
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 550_000_000)
                    visible.toggle()
                }
            }
    }
}
