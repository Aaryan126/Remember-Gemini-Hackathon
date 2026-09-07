import Foundation

/// Display-only relationships; never feeds back into automatic topic organization.
nonisolated struct ProjectGraphMap {
    struct Node: Identifiable {
        let cluster: ProvenanceCluster
        let members: [MemoryItem]
        var id: UUID { cluster.id }
        var sourceIDs: Set<UUID> { Set(members.map(\.id)) }
        var tags: Set<String> { Set(members.flatMap(\.tags).map { $0.lowercased() }) }
        var shortTitle: String {
            let words = cluster.title.split(whereSeparator: \.isWhitespace)
            let shortened = words.prefix(5).joined(separator: " ")
            return String(shortened.prefix(44)) + (words.count > 5 || shortened.count > 44 ? "…" : "")
        }
        /// Keep long words on one line; the view scales that line instead of
        /// splitting a word such as "Entrepreneurship" across the circle.
        var titleLines: [String] {
            var lines: [String] = []
            for word in shortTitle.split(separator: " ") {
                if let last = lines.last, last.count + word.count + 1 <= 14 {
                    lines[lines.count - 1] += " " + word
                } else {
                    lines.append(String(word))
                }
            }
            return lines.count > 4 ? Array(lines.prefix(3)) + [lines.dropFirst(3).joined(separator: " ")] : lines
        }
    }

    struct Edge: Equatable {
        let first: Int
        let second: Int
    }

    let nodes: [Node]
    let edges: [Edge]
    let totalCount: Int

    init(snapshot: ProvenanceSnapshot) {
        let clusters = snapshot.activeClusters
        totalCount = clusters.count
        nodes = clusters.prefix(40).map { Node(cluster: $0, members: snapshot.members(of: $0.id)) }
        var connections: [Edge] = []
        let sources = nodes.map(\.sourceIDs)
        let tags = nodes.map(\.tags)
        for first in nodes.indices {
            for second in nodes.indices where second > first {
                let sharedSource = !sources[first].isDisjoint(with: sources[second])
                let union = tags[first].union(tags[second])
                let sharedTags = !union.isEmpty
                    && Double(tags[first].intersection(tags[second]).count) / Double(union.count) >= 0.5
                if sharedSource || sharedTags { connections.append(Edge(first: first, second: second)) }
            }
        }
        edges = connections
    }

    func isConnected(_ first: UUID, to second: UUID) -> Bool {
        first == second || edges.contains {
            (nodes[$0.first].id == first && nodes[$0.second].id == second)
                || (nodes[$0.second].id == first && nodes[$0.first].id == second)
        }
    }
}

/// Stable staggered circles. Logarithmic sizing shows volume without letting a
/// very large thread overwhelm small ones or change the size of unrelated nodes.
nonisolated struct ProjectGraphLayout {
    let memberCounts: [Int]
    init(count: Int) { memberCounts = Array(repeating: 1, count: max(0, count)) }
    init(memberCounts: [Int]) { self.memberCounts = memberCounts }
    var count: Int { memberCounts.count }
    var columns: Int { count <= 1 ? 1 : count <= 8 ? 2 : 4 }
    var rows: Int { max(1, (count + columns - 1) / columns) }
    private var pitch: CGFloat { (memberCounts.indices.map(diameter).max() ?? 116) + 24 }
    var size: CGSize {
        CGSize(width: CGFloat(columns) * pitch + 28, height: CGFloat(rows) * pitch + (columns > 1 ? pitch / 4 : 0) + 28)
    }

    func diameter(_ index: Int) -> CGFloat {
        116 + min(56, 22 * log2(CGFloat(max(1, memberCounts[index]))))
    }

    func position(_ index: Int) -> CGPoint {
        let column = index % columns
        let row = index / columns
        return CGPoint(x: 14 + pitch / 2 + CGFloat(column) * pitch,
                       y: 14 + pitch / 2 + CGFloat(row) * pitch + (column.isMultiple(of: 2) ? 0 : pitch / 4))
    }

    func fitScale(in viewport: CGSize) -> CGFloat {
        min(1.15, min(max(1, viewport.width - 24) / size.width, max(1, viewport.height - 64) / size.height))
    }

    static func boundedPan(_ pan: CGSize, content: CGSize, viewport: CGSize, scale: CGFloat) -> CGSize {
        let xLimit = max(0, (content.width * scale - viewport.width) / 2) + 60
        let yLimit = max(0, (content.height * scale - viewport.height) / 2) + 60
        return CGSize(width: min(xLimit, max(-xLimit, pan.width)), height: min(yLimit, max(-yLimit, pan.height)))
    }
}
