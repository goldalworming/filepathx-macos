import Foundation

/// One text edit shared by every row of an inline batch rename.
///
/// The rows have different names, so the caret can't be a plain integer — it's
/// anchored to one end of each row's *stem* (the name minus its extension) and
/// resolved per row. `.fromEnd(0)` sits just before the extension (where batch
/// rename starts, matching the C source), `.fromStart(0)` sits before the first
/// character, which is what you want when adding a prefix.
///
/// The edit itself is "replace `deleted` characters ending at the anchor with
/// `typed`", and `cursor` is the caret's offset inside `typed`. Moving the
/// caret out of the typed run slides the whole replacement range, so ← then →
/// always lands back where you started.
struct BatchEdit: Equatable {
    enum Anchor: Equatable {
        case fromStart(Int)
        case fromEnd(Int)
    }

    /// Keeps repeated arrow presses past the longest name from growing forever.
    private static let maxOffset = 512

    var anchor: Anchor = .fromEnd(0)
    /// Characters chopped off the stem immediately before the anchor.
    var deleted: Int = 0
    var typed: String = ""
    /// Caret offset within `typed`.
    var cursor: Int = 0

    var hasChanges: Bool { !typed.isEmpty || deleted > 0 }

    // MARK: - Applying to a row

    private func anchorIndex(inStem stem: String) -> Int {
        switch anchor {
        case .fromStart(let k): return min(k, stem.count)
        case .fromEnd(let k):   return max(0, stem.count - k)
        }
    }

    /// The row's stem split around the edit: what survives before it, and what
    /// survives after it.
    func split(stem: String) -> (head: String, tail: String) {
        let idx = anchorIndex(inStem: stem)
        return (String(stem.prefix(max(0, idx - deleted))), String(stem.dropFirst(idx)))
    }

    /// The full new name for `name`, extension preserved.
    func newName(for name: String) -> String {
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        let (head, tail) = split(stem: stem)
        let newStem = head + typed + tail
        guard !newStem.isEmpty else { return name }
        return ext.isEmpty ? newStem : "\(newStem).\(ext)"
    }

    /// `typed` split at the caret, for drawing the cursor between the halves.
    var typedAroundCursor: (before: String, after: String) {
        let clamped = min(max(0, cursor), typed.count)
        let i = typed.index(typed.startIndex, offsetBy: clamped)
        return (String(typed[..<i]), String(typed[i...]))
    }

    // MARK: - Editing

    mutating func insert(_ text: String) {
        let clamped = min(max(0, cursor), typed.count)
        typed.insert(contentsOf: text, at: typed.index(typed.startIndex, offsetBy: clamped))
        cursor = clamped + text.count
    }

    /// Backspace eats the typed text first, then starts chopping the stem.
    mutating func deleteBackward() {
        if cursor > 0, !typed.isEmpty {
            let clamped = min(cursor, typed.count)
            typed.remove(at: typed.index(typed.startIndex, offsetBy: clamped - 1))
            cursor = clamped - 1
        } else {
            deleted += 1
        }
    }

    mutating func moveLeft() {
        if cursor > 0 {
            cursor -= 1
            return
        }
        switch anchor {
        case .fromEnd(let k):   anchor = .fromEnd(min(Self.maxOffset, k + 1))
        case .fromStart(let k): anchor = .fromStart(max(0, k - 1))
        }
    }

    mutating func moveRight() {
        if cursor < typed.count {
            cursor += 1
            return
        }
        switch anchor {
        case .fromEnd(let k):   anchor = .fromEnd(max(0, k - 1))
        case .fromStart(let k): anchor = .fromStart(min(Self.maxOffset, k + 1))
        }
    }

    /// Home — before the first character, i.e. prefix position.
    mutating func moveToStart() {
        anchor = .fromStart(0)
        cursor = 0
    }

    /// End — just before the extension.
    mutating func moveToEnd() {
        anchor = .fromEnd(0)
        cursor = typed.count
    }
}
