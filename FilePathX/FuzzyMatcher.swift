import Foundation

/// Scoring for the fuzzy finder, ported from the C source's `ff_score_*`.
///
/// The query is split on whitespace and every token must match the candidate
/// independently (token order doesn't matter). A token first tries a
/// contiguous case-insensitive substring hit — what people usually mean — and
/// only falls back to an in-order subsequence match, which scores lower.
///
/// Positions are indices into the name's `Character` array, not bytes, so
/// highlighting lines up on non-ASCII names.
enum FuzzyMatcher {

    struct Match {
        let score: Int
        /// Sorted, deduplicated character positions that matched.
        let marks: [Int]
    }

    /// Characters that make the next character count as a "word start".
    private static let boundaries: Set<Character> = ["_", "-", ".", " ", "/", "\\"]

    /// Case- and diacritic-folded characters, one output per input character
    /// so match positions still index the original string. Folds that would
    /// change the length (ß → ss) are left alone.
    private static func normalized(_ s: String) -> [Character] {
        s.map { ch in
            let folded = String(ch).folding(options: [.caseInsensitive, .diacriticInsensitive],
                                            locale: nil)
            if folded.count == 1, let c = folded.first { return c }
            return String(ch).lowercased().first ?? ch
        }
    }

    /// Returns nil when the candidate doesn't match at all.
    static func match(name: String, query: String) -> Match? {
        let tokens = query.split(separator: " ", omittingEmptySubsequences: true)
        guard !tokens.isEmpty else { return Match(score: 1, marks: []) }

        let chars = normalized(name)
        var total = 0
        var marks: [Int] = []

        for token in tokens {
            guard let s = scoreToken(chars, normalized(String(token)), marks: &marks) else {
                return nil
            }
            total += s
        }

        marks = Array(Set(marks)).sorted()
        // Slight bias toward shorter names.
        total -= chars.count / 4
        return Match(score: total, marks: marks)
    }

    private static func scoreToken(_ name: [Character], _ token: [Character],
                                   marks: inout [Int]) -> Int? {
        guard !token.isEmpty else { return 0 }
        guard name.count >= token.count else { return nil }

        // 1. Contiguous substring.
        if let pos = firstRange(of: token, in: name) {
            marks.append(contentsOf: pos..<(pos + token.count))
            var score = 40 + token.count * 12
            if pos == 0 {
                score += 20
            } else if boundaries.contains(name[pos - 1]) {
                score += 10
            }
            return score
        }

        // 2. In-order subsequence.
        var qi = 0
        var score = 0
        var consecutive = 0
        var added: [Int] = []
        for i in name.indices where qi < token.count {
            guard name[i] == token[qi] else {
                consecutive = 0
                continue
            }
            added.append(i)
            score += 10 + consecutive * 8
            if i == 0 {
                score += 4
            } else if boundaries.contains(name[i - 1]) {
                score += 3
            }
            consecutive += 1
            qi += 1
        }
        guard qi == token.count else { return nil }
        marks.append(contentsOf: added)
        return score
    }

    private static func firstRange(of token: [Character], in name: [Character]) -> Int? {
        guard token.count <= name.count else { return nil }
        for start in 0...(name.count - token.count) {
            var ok = true
            for k in token.indices where name[start + k] != token[k] {
                ok = false
                break
            }
            if ok { return start }
        }
        return nil
    }
}
