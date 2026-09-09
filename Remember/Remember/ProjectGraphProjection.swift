import Foundation

/// Viewport-only depth and focus geometry. Never changes saved thread organization.
nonisolated struct ProjectGraphProjection {
    struct Node {
        let center: CGPoint
        let scale: CGFloat
        let diameter: CGFloat
    }

    let nodes: [Node]

    init(layout: ProjectGraphLayout, viewport: CGSize, scale: CGFloat, pan: CGSize,
         focusedIndex: Int?, reduceMotion: Bool) {
        let scale = scale.isFinite && scale > 0 ? scale : 1
        let center = CGPoint(x: viewport.width / 2, y: (viewport.height - 40) / 2)
        let layoutSize = layout.size
        let positions = (0..<layout.count).map { index in
            let point = layout.position(index)
            return CGPoint(x: (point.x - layoutSize.width / 2) * scale + center.x + pan.width,
                           y: (point.y - layoutSize.height / 2) * scale + center.y + pan.height)
        }
        let focus = focusedIndex.flatMap { positions.indices.contains($0) ? positions[$0] : nil }
        nodes = positions.enumerated().map { index, point in
            var position = point
            var depth: CGFloat = 1
            if !reduceMotion {
                let x = (point.x - center.x) / max(1, viewport.width * 0.7)
                let y = (point.y - center.y) / max(1, viewport.height * 0.65)
                let distance = min(1, x * x + y * y)
                let falloff = distance * distance * (3 - 2 * distance)
                depth = 1.04 - 0.14 * falloff
                if let focus {
                    if index == focusedIndex {
                        depth *= 1.06
                    } else {
                        let dx = point.x - focus.x, dy = point.y - focus.y
                        let distance = hypot(dx, dy)
                        if distance > 0 {
                            let lift = 7 * scale * max(0, 1 - distance / (280 * scale))
                            position.x += dx / distance * lift
                            position.y += dy / distance * lift
                        }
                    }
                }
            }
            return Node(center: position, scale: scale * depth, diameter: layout.diameter(index) * scale * depth)
        }
    }

    func hitTest(_ point: CGPoint) -> Int? {
        nodes.indices.reversed().first { index in
            let node = nodes[index]
            return hypot(point.x - node.center.x, point.y - node.center.y) <= node.diameter / 2
        }
    }

    /// Lines meet the visible circle edges, including their focus/depth transforms.
    func endpoints(for edge: ProjectGraphMap.Edge) -> (start: CGPoint, end: CGPoint)? {
        guard nodes.indices.contains(edge.first), nodes.indices.contains(edge.second) else { return nil }
        let first = nodes[edge.first], second = nodes[edge.second]
        let dx = second.center.x - first.center.x, dy = second.center.y - first.center.y
        let distance = hypot(dx, dy)
        let firstRadius = first.diameter / 2 + 2, secondRadius = second.diameter / 2 + 2
        guard distance > firstRadius + secondRadius else { return nil }
        return (CGPoint(x: first.center.x + dx / distance * firstRadius,
                        y: first.center.y + dy / distance * firstRadius),
                CGPoint(x: second.center.x - dx / distance * secondRadius,
                        y: second.center.y - dy / distance * secondRadius))
    }
}
