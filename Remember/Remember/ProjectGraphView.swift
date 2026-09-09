import SwiftUI

struct ProjectGraphView: View {
    let model: ProjectViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var topicTransition
    @State private var focusedID: UUID?
    @State private var selectedThreadID: UUID?
    @State private var isDragging = false
    @State private var pan = CGSize.zero
    @GestureState private var drag = CGSize.zero

    var body: some View {
        let map = ProjectGraphMap(snapshot: model.snapshot)
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your memory map").font(.title2.bold())
                Text("\(map.totalCount) threads · \(map.edges.count) connections\(map.totalCount > 40 ? " in view" : "")")
                    .font(.subheadline).foregroundStyle(.secondary)
                if map.totalCount > 40 {
                    Text("Showing 40 threads. Find every thread in Timeline.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            if map.totalCount == 0 {
                ContentUnavailableView("No active threads", systemImage: "circle.dotted",
                    description: Text("Your memories are still in Memories. Restore a thread from Archive or capture something new."))
            } else {
                graph(map)
            }
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(uiColor: .systemGroupedBackground))
        .onChange(of: map.nodes.map(\.id)) { _, _ in
            resetViewport()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { focusedID = nil; isDragging = false }
        }
        .sensoryFeedback(.selection, trigger: focusedID) { _, next in next != nil }
        .navigationDestination(item: $selectedThreadID) { id in
            if reduceMotion {
                ClusterRiverView(clusterID: id, model: model)
            } else {
                ClusterRiverView(clusterID: id, model: model)
                    .navigationTransition(.zoom(sourceID: id, in: topicTransition))
            }
        }
    }

