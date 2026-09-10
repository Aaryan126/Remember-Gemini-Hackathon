import Foundation

/// A display-only label, never a rename or a generated claim about the thread.
nonisolated struct ProjectGraphLabel {
    let words: [String]
    var text: String { words.joined(separator: " ") }
    var lines: [String] {
        // Pair short words where possible; keep long words intact.
        var result: [String] = []
        for word in words {
            if let last = result.last, last.count + word.count + 1 <= 14 {
                result[result.count - 1] += " " + word
            } else { result.append(word) }
        }
        return result
    }

    init(title: String) {
        let original = title.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !original.isEmpty else { words = ["Untitled", "thread"]; return }
        // Only simplify longer titles. Keep the final qualifier (Dates, Assignments,
        // Confirmation, etc.) instead of blindly chopping off the title's tail.
        let filler: Set<String> = ["a", "an", "the", "and", "of", "for", "to", "in", "on", "with", "about", "important", "best", "use"]
        let filtered = original.filter { !filler.contains($0.trimmingCharacters(in: .punctuationCharacters).lowercased()) }
        let candidates = original.count > 3 && !filtered.isEmpty ? filtered : original
        if candidates.count <= 3 {
            words = candidates
        } else {
            words = Array(candidates.prefix(2)) + [candidates[candidates.count - 1]]
        }
    }
}
