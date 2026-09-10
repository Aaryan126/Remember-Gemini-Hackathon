import Foundation
import CoreGraphics

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

/// A center-out hexagonal lattice, with six equidistant neighbors per complete ring.
nonisolated struct ProjectGraphLayout {
    static let maximumMagnification: CGFloat = 1.16
    static let focusMagnification: CGFloat = 1.06
    let memberCounts: [Int]
    private let points: [CGPoint]
    let size: CGSize
    let centralIndex: Int?
    init(count: Int) { self.init(memberCounts: Array(repeating: 1, count: max(0, count))) }
    init(memberCounts: [Int]) {
        self.memberCounts = memberCounts
        let central = memberCounts.indices.max { memberCounts[$0] < memberCounts[$1] }
        centralIndex = central
        // Reserve room for the largest focused circle without moving any slots.
        let pitch = (memberCounts.map { Self.diameter(for: $0) }.max() ?? 116)
            * Self.maximumMagnification * Self.focusMagnification + 12
        var lattice = [CGPoint.zero]
        var ring = 1
        let directions = [(1, 0), (0, 1), (-1, 1), (-1, 0), (0, -1), (1, -1)]
        while lattice.count < memberCounts.count {
            var q = 0, r = -ring
            for (dq, dr) in directions {
                for _ in 0..<ring {
                    lattice.append(CGPoint(x: (CGFloat(q) + CGFloat(r) / 2) * pitch,
                                           y: CGFloat(r) * sqrt(3) / 2 * pitch))
                    q += dq; r += dr
                }
            }
            ring += 1
        }
        let radius = CGFloat(max(0, ring - 1)) * pitch + pitch / 2 + 14
        size = CGSize(width: radius * 2, height: radius * 2)
        var arranged = Array(repeating: CGPoint(x: radius, y: radius), count: memberCounts.count)
        // Keep source indices/IDs intact while placing the largest thread at the lens center.
        let indices = central.map { center in [center] + memberCounts.indices.filter { $0 != center } } ?? []
        for (slot, index) in indices.enumerated() {
            arranged[index] = CGPoint(x: lattice[slot].x + radius, y: lattice[slot].y + radius)
        }
        points = arranged
    }
    var count: Int { memberCounts.count }

    func diameter(_ index: Int) -> CGFloat {
        Self.diameter(for: memberCounts[index])
    }

    private static func diameter(for count: Int) -> CGFloat {
        116 + min(56, 22 * log2(CGFloat(max(1, count))))
    }

    func position(_ index: Int) -> CGPoint { points[index] }

    /// Snap only to occupied slots, including at incomplete outer rings.
    func snapTarget(for pan: CGSize, scale: CGFloat) -> (index: Int, pan: CGSize)? {
        guard scale.isFinite, scale > 0, pan.width.isFinite, pan.height.isFinite else { return nil }
        var nearest: (index: Int, pan: CGSize)?
        var shortestDistance = CGFloat.infinity
        for index in points.indices {
            let target = CGSize(width: (size.width / 2 - points[index].x) * scale,
                                height: (size.height / 2 - points[index].y) * scale)
            let distance = hypot(target.width - pan.width, target.height - pan.height)
            if distance < shortestDistance {
                shortestDistance = distance
                nearest = (index, target)
            }
        }
        return nearest
    }

    static func browsingScale(in viewport: CGSize) -> CGFloat {
        // Keep labels readable as the library grows; explore the larger world by panning.
        min(1, max(0.8, (viewport.width - 24) / 360))
    }

    static func boundedPan(_ pan: CGSize, content: CGSize, viewport: CGSize, scale: CGFloat) -> CGSize {
        // Allow even the outermost circles to approach the center's depth/focus region.
        let xLimit = max(60, content.width * scale / 2 - min(72 * scale, viewport.width / 2))
        let yLimit = max(60, content.height * scale / 2 - min(72 * scale, viewport.height / 2))
        return CGSize(width: min(xLimit, max(-xLimit, pan.width)), height: min(yLimit, max(-yLimit, pan.height)))
    }
}
