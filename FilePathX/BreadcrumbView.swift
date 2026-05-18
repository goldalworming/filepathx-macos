import SwiftUI

struct BreadcrumbView: View {
    @ObservedObject var tab: BrowserTab
    @State private var editing: Bool = false
    @State private var editText: String = ""
    @FocusState private var editFocused: Bool

    private var segments: [(name: String, url: URL)] {
        let parts = tab.url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        var result: [(String, URL)] = [("Macintosh HD", URL(fileURLWithPath: "/"))]
        var accum = URL(fileURLWithPath: "/")
        for part in parts {
            accum.appendPathComponent(part)
            result.append((part, accum))
        }
        return result
    }

    var body: some View {
        if editing {
            TextField("", text: $editText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .focused($editFocused)
                .onSubmit { commit() }
                .onExitCommand { cancel() }
                .onAppear {
                    DispatchQueue.main.async { editFocused = true }
                }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { idx, seg in
                        Button {
                            if seg.url != tab.url {
                                tab.navigate(to: seg.url)
                            }
                        } label: {
                            Text(seg.name)
                                .font(.system(size: 12))
                                .foregroundStyle(idx == segments.count - 1 ? Color.primary : Color.secondary)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)

                        if idx < segments.count - 1 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    // Tap-to-edit area filling the trailing space.
                    Color.clear
                        .frame(maxWidth: .infinity, minHeight: 22)
                        .contentShape(Rectangle())
                        .onTapGesture { startEdit() }
                }
                .padding(.horizontal, 4)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { startEdit() }
        }
    }

    private func startEdit() {
        editText = tab.url.path
        editing = true
    }

    private func commit() {
        let raw = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        editing = false
        editText = ""
        guard !raw.isEmpty else { return }
        let expanded = NSString(string: raw).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        tab.navigate(to: url)
    }

    private func cancel() {
        editing = false
        editText = ""
    }
}
