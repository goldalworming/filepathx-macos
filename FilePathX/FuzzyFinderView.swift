import SwiftUI

/// The ⌘F search dialog, drawn over the panel that opened it — same layout as
/// the C source's overlay: search field on top, scored results below, footer
/// with counts and the indexing spinner.
struct FuzzyFinderView: View {
    @ObservedObject var finder: FuzzyFinder
    @ObservedObject var tab: BrowserTab

    @FocusState private var queryFocused: Bool

    private let rowHeight: CGFloat = 28

    var body: some View {
        ZStack(alignment: .top) {
            // Dim + click-outside-to-close.
            Color.black.opacity(0.45)
                .contentShape(Rectangle())
                .onTapGesture { finder.close() }

            VStack(spacing: 0) {
                queryRow
                Divider()
                resultList
                Divider()
                footer
            }
            .frame(maxWidth: 720)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
            )
            .shadow(radius: 24, y: 8)
            .padding(.horizontal, 24)
            .padding(.top, 20)
        }
        .onAppear { queryFocused = true }
    }

    // MARK: - Query

    private var queryRow: some View {
        HStack(spacing: 8) {
            if finder.isScanning {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16)
            } else {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
            }

            TextField("Type to filter…", text: $finder.query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($queryFocused)
                // Return is also handled by the key monitor; this covers the
                // case where the field consumes it first.
                .onSubmit { finder.activate(in: tab) }

            Toggle("Recursive", isOn: Binding(
                get: { finder.recursive },
                set: { _ in finder.toggleRecursive() }
            ))
            .toggleStyle(.checkbox)
            .help("Search subfolders too (⌘R)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Results

    private var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(finder.results.enumerated()), id: \.element.id) { idx, result in
                        row(result, index: idx)
                            .id(result.id)
                    }
                }
            }
            .frame(height: rowHeight * 12)
            .onChange(of: finder.selected) { _ in
                guard let id = finder.currentResult?.id else { return }
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    private func row(_ result: FuzzyFinder.Result, index: Int) -> some View {
        let isSelected = index == finder.selected
        return HStack(spacing: 8) {
            FileIcon(url: result.entry.url, size: 16)
            HighlightedName(name: result.entry.name, marks: result.marks)
                .lineLimit(1)
                .truncationMode(.middle)
            if !result.entry.relative.isEmpty {
                Text(result.entry.relative)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.30) : .clear)
        .contentShape(Rectangle())
        .onTapGesture {
            finder.selected = index
            finder.activate(in: tab)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            if finder.isScanning {
                Text("Indexing…  \(finder.indexCount) items  ·  \(finder.results.count) matches")
                Spacer()
                Button("Stop") { finder.stopScan() }
                    .buttonStyle(.link)
            } else {
                Text("\(finder.results.count) / \(finder.indexCount)  ·  ↑↓ navigate  ·  ⏎ open  ·  ⌘R recursive  ·  esc close")
                Spacer()
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

/// Draws a name with the fuzzy-matched characters tinted, the way the C
/// renderer highlights per-character marks.
private struct HighlightedName: View {
    let name: String
    let marks: [Int]

    var body: some View {
        let markSet = Set(marks)
        let chars = Array(name)
        return chars.indices.reduce(Text("")) { acc, i in
            let piece = Text(String(chars[i]))
            return acc + (markSet.contains(i)
                          ? piece.foregroundColor(.yellow).bold()
                          : piece)
        }
        .font(.system(size: 12))
    }
}
