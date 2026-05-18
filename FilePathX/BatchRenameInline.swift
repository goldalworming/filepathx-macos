import SwiftUI

/// Per-row composite rendered when `BrowserTab.batchActive` is true and the row
/// is selected. Mirrors the C source's batch rename UI:
/// `<original stem minus chop>` (primary) + `<typed>` (green) + cursor + `.<ext>` (dim).
struct BatchRenameInline: View {
    let entry: FileEntry
    let typed: String
    let chop: Int
    var font: Font = .system(size: 12)

    private var stemAfterChop: String {
        let stem = (entry.name as NSString).deletingPathExtension
        let keep = max(0, stem.count - chop)
        return String(stem.prefix(keep))
    }

    private var extWithDot: String {
        let ext = (entry.name as NSString).pathExtension
        return ext.isEmpty ? "" : ".\(ext)"
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(stemAfterChop)
                .foregroundStyle(.primary)
            Text(typed)
                .foregroundStyle(Color.green)
            BlinkingCursor()
                .padding(.horizontal, 1)
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
