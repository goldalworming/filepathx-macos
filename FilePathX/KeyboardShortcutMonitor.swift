import AppKit

/// Intercepts keyboard shortcuts globally for the app, before AppKit's
/// responder chain hands them to controls like NSTableView (which would
/// otherwise consume ⌘↑/⌘↓ to jump-select first/last row).
///
/// Events are passed through untouched when a text field/view holds focus,
/// so inline rename keeps working.
@MainActor
final class KeyboardShortcutMonitor {
    private weak var app: AppModel?
    private var monitor: Any?

    init(app: AppModel) {
        self.app = app
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(event) ?? event
            }
        }
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let app, let tab = app.activeTab else { return event }

        // Batch rename mode owns all keystrokes until commit/cancel.
        if tab.batchActive {
            return handleBatch(event, tab: tab)
        }

        // Don't intercept while a text input is *actively editing* — let it
        // handle arrows / typing. NSTextView is the actual editor (and also
        // serves as field editor for NSTextField), so checking that alone
        // skips real edit sessions without catching idle responders.
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
           textView.isEditable {
            return event
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Arrow up/down — let SwiftUI Table handle natively when it's first
        // responder (it scrolls-to-visible and updates selection via our
        // binding). For icon-grid mode there's no Table, so we route arrow
        // keys to active tab's selection ourselves.
        if event.keyCode == 126 || event.keyCode == 125 {
            let direction = event.keyCode == 125 ? 1 : -1
            if tab.viewMode != .details {
                if flags.isEmpty {
                    moveSelection(tab: tab, by: direction, extend: false)
                    return nil
                }
                if flags == .shift {
                    moveSelection(tab: tab, by: direction, extend: true)
                    return nil
                }
            }
            // Details mode + arrow: fall through, let Table handle.
            // Cmd+Up/Down: fall through to Command handler below.
        }

        // No modifiers
        if flags.isEmpty {
            switch event.keyCode {
            case 51: // Backspace → enclosing folder
                if tab.canGoUp { tab.goUp(); return nil }
            case 36: // Return → open selection (works in both details + icon views)
                if !tab.selection.isEmpty {
                    tab.openSelection()
                    return nil
                }
            case 48: // Tab → cycle active panel (only in split mode)
                if app.panels.count >= 2 {
                    app.activePanelIndex = (app.activePanelIndex + 1) % app.panels.count
                    app.transferFocusToActivePanel()
                    return nil
                }
            case 120: // F2 → rename (needs Fn+F2 unless function-key mode is on)
                if tab.selection.count >= 2 {
                    tab.beginBatchRename()
                    return nil
                } else if !tab.selection.isEmpty {
                    tab.beginRename()
                    return nil
                }
            default: break
            }
            return event
        }

        // ⌃D → open Terminal at the current folder
        if flags == .control, event.keyCode == 2 {
            FileSystemService.openInTerminal(tab.url)
            return nil
        }

        guard flags == .command else { return event }

        switch event.keyCode {
        case 14: // ⌘E → rename (sheet for multi-select, inline for single)
            if tab.selection.count >= 2 {
                tab.beginBatchRename()
                return nil
            } else if !tab.selection.isEmpty {
                tab.beginRename()
                return nil
            }
        case 126: // ⌘↑ → enclosing folder
            if tab.canGoUp { tab.goUp(); return nil }
        case 125: // ⌘↓ → open selection
            if !tab.selection.isEmpty { tab.openSelection(); return nil }
        case 8: // ⌘C → copy
            if !tab.selection.isEmpty {
                app.copy(urls: tab.selectedURLs)
                return nil
            }
        case 7: // ⌘X → cut
            if !tab.selection.isEmpty {
                app.cut(urls: tab.selectedURLs)
                return nil
            }
        case 9: // ⌘V → paste
            if app.canPaste {
                app.paste(into: tab.url)
                return nil
            }
        case 42: // ⌘\ → toggle split pane
            app.toggleSplit()
            return nil
        default: break
        }
        return event
    }

    private func moveSelection(tab: BrowserTab, by delta: Int, extend: Bool) {
        let entries = tab.entries
        guard !entries.isEmpty else { return }

        let anchorIdx: Int
        if tab.selection.isEmpty {
            // No prior selection — pick first row going down, last going up.
            anchorIdx = delta > 0 ? -1 : entries.count
        } else {
            let indices = tab.selection.compactMap { id in
                entries.firstIndex(where: { $0.id == id })
            }
            // Extend from the edge of the current selection in the motion's direction.
            anchorIdx = delta > 0 ? (indices.max() ?? 0) : (indices.min() ?? 0)
        }

        let nextIdx = max(0, min(entries.count - 1, anchorIdx + delta))
        let nextID = entries[nextIdx].id
        if extend {
            tab.selection.insert(nextID)
        } else {
            tab.selection = [nextID]
        }
    }

    private func handleBatch(_ event: NSEvent, tab: BrowserTab) -> NSEvent? {
        switch event.keyCode {
        case 36, 76: // Return / Numpad Enter → commit
            tab.commitBatchRename()
            return nil
        case 53: // Escape → cancel
            tab.cancelBatchRename()
            return nil
        case 51: // Backspace → pop typed, then chop more from stem
            tab.batchBackspace()
            return nil
        default:
            break
        }

        // Append printable characters (let ⌘-anything pass through so Cmd+Q etc. still work)
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) { return event }
        // Use `characters` so Shift produces uppercase; filter private-use
        // function-key scalars (0xF700+) like arrows / F-keys.
        if let chars = event.characters,
           let scalar = chars.unicodeScalars.first,
           scalar.value >= 32, scalar.value < 0xF700, scalar.value != 127 {
            tab.batchAppend(chars)
            return nil
        }
        // Consume anything else (arrows, function keys) so they don't move selection.
        return nil
    }
}
