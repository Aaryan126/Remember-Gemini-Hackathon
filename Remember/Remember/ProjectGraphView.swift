import SwiftUI

struct ProjectGraphView: View {
    let model: ProjectViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var topicTransition
    @State private var focusedID: UUID?
    @State private var selectedThreadID: UUID?
    @State private var previewID: UUID?
    @State private var centeredID: UUID?
    @ScaledMetric(relativeTo: .subheadline) private var captionHeight: CGFloat = 44
    @State private var motion = ProjectGraphMotion()
    @GestureState private var dragIsActive = false

    var body: some View {
        let map = ProjectGraphMap(snapshot: model.snapshot)
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your memory map").font(.title2.bold())
                Text("\(map.totalCount) threads · \(map.edges.count) connections\(map.totalCount > 40 ? " in view" : "")")
                    .font(.subheadline).foregroundStyle(RememberPalette.secondaryText)
                if map.totalCount > 40 {
                    Text("Showing 40 threads. Find every thread in Timeline.")
                        .font(.footnote).foregroundStyle(RememberPalette.secondaryText)
                }
            }

            if map.totalCount == 0 {
                ContentUnavailableView("No active threads", systemImage: "circle.dotted",
                    description: Text("Your memories are still in Memories. Restore a thread from Archive or capture something new."))
            } else {
                centeredCaption(map)
                graph(map)
            }
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .rememberCanvas()
        .onChange(of: map.nodes.map(\.id)) { _, _ in
            centeredID = nil
            resetViewport()
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

    private func centeredCaption(_ map: ProjectGraphMap) -> some View {
        let node = map.nodes.first { $0.id == centeredID }
            ?? map.nodes.max { $0.members.count < $1.members.count }
        // Reserve the same space for every title. Unusually long titles remain
        // readable by scrolling the caption, without shrinking/repositioning the map.
        return ScrollView(.vertical) {
            Text(node?.cluster.title ?? "")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("map-centered-title")
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: captionHeight, alignment: .top)
        .id(node?.id)
    }

    private func graph(_ map: ProjectGraphMap) -> some View {
        GeometryReader { geometry in
            let layout = ProjectGraphLayout(memberCounts: map.nodes.map { $0.members.count })
            let scale = ProjectGraphLayout.browsingScale(in: geometry.size)
            let offset = motion.position
            let projection = ProjectGraphProjection(layout: layout, viewport: geometry.size, scale: scale, pan: offset,
                focusedIndex: map.nodes.firstIndex { $0.id == focusedID }, reduceMotion: reduceMotion)
            ZStack {
                RoundedRectangle(cornerRadius: 28).fill(RememberPalette.mapCanvas)
                    .onTapGesture { focus(nil) }
                RoundedRectangle(cornerRadius: 28)
                    .fill(RadialGradient(colors: [colorScheme == .dark ? silver.opacity(0.10) : .white.opacity(0.65), .clear],
                                         center: .center, startRadius: 20, endRadius: geometry.size.height * 0.6))
                    .allowsHitTesting(false)
                ZStack(alignment: .topLeading) {
                    connections(map, projection: projection)
                    ForEach(Array(map.nodes.enumerated()), id: \.element.id) { index, node in
                        let pose = projection.nodes[index]
                        graphNode(node, diameter: layout.diameter(index), prominence: pose.prominence,
                                  lighting: ProjectGraphLighting(center: pose.center, viewport: geometry.size, reduceMotion: reduceMotion),
                                  related: focusedID.map { map.isConnected($0, to: node.id) } ?? true)
                            .scaleEffect(pose.scale)
                            .position(pose.center)
                            .zIndex(node.id == focusedID ? 1 : 0)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 8)
                .updating($dragIsActive) { _, state, _ in state = true }
                .onChanged { value in
                    if !motion.isDragging {
                        // Interrupt at the currently visible position, not the old snap target.
                        motion.beginDrag()
                        let initial = ProjectGraphProjection(layout: layout, viewport: geometry.size, scale: scale, pan: motion.position,
                            focusedIndex: map.nodes.firstIndex { $0.id == focusedID }, reduceMotion: reduceMotion)
                        focus(initial.hitTest(value.startLocation).map { map.nodes[$0].id })
                    }
                    motion.drag(translation: value.translation, layout: layout, viewport: geometry.size, scale: scale)
                }
                .onEnded { value in
                    guard motion.isDragging else { return }
                    motion.drag(translation: value.translation, layout: layout, viewport: geometry.size, scale: scale)
                    settleMap(at: motion.position, layout: layout, scale: scale, map: map)
                })
            .overlay(alignment: .bottom) {
                VStack(alignment: .trailing, spacing: 10) {
                    HStack(spacing: 0) {
                        if focusedID != nil {
                            mapControl("Clear focus", symbol: "circle.dotted") { focus(nil) }
                            Divider().frame(height: 18)
                        }
                        mapControl("Recenter map", symbol: "scope") { resetViewport() }
                    }
                    .background(.regularMaterial, in: .capsule)
                    .overlay(Capsule().strokeBorder(.primary.opacity(0.06)))
                    if let node = map.nodes.first(where: { $0.id == previewID }) {
                        focusPreview(node, map: map)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(12)
            }
            .clipShape(.rect(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.primary.opacity(0.06)))
            .onChange(of: dragIsActive) { _, active in
                // Also settle when the system cancels a drag without onEnded.
                if !active && motion.isDragging {
                    settleMap(at: motion.position, layout: layout, scale: scale, map: map)
                }
            }
            .onChange(of: motion.isSettling) { _, settling in
                if !settling && !motion.isDragging {
                    centeredID = layout.snapTarget(for: motion.position, scale: scale).map { map.nodes[$0.index].id }
                }
            }
            .onChange(of: geometry.size) { _, _ in
                settleMap(at: motion.position, layout: layout, scale: scale, map: map)
            }
            .onChange(of: layout.memberCounts) { _, _ in
                settleMap(at: motion.position, layout: layout, scale: scale, map: map)
            }
            .onChange(of: reduceMotion) { _, enabled in
                if enabled { settleMap(at: motion.position, layout: layout, scale: scale, map: map) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    if let target = layout.snapTarget(for: motion.position, scale: scale) {
                        motion.settle(to: target.pan, animated: false)
                    }
                    focusedID = nil; previewID = nil
                }
            }
            .onDisappear {
                if let target = layout.snapTarget(for: motion.position, scale: scale) {
                    motion.settle(to: target.pan, animated: false)
                } else { motion.stop() }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("memory-map-canvas")
            .accessibilityScrollAction { edge in
                let step = min(geometry.size.width, geometry.size.height) * 0.6
                var next = motion.position
                switch edge {
                case .top: next.height += step
                case .bottom: next.height -= step
                case .leading: next.width += step
                case .trailing: next.width -= step
                default: return
                }
                let bounded = ProjectGraphLayout.boundedPan(next, content: layout.size, viewport: geometry.size, scale: scale)
                settleMap(at: bounded, layout: layout, scale: scale, map: map)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func settleMap(at offset: CGSize, layout: ProjectGraphLayout, scale: CGFloat, map: ProjectGraphMap) {
        guard let target = layout.snapTarget(for: offset, scale: scale) else { return }
        motion.settle(to: target.pan, animated: !reduceMotion)
        if !motion.isSettling { centeredID = map.nodes[target.index].id }
        focus(map.nodes[target.index].id)
    }

    private func connections(_ map: ProjectGraphMap, projection: ProjectGraphProjection) -> some View {
        ZStack {
            ForEach(Array(map.edges.enumerated()), id: \.offset) { _, edge in
                if let endpoints = projection.endpoints(for: edge) {
                    let highlighted = focusedID == map.nodes[edge.first].id || focusedID == map.nodes[edge.second].id
                    GraphConnection(start: endpoints.start, end: endpoints.end)
                        .stroke(highlighted ? silver.opacity(0.85) : Color.secondary.opacity(focusedID == nil ? 0.25 : 0.12),
                                style: StrokeStyle(lineWidth: highlighted ? 2.5 : 1.25, lineCap: .round))
                }
            }
        }.accessibilityHidden(true).allowsHitTesting(false)
    }

    private func graphNode(_ node: ProjectGraphMap.Node, diameter: CGFloat, prominence: CGFloat,
                           lighting: ProjectGraphLighting, related: Bool) -> some View {
        let focused = focusedID == node.id
        let fittedSize = labelFontSize(node.titleLines, diameter: diameter)
        // A single enormous token must not turn into microscopic text. The exact
        // title is still available in the centered caption and accessibility label.
        let label = fittedSize >= 11 ? node.titleLines.joined(separator: "\n") : "Open\nthread"
        return Button {
            openRiver(node.id)
        } label: {
            Text(label)
                .font(.system(size: fittedSize >= 11 ? fittedSize : 18, weight: .semibold))
                .multilineTextAlignment(.center)
                .fixedSize()
                .foregroundStyle(.primary)
                .frame(width: diameter * 0.78, height: diameter * 0.74)
                .frame(width: diameter, height: diameter)
                .background {
                    ProjectGraphNodeSurface(diameter: diameter, prominence: prominence, focused: focused, lighting: lighting)
                }
                .clipShape(Circle())
                .shadow(color: .black.opacity(colorScheme == .dark ? (focused ? 0.14 : 0.08) : (focused ? 0.10 : 0.045)),
                        radius: focused ? 10 : 6, y: colorScheme == .dark ? 3 : 5)
                .contentShape(Circle())
                .matchedTransitionSource(id: node.id, in: topicTransition) { source in
                    source.clipShape(RoundedRectangle(cornerRadius: diameter / 2))
                }
        }
        .buttonStyle(GraphNodePressStyle { focus(node.id) })
        .highPriorityGesture(LongPressGesture(minimumDuration: 0.3, maximumDistance: 10).onEnded { _ in
            focus(node.id)
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { previewID = node.id }
        })
        .opacity(related ? 1 : contrast == .increased ? 0.90 : 0.72)
        .accessibilityAddTraits(focused ? [.isSelected] : [])
        .accessibilityLabel("\(node.cluster.title), \(node.members.count) \(node.members.count == 1 ? "memory" : "memories")")
        .accessibilityValue(Set(node.members.map(\.kind)).count == 1 ? kindLabel(node.members.first?.kind) : "Mixed sources")
        .accessibilityHint("Tap to open the river. Hold to preview and highlight connected threads.")
        .accessibilityAction(named: "Highlight connections") { focus(node.id) }
        .accessibilityAction(named: "Preview thread") { focus(node.id); previewID = node.id }
        .accessibilityIdentifier("graph-node-\(node.id)")
    }

    private func labelFontSize(_ lines: [String], diameter: CGFloat) -> CGFloat {
        let font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        let widest = lines.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 1
        // Fit the whole label uniformly, rather than making each line a different size.
        return 18 * min(1, diameter * 0.78 / max(1, widest), diameter * 0.74 / max(1, CGFloat(lines.count) * font.lineHeight))
    }

    private func focusPreview(_ node: ProjectGraphMap.Node, map: ProjectGraphMap) -> some View {
        let related = map.nodes.filter { $0.id != node.id && map.isConnected(node.id, to: $0.id) }.count
        return Button { openRiver(node.id) } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(node.cluster.title).font(.headline).lineLimit(2)
                    Text("\(node.members.count) \(node.members.count == 1 ? "memory" : "memories") · \(related) related threads")
                        .font(.caption).foregroundStyle(RememberPalette.secondaryText)
                    if !node.tags.isEmpty {
                        Text(node.tags.sorted().prefix(3).joined(separator: " · "))
                            .font(.caption).foregroundStyle(RememberPalette.secondaryText).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(RememberPalette.secondaryText)
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if reduceTransparency { RoundedRectangle(cornerRadius: 24).fill(Color(uiColor: .secondarySystemGroupedBackground)) }
                else {
                    RoundedRectangle(cornerRadius: 24).fill(.regularMaterial)
                    if colorScheme == .light { RoundedRectangle(cornerRadius: 24).fill(.white.opacity(0.72)) }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(silver.opacity(0.25)))
            .shadow(color: .black.opacity(colorScheme == .light ? 0.06 : 0), radius: 14, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open River: \(node.cluster.title)")
        .accessibilityIdentifier("map-focus-preview")
    }

    private func openRiver(_ id: UUID) {
        focus(id)
        previewID = nil
        selectedThreadID = id
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
        if previewID != id { previewID = nil }
        guard focusedID != id else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.84)) { focusedID = id }
    }

    private func resetViewport() {
        motion.settle(to: .zero, animated: !reduceMotion)
        focusedID = nil; previewID = nil
    }

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

    private var silver: Color {
        colorScheme == .dark ? Color(red: 0.77, green: 0.82, blue: 0.91) : Color(red: 0.38, green: 0.43, blue: 0.51)
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
