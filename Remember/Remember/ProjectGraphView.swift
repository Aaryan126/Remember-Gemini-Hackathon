import SwiftUI

struct ProjectGraphView: View {
    let model: ProjectViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var zoom: CGFloat = 1
    @State private var pan = CGSize.zero
    @GestureState private var drag = CGSize.zero
    @GestureState private var magnification: CGFloat = 1

    var body: some View {
        let map = ProjectGraphMap(snapshot: model.snapshot)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your memory map").font(.title2.bold())
                    Text("\(map.totalCount) threads · \(map.edges.count) connections\(map.totalCount > 40 ? " in view" : "")")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                if map.totalCount == 0 {
                    ContentUnavailableView("No active threads", systemImage: "circle.dotted",
                        description: Text("Your memories are still in Memories. Restore a thread from Archive or capture something new."))
                } else if !dynamicTypeSize.isAccessibilitySize {
                    graph(map)
                    Text("Larger circles hold more memories. Tap to open; drag or pinch to explore.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                if map.totalCount > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("All threads").font(.title3.bold())
                        Text(map.edges.isEmpty
                            ? "Threads stand on their own for now. Connections appear when they share sources or tags."
                            : "Lines connect threads with shared sources or overlapping tags.")
                            .font(.footnote).foregroundStyle(.secondary)
                        if map.totalCount > 40 {
                            Text("The map shows the first 40 threads. Every thread is available below.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    LazyVStack(spacing: 10) {
                        ForEach(model.snapshot.activeClusters) { cluster in
                            let members = model.snapshot.members(of: cluster.id)
                            NavigationLink { ClusterRiverView(clusterID: cluster.id, model: model) } label: {
                                HStack(spacing: 14) {
                                    Circle().fill(tint(for: cluster.id).opacity(0.7)).frame(width: 12, height: 12)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(cluster.title).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                                        Text("\(members.count) \(members.count == 1 ? "memory" : "memories")").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                                }
                                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("graph-thread-\(cluster.id)")
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .onChange(of: map.nodes.map(\.id)) { _, _ in
            resetViewport()
        }
    }

    private func graph(_ map: ProjectGraphMap) -> some View {
        GeometryReader { geometry in
            let layout = ProjectGraphLayout(memberCounts: map.nodes.map { $0.members.count })
            let scale = layout.fitScale(in: geometry.size) * min(4, max(0.7, zoom * magnification))
            let offset = ProjectGraphLayout.boundedPan(
                CGSize(width: pan.width + drag.width, height: pan.height + drag.height),
                content: layout.size, viewport: geometry.size, scale: scale
            )
            ZStack {
                RoundedRectangle(cornerRadius: 28).fill(Color(uiColor: .secondarySystemGroupedBackground))
                RoundedRectangle(cornerRadius: 28)
                    .fill(LinearGradient(colors: [.cyan.opacity(0.08), .clear, .indigo.opacity(0.07)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Canvas { context, size in
                    for x in stride(from: 16.0, to: size.width, by: 22) {
                        for y in stride(from: 16.0, to: size.height, by: 22) {
                            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)), with: .color(.secondary.opacity(0.18)))
                        }
                    }
                }.accessibilityHidden(true)
                ZStack(alignment: .topLeading) {
                    connections(map, layout: layout)
                    ForEach(Array(map.nodes.enumerated()), id: \.element.id) { index, node in
                        graphNode(node, diameter: layout.diameter(index)).position(layout.position(index))
                    }
                }
                .frame(width: layout.size.width, height: layout.size.height)
                .scaleEffect(scale)
                .position(x: geometry.size.width / 2 + offset.width, y: (geometry.size.height - 40) / 2 + offset.height)
            }
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 8)
                .updating($drag) { value, state, transaction in
                    transaction.animation = nil
                    state = value.translation
                }
                .onEnded { value in
                    pan = ProjectGraphLayout.boundedPan(
                        CGSize(width: pan.width + value.translation.width, height: pan.height + value.translation.height),
                        content: layout.size, viewport: geometry.size, scale: scale
                    )
                })
            .simultaneousGesture(MagnifyGesture()
                .updating($magnification) { value, state, _ in state = value.magnification }
                .onEnded { value in zoom = min(4, max(0.7, zoom * value.magnification)) })
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 0) {
                    mapControl("Fit map", symbol: "arrow.up.left.and.arrow.down.right") { resetViewport() }
                    Divider().frame(height: 18)
                    mapControl("Zoom out", symbol: "minus") { zoom = max(0.7, zoom / 1.3) }
                    mapControl("Zoom in", symbol: "plus") { zoom = min(4, zoom * 1.3) }
                }
                .background(.regularMaterial, in: .capsule)
                .overlay(Capsule().strokeBorder(.primary.opacity(0.06)))
                .padding(12)
            }
            .clipShape(.rect(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.primary.opacity(0.06)))
        }
        .frame(height: 460)
    }

    private func connections(_ map: ProjectGraphMap, layout: ProjectGraphLayout) -> some View {
        Canvas { context, _ in
            for edge in map.edges {
                let start = layout.position(edge.first), end = layout.position(edge.second)
                var path = Path()
                path.move(to: start)
                path.addCurve(to: end,
                    control1: CGPoint(x: start.x, y: (start.y + end.y) / 2),
                    control2: CGPoint(x: end.x, y: (start.y + end.y) / 2))
                context.stroke(path, with: .color(.teal.opacity(0.5)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }.accessibilityHidden(true)
    }

    private func graphNode(_ node: ProjectGraphMap.Node, diameter: CGFloat) -> some View {
        let color = tint(for: node.id)
        return NavigationLink {
            ClusterRiverView(clusterID: node.id, model: model)
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
                    Circle().fill(Color(uiColor: .secondarySystemGroupedBackground))
                        .overlay {
                            Circle().fill(LinearGradient(colors: [color.opacity(0.18), color.opacity(0.05)],
                                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                }
                .overlay(Circle().strokeBorder(color.opacity(0.35), lineWidth: 1))
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(node.cluster.title), \(node.members.count) \(node.members.count == 1 ? "memory" : "memories")")
        .accessibilityValue(Set(node.members.map(\.kind)).count == 1 ? kindLabel(node.members.first?.kind) : "Mixed sources")
        .accessibilityHint("Opens the thread river and its saved media")
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

    private func resetViewport() { zoom = 1; pan = .zero }

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
        let colors: [Color] = [.teal, .indigo, .orange, .blue, .purple, .pink]
        return colors[id.uuidString.utf8.reduce(0) { $0 + Int($1) } % colors.count]
    }
}
