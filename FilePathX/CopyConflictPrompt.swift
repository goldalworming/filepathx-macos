import AppKit

/// Per-batch conflict resolver for copy / move. Shows a Finder-style alert
/// (Replace / Keep Both / Skip) with an "Apply to all" checkbox so the user
/// answers at most once per batch when several items collide.
@MainActor
final class CopyConflictPrompter {
    private var sticky: FileSystemService.ConflictAction? = nil

    func resolve(targetURL: URL, isMove: Bool = false) -> FileSystemService.ConflictAction {
        if let sticky { return sticky }

        let alert = NSAlert()
        let name = targetURL.lastPathComponent
        alert.messageText = "An item named \u{201C}\(name)\u{201D} already exists in this location."
        alert.informativeText = isMove
            ? "Do you want to replace it with the one you're moving?"
            : "Do you want to replace it with the one you're copying?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Replace")       // .alertFirstButtonReturn
        alert.addButton(withTitle: "Keep Both")     // .alertSecondButtonReturn
        alert.addButton(withTitle: "Skip")          // .alertThirdButtonReturn

        let checkbox = NSButton(
            checkboxWithTitle: "Apply to all",
            target: nil,
            action: nil
        )
        checkbox.state = .off
        alert.accessoryView = checkbox

        let response = alert.runModal()
        let action: FileSystemService.ConflictAction
        switch response {
        case .alertFirstButtonReturn:  action = .replace
        case .alertSecondButtonReturn: action = .keepBoth
        default:                       action = .skip
        }
        if checkbox.state == .on { sticky = action }
        return action
    }
}
