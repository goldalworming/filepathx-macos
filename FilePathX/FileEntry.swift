import Foundation

struct FileEntry: Identifiable, Hashable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: Int64
    let modificationDate: Date?
    let typeDescription: String

    var id: URL { url }

    var modificationSortKey: Date { modificationDate ?? .distantPast }

    var displaySize: String {
        if isDirectory { return "—" }
        return Self.byteFormatter.string(fromByteCount: size)
    }

    var displayDate: String {
        guard let date = modificationDate else { return "—" }
        return Self.dateFormatter.string(from: date)
    }

    static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