    private func graph(_ map: ProjectGraphMap) -> some View {
        GeometryReader { geometry in
            let layout = ProjectGraphLayout(memberCounts: map.nodes.map { $0.members.count })
            let scale = ProjectGraphLayout.browsingScale(in: geometry.size)
            let offset = ProjectGraphLayout.boundedPan(
                CGSize(width: pan.width + drag.width, height: pan.height + drag.height),
                content: layout.size, viewport: geometry.size, scale: scale
            )
            let projection = ProjectGraphProjection(layout: layout, viewport: geometry.size, scale: scale, pan: offset,
                focusedIndex: map.nodes.firstIndex { $0.id == focusedID }, reduceMotion: reduceMotion)
            ZStack {
                RoundedRectangle(cornerRadius: 28).fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .onTapGesture { focus(nil) }
                RoundedRectangle(cornerRadius: 28)
                    .fill(LinearGradient(colors: [.cyan.opacity(0.08), .clear, .indigo.opacity(0.07)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .allowsHitTesting(false)
                Canvas { context, size in
                    for x in stride(from: 16.0, to: size.width, by: 22) {
                        for y in stride(from: 16.0, to: size.height, by: 22) {
                            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)), with: .color(.secondary.opacity(0.18)))
                        }
                    }
                }.accessibilityHidden(true).allowsHitTesting(false)
                ZStack(alignment: .topLeading) {
                    connections(map, projection: projection)
                    ForEach(Array(map.nodes.enumerated()), id: \.element.id) { index, node in
                        let pose = projection.nodes[index]
                        graphNode(node, diameter: layout.diameter(index), related: focusedID.map { map.isConnected($0, to: node.id) } ?? true)
                            .scaleEffect(pose.scale)
                            .position(pose.center)
                            .zIndex(node.id == focusedID ? 1 : 0)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 8)
                .updating($drag) { value, state, transaction in
                    transaction.animation = nil
                    state = value.translation
                }
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        // Hit-test the original viewport, not the already translated nodes.
                        let restingPan = ProjectGraphLayout.boundedPan(pan, content: layout.size, viewport: geometry.size, scale: scale)
                        let initial = ProjectGraphProjection(layout: layout, viewport: geometry.size, scale: scale, pan: restingPan,
                            focusedIndex: map.nodes.firstIndex { $0.id == focusedID }, reduceMotion: reduceMotion)
                        focus(initial.hitTest(value.startLocation).map { map.nodes[$0].id })
                    }
                }
                .onEnded { value in
                    pan = ProjectGraphLayout.boundedPan(
                        CGSize(width: pan.width + value.translation.width, height: pan.height + value.translation.height),
                        content: layout.size, viewport: geometry.size, scale: scale
                    )
                    isDragging = false
                })
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 0) {
                    if focusedID != nil {
                        mapControl("Clear focus", symbol: "circle.dotted") { focus(nil) }
                        Divider().frame(height: 18)
                    }
                    mapControl("Recenter map", symbol: "scope") { resetViewport() }
                }
                .background(.regularMaterial, in: .capsule)
                .overlay(Capsule().strokeBorder(.primary.opacity(0.06)))
                .padding(12)
            }
            .clipShape(.rect(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.primary.opacity(0.06)))
            .onChange(of: drag) { _, value in
                if value == .zero { isDragging = false }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("memory-map-canvas")
            .accessibilityScrollAction { edge in
                let step = min(geometry.size.width, geometry.size.height) * 0.6
                var next = pan
                switch edge {
                case .top: next.height += step
                case .bottom: next.height -= step
                case .leading: next.width += step
                case .trailing: next.width -= step
                default: return
                }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    pan = ProjectGraphLayout.boundedPan(next, content: layout.size, viewport: geometry.size, scale: scale)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func connections(_ map: ProjectGraphMap, projection: ProjectGraphProjection) -> some View {
        ZStack {
            ForEach(Array(map.edges.enumerated()), id: \.offset) { _, edge in
                if let endpoints = projection.endpoints(for: edge) {
                    let highlighted = focusedID == map.nodes[edge.first].id || focusedID == map.nodes[edge.second].id
                    GraphConnection(start: endpoints.start, end: endpoints.end)
                        .stroke(highlighted ? Color.accentColor.opacity(0.8) : Color.secondary.opacity(focusedID == nil ? 0.3 : 0.12),
                                style: StrokeStyle(lineWidth: highlighted ? 2.5 : 1.25, lineCap: .round))
                }
            }
        }.accessibilityHidden(true).allowsHitTesting(false)
    }

    private func graphNode(_ node: ProjectGraphMap.Node, diameter: CGFloat, related: Bool) -> some View {
        let color = tint(for: node.id)
        let focused = focusedID == node.id
        return Button {
            focus(node.id)
            selectedThreadID = node.id
        } label: {
            VStack(spacing: 2) {
                ForEach(Array(node.titleLines.enumerated()), id: \.offset) { _, line in
                    Text(line).lineLimit(1).minimumScaleFactor(0.55)
                        .frame(maxWidth: .infinity)
                }
            }
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .frame(width: diameter * 0.74, height: diameter * 0.74)
                .frame(width: diameter, height: diameter)
                .background {
                    if reduceTransparency {
                        Circle().fill(Color(uiColor: .secondarySystemGroupedBackground))
                    } else {
                        Circle().fill(.regularMaterial)
                    }
                    Circle().fill(LinearGradient(colors: [color.opacity(focused ? 0.24 : 0.12), color.opacity(0.04)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                .overlay(Circle().strokeBorder(color.opacity(focused ? 0.75 : related && focusedID != nil ? 0.5 : 0.25), lineWidth: focused ? 1.8 : 1))
                .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom), lineWidth: 0.75))
                .clipShape(Circle())
                .shadow(color: focused ? color.opacity(0.2) : .black.opacity(0.06), radius: focused ? 12 : 4, y: focused ? 3 : 2)
                .contentShape(Circle())
                .matchedTransitionSource(id: node.id, in: topicTransition) { source in
                    source.clipShape(RoundedRectangle(cornerRadius: diameter / 2))
                }
        }
        .buttonStyle(GraphNodePressStyle { focus(node.id) })
        .highPriorityGesture(LongPressGesture(minimumDuration: 0.3, maximumDistance: 10).onEnded { _ in focus(node.id) })
        .opacity(related ? 1 : contrast == .increased ? 0.85 : 0.65)
        .accessibilityAddTraits(focused ? [.isSelected] : [])
        .accessibilityLabel("\(node.cluster.title), \(node.members.count) \(node.members.count == 1 ? "memory" : "memories")")
        .accessibilityValue(Set(node.members.map(\.kind)).count == 1 ? kindLabel(node.members.first?.kind) : "Mixed sources")
        .accessibilityHint("Tap to open the river. Hold to highlight connected threads.")
        .accessibilityAction(named: "Highlight connections") { focus(node.id) }
        .accessibilityIdentifier("graph-node-\(node.id)")
    }

    private func mapControl(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2), action)
        } label: {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(title)
    }

    private func focus(_ id: UUID?) {
        guard focusedID != id else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.84)) { focusedID = id }
    }

    private func resetViewport() { pan = .zero; focusedID = nil; isDragging = false }

    private func kindLabel(_ kind: MemoryKind?) -> String {
        switch kind {
        case .audio: "Voice"
        case .image: "Photos"
        case .video: "Videos"
        case .link: "Links"
        case .pdf: "Documents"
        case .text: "Notes"
        case nil: "Sources"
        }
    }

    private func tint(for id: UUID) -> Color {
        let colors: [Color] = [.teal, .indigo, .blue, .purple]
        return colors[id.uuidString.utf8.reduce(0) { $0 + Int($1) } % colors.count]
    }
}

private struct GraphNodePressStyle: ButtonStyle {
    let onPress: () -> Void
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { onPress() }
            }
    }
}

/// Interpolates with the moving circles so focus never detaches their connections.
private struct GraphConnection: Shape {
    var start: CGPoint
    var end: CGPoint
    var animatableData: AnimatablePair<CGPoint.AnimatableData, CGPoint.AnimatableData> {
        get { AnimatablePair(start.animatableData, end.animatableData) }
        set { start.animatableData = newValue.first; end.animatableData = newValue.second }
    }
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: start)
        path.addCurve(to: end, control1: CGPoint(x: start.x, y: (start.y + end.y) / 2),
                      control2: CGPoint(x: end.x, y: (start.y + end.y) / 2))
        return path
    }
}
