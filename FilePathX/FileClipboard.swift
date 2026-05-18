import Foundation

enum ClipboardOperation {
    case copy
    case cut
}

struct FileClipboard {
    var urls: [URL] = []
    var operation: ClipboardOperation = .copy

    var isEmpty: Bool { urls.isEmpty }
}
