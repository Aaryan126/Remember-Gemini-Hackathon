import Foundation

/// Viewport-only depth and focus geometry. Never changes saved thread organization.
nonisolated struct ProjectGraphProjection {
    struct Node {
        let center: CGPoint
        let scale: CGFloat
        let diameter: CGFloat
        let prominence: CGFloat
    }

    let nodes: [Node]

    init(layout: ProjectGraphLayout, viewport: CGSize, scale: CGFloat, pan: CGSize,
         focusedIndex: Int?, reduceMotion: Bool) {
        let scale = scale.isFinite && scale > 0 ? scale : 1
        let center = CGPoint(x: viewport.width / 2, y: (viewport.height - 40) / 2)
        let layoutSize = layout.size
        let lensRadius = max(100, min(viewport.width * 0.62, viewport.height * 0.48))
        nodes = (0..<layout.count).map { index in
            let point = layout.position(index)
            let x = (point.x - layoutSize.width / 2) * scale + pan.width
            let y = (point.y - layoutSize.height / 2) * scale + pan.height
            // Pan translates one rigid honeycomb. Magnification must never bend
            // its rows or push neighboring circles out of their assigned slots.
            let position = CGPoint(x: center.x + x, y: center.y + y)
            let normalized = hypot(x, y) / lensRadius
            let magnification = ProjectGraphLayout.maximumMagnification
            let baseDepth = reduceMotion ? 1 : magnification / sqrt(1 + normalized * normalized)
            let depth = baseDepth * (!reduceMotion && index == focusedIndex ? ProjectGraphLayout.focusMagnification : 1)
            return Node(center: position, scale: scale * depth, diameter: layout.diameter(index) * scale * depth,
                        prominence: min(1, baseDepth / magnification))
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
