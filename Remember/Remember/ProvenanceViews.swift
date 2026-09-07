import SwiftUI
import QuickLook

struct ProjectStatusView: View {
    let model: ProjectViewModel
    var body: some View {
        if let error = model.errorMessage {
            HStack { Text(error).font(.footnote); Spacer(); Button("Dismiss") { model.errorMessage = nil } }.padding().background(.bar)
        } else if model.isOrganizing {
            HStack { ProgressView(); Text("Organizing your threads…").font(.caption) }.padding(8).background(.bar)
        }
    }
}

struct ProvenanceEventRow: View {
    let event: ProvenanceEvent
    var displayMemory: MemoryItem? = nil
    var showsIcon = true
    var body: some View {
        let payload = try? event.payload()
        HStack(alignment: .top, spacing: 12) {
            if showsIcon {
                Image(systemName: event.kind == .merge ? "arrow.triangle.merge" : event.kind == .archive ? "archivebox" : "circle.fill")
                    .font(.system(size: event.kind == .capture ? 10 : 18)).foregroundStyle(.tint).frame(width: 24, height: 24)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(displayMemory?.displayTitle ?? payload?.memory?.displayTitle ?? payload?.title ?? event.kind.label).font(.headline).lineLimit(2)
                Text(event.kind.label + " · " + event.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
                if let rationale = payload?.rationale, !rationale.isEmpty, rationale != event.kind.label {
                    Text(rationale).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }.padding(.vertical, 5)
    }
}

struct ProjectGraphView: View {
    let model: ProjectViewModel
    @State private var scale = 0.75
    @GestureState private var magnification = 1.0
    private var snapshot: ProvenanceSnapshot { model.snapshot }
    private var clusters: [ProvenanceCluster] { Array(snapshot.activeClusters.prefix(40)) }
    private func position(_ index: Int) -> CGPoint {
        guard index > 0 else { return CGPoint(x: 800, y: 800) }
        var ring = 1
        var offset = index - 1
        while offset >= 6 * ring { offset -= 6 * ring; ring += 1 }
        let angle = Double(offset) * 2 * Double.pi / Double(6 * ring)
        let radius = Double(ring) * 180
        return CGPoint(x: 800 + cos(angle) * radius, y: 800 + sin(angle) * radius)
    }
    var body: some View {
        ScrollView {
            HStack {
                Text("\(snapshot.activeClusters.count) growing threads").font(.headline)
                Spacer()
                Button { scale = max(0.5, scale - 0.25) } label: { Image(systemName: "minus.magnifyingglass") }.accessibilityLabel("Zoom out")
                Button { scale = min(2, scale + 0.25) } label: { Image(systemName: "plus.magnifyingglass") }.accessibilityLabel("Zoom in")
            }.padding(.horizontal)
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        for (index, cluster) in clusters.enumerated() {
                            for next in clusters.indices where next > index && related(cluster, clusters[next]) {
                                var path = Path()
                                path.move(to: position(index)); path.addLine(to: position(next))
                                context.stroke(path, with: .color(.secondary.opacity(0.25)), lineWidth: 2)
                            }
                        }
                    }.accessibilityHidden(true)
                    ForEach(Array(clusters.enumerated()), id: \.element.id) { index, cluster in
                        let count = snapshot.members(of: cluster.id).count
                        let size = min(104.0, 62 + sqrt(Double(count)) * 10)
                        NavigationLink { ClusterRiverView(clusterID: cluster.id, model: model) } label: {
                            VStack(spacing: 8) {
                                Text("\(count)").font(.title2.weight(.semibold))
                                    .frame(width: size, height: size)
                                    .background(.tint.opacity(0.12), in: Circle()).overlay(Circle().stroke(.tint.opacity(0.3)))
                                Text(cluster.title).font(.subheadline.weight(.medium)).lineLimit(2).frame(width: 152)
                            }.multilineTextAlignment(.center).frame(width: 160, height: 156)
                        }.buttonStyle(.plain).position(position(index)).accessibilityLabel("\(cluster.title), \(count) memories")
                    }
                }.frame(width: 1600, height: 1600)
                    .scaleEffect(min(2, max(0.5, scale * magnification)), anchor: .topLeading)
                    .frame(width: 1600 * scale, height: 1600 * scale, alignment: .topLeading)
                    .gesture(MagnifyGesture().updating($magnification) { value, state, _ in state = value.magnification }
                        .onEnded { scale = min(2, max(0.5, scale * $0.magnification)) })
            }.defaultScrollAnchor(.center).frame(height: 410).background(.secondary.opacity(0.035))
            Text("Connections show shared sources or tags. Drag to explore; pinch to zoom.")
                .font(.caption).foregroundStyle(.secondary).padding()
            LazyVStack(alignment: .leading) {
                ForEach(snapshot.activeClusters) { cluster in
                    NavigationLink { ClusterRiverView(clusterID: cluster.id, model: model) } label: {
                        HStack { Text(cluster.title); Spacer(); Text("\(snapshot.members(of: cluster.id).count)"); Image(systemName: "chevron.right") }
                            .padding().background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal)
        }
    }
    private func related(_ first: ProvenanceCluster, _ second: ProvenanceCluster) -> Bool {
        let a = Set(snapshot.members(of: first.id).map(\.id)), b = Set(snapshot.members(of: second.id).map(\.id))
        if !a.isDisjoint(with: b) { return true }
        let tagsA = Set(snapshot.members(of: first.id).flatMap(\.tags)), tagsB = Set(snapshot.members(of: second.id).flatMap(\.tags))
        return !tagsA.isEmpty && Double(tagsA.intersection(tagsB).count) / Double(tagsA.union(tagsB).count) >= 0.5
    }
}

struct ClusterRiverView: View {
    let clusterID: UUID
    let model: ProjectViewModel
    @State private var isHistorical = false
    @State private var date = Date()
    @State private var title = ""
    @State private var showsRename = false
    @State private var limit = 50
    private var snapshot: ProvenanceSnapshot { model.historical(at: isHistorical ? date : nil) }
    private var cluster: ProvenanceCluster? { snapshot.clusters[clusterID] }
    private var events: [ProvenanceEvent] {
        let lineage = model.snapshot.ancestors(of: clusterID)
        return snapshot.events.filter { event in
            guard ![.checkpoint, .enrichment, .processing].contains(event.kind), let payload = try? event.payload() else { return false }
            if let id = payload.clusterID, lineage.contains(id) { return true }
            if !lineage.isDisjoint(with: payload.parents) { return true }
            if payload.assignments.values.contains(where: { !lineage.isDisjoint(with: $0) }) { return true }
            if let id = event.memoryID { return snapshot.memberships[id, default: []].contains(clusterID) || lineage.contains(id) }
            return false
        }
    }
    var body: some View {
        List {
            Section {
                Text(cluster?.title ?? "This thread had not formed yet").font(.largeTitle.bold())
                Text("\(snapshot.members(of: clusterID).count) \(snapshot.members(of: clusterID).count == 1 ? "memory" : "memories") · a traceable history").foregroundStyle(.secondary)
                Toggle("Travel through time", isOn: $isHistorical)
                if isHistorical {
                    DatePicker("As of", selection: $date, in: ...Date())
                    Slider(value: Binding(get: { date.timeIntervalSince1970 }, set: { date = Date(timeIntervalSince1970: $0) }),
                        in: (model.snapshot.events.first?.timestamp.timeIntervalSince1970 ?? Date().timeIntervalSince1970 - 1)...Date().timeIntervalSince1970)
                        .accessibilityLabel("History date").accessibilityIdentifier("History date")
                    comparison
                }
            }
            if let cluster, !cluster.parents.isEmpty {
                Section("Tributaries") {
                    ForEach(cluster.parents, id: \.self) { id in
                        NavigationLink { ClusterRiverView(clusterID: id, model: model) } label: {
                            Label(snapshot.clusters[id]?.title ?? "Earlier thread", systemImage: "arrow.turn.down.right")
                        }
                    }
                    Label(cluster.title, systemImage: "arrow.triangle.merge").font(.headline)
                }
            }
            Section("Sources") {
                ForEach(snapshot.members(of: clusterID)) { memory in
                    NavigationLink { ProjectSourceView(memory: memory, model: model, historical: isHistorical) } label: {
                        VStack(alignment: .leading) { Text(memory.displayTitle); Text(memory.kind.rawValue.capitalized).font(.caption).foregroundStyle(.secondary) }
                    }.accessibilityIdentifier("project-source-\(memory.id)")
                }
            }
            Section("River") {
                if events.count > limit { Button("Unfold earlier history") { limit += 50 } }
                ForEach(Array(events.suffix(limit))) { event in
                    NavigationLink { ProvenanceEventView(event: event, model: model, historical: isHistorical) } label: {
                        HStack(spacing: 12) {
                            RiverStreamMark(event: event, lineage: Array(model.snapshot.ancestors(of: clusterID)).sorted { $0.uuidString < $1.uuidString })
                                .frame(width: 52).accessibilityHidden(true)
                            ProvenanceEventRow(event: event, displayMemory: event.memoryID.flatMap { snapshot.memories[$0] }, showsIcon: false)
                        }
                    }
                }
            }
        }.listStyle(.insetGrouped).navigationTitle("Thread history").navigationBarTitleDisplayMode(.inline)
            .toolbar { if !isHistorical, cluster?.retired == false { Button("Rename") { title = cluster?.title ?? ""; showsRename = true } } }
            .alert("Name this topic", isPresented: $showsRename) {
                TextField("Topic name", text: $title)
                Button("Save") { Task { await model.rename(clusterID, title: title) } }
                Button("Cancel", role: .cancel) {}
            }
            .task { await model.recap(clusterID) }
            .safeAreaInset(edge: .bottom) { ProjectStatusView(model: model) }
    }
    private var comparison: some View {
        let before = Dictionary(uniqueKeysWithValues: snapshot.members(of: clusterID).map { ($0.id, $0) })
        let current = Dictionary(uniqueKeysWithValues: model.snapshot.members(of: clusterID).map { ($0.id, $0) })
        let added = Set(current.keys).subtracting(before.keys).count
        let removed = Set(before.keys).subtracting(current.keys).count
        let revised = before.values.filter { old in current[old.id].map { $0.originalFilename != old.originalFilename } ?? false }.count
        return VStack(alignment: .leading, spacing: 4) {
            Text("Since this moment: +\(added) sources, −\(removed) sources, \(revised) revised.")
            if cluster?.title != model.snapshot.clusters[clusterID]?.title { Text("Now named \(model.snapshot.clusters[clusterID]?.title ?? "Unknown")") }
        }.font(.footnote).foregroundStyle(.secondary)
    }
}

struct ProvenanceEventView: View {
    let event: ProvenanceEvent
    let model: ProjectViewModel
    var historical = false
    var body: some View {
        let payload = try? event.payload()
        List {
            Section { ProvenanceEventRow(event: event) }
            Section("Why is this here?") {
                Text(payload?.rationale ?? "History unavailable")
                LabeledContent("Origin", value: event.origin.capitalized)
                LabeledContent("Method", value: payload?.model ?? "Unknown")
                if let device = payload?.deviceContext { LabeledContent("Capture context", value: device) }
                ForEach((payload?.scores ?? [:]).keys.sorted(), id: \.self) { key in
                    LabeledContent(UUID(uuidString: key).flatMap { model.snapshot.clusters[$0]?.title } ?? key,
                        value: String(format: "%.3f", payload?.scores[key] ?? 0))
                }
            }
            if let memory = payload?.memory {
                Section("Source revision") {
                    NavigationLink { ProjectSourceView(memory: memory, model: model, historical: true) } label: { Text(memory.displayTitle) }
                    if [.capture, .revision, .imported].contains(event.kind), memory.kind == .text {
                        Button("Restore this note revision") { Task { await model.restoreRevision(event) } }
                    }
                }
            }
            if let revisionID = payload?.sourceRevisionID, let source = model.snapshot.events.first(where: { $0.id == revisionID }) {
                Section("Evidence used for this decision") {
                    NavigationLink { ProvenanceEventView(event: source, model: model, historical: true) } label: { ProvenanceEventRow(event: source) }
                }
            }
            if let payload, !payload.assignments.isEmpty {
                Section(event.kind == .splitProposal ? "Proposed sources" : "Affected sources") {
                    ForEach(payload.assignments.keys.sorted(), id: \.self) { key in
                        if let id = UUID(uuidString: key), let memory = model.snapshot.memories[id] { Text(memory.displayTitle) }
                    }
                }
            }
            if let payload, !payload.citedEventIDs.isEmpty {
                Section(event.kind == .recap ? "Activity behind this recap" : "Evidence behind this change") {
                    ForEach(model.snapshot.events.filter { payload.citedEventIDs.contains($0.id) }) { source in
                        NavigationLink { ProvenanceEventView(event: source, model: model, historical: true) } label: { ProvenanceEventRow(event: source) }
                    }
                }
            }
            if !historical, !model.snapshot.resolved.contains(event.id) {
                if event.kind == .splitProposal {
                    Button("Accept split") { Task { await model.resolve(event, accept: true) } }
                    Button("Keep together") { Task { await model.resolve(event, accept: false) } }
                } else if [.merge, .placement, .split, .rename].contains(event.kind) {
                    Button("Undo this change") { Task { await model.undo(event) } }
                }
            }
        }.navigationTitle(event.kind.label).safeAreaInset(edge: .bottom) { ProjectStatusView(model: model) }
    }
}

private struct RiverStreamMark: View {
    let event: ProvenanceEvent
    let lineage: [UUID]
    var body: some View {
        Canvas { context, size in
            let payload = try? event.payload()
            let lanes = max(1, min(4, lineage.count))
            func x(_ id: UUID?) -> CGFloat {
                let index = id.flatMap { lineage.firstIndex(of: $0) } ?? 0
                return 7 + CGFloat(index % lanes) * 12
            }
            for lane in 0..<lanes {
                var line = Path()
                let position = 7 + CGFloat(lane) * 12
                line.move(to: CGPoint(x: position, y: 0)); line.addLine(to: CGPoint(x: position, y: size.height))
                context.stroke(line, with: .color(.accentColor.opacity(0.16)), lineWidth: 2)
            }
            let target = x(payload?.clusterID ?? event.memoryID)
            if event.kind == .merge {
                for parent in payload?.parents ?? [] {
                    var tributary = Path()
                    tributary.move(to: CGPoint(x: x(parent), y: 0))
                    tributary.addCurve(to: CGPoint(x: target, y: size.height / 2),
                        control1: CGPoint(x: x(parent), y: size.height / 3), control2: CGPoint(x: target, y: size.height / 3))
                    context.stroke(tributary, with: .color(.accentColor), lineWidth: 2)
                }
            }
            let diameter: CGFloat = event.kind == .merge ? 12 : 8
            context.fill(Path(ellipseIn: CGRect(x: target - diameter / 2, y: size.height / 2 - diameter / 2, width: diameter, height: diameter)), with: .color(.accentColor))
        }
    }
}

struct ProjectSourceView: View {
    let memory: MemoryItem
    let model: ProjectViewModel
    var historical = false
    @State private var selected: Set<UUID> = []
    @State private var preview: URL?
    var body: some View {
        List {
            Section {
                Text(memory.displayTitle).font(.title2.bold())
                LabeledContent("Captured", value: memory.createdAt.formatted(date: .abbreviated, time: .shortened))
                Text(memory.extractedText ?? memory.userCaption ?? memory.displaySummary ?? "Extraction is pending. The original is saved.").textSelection(.enabled)
                Button("Open saved original") {
                    do { preview = try LibraryFileStore(directoryURL: LibraryFileStore.defaultDirectory()).url(for: memory.originalFilename) }
                    catch { model.errorMessage = error.localizedDescription }
                }
            }
            Section("Provenance") {
                ForEach(model.snapshot.events.filter { $0.memoryID == memory.id && $0.kind != .processing }.reversed()) { event in
                    NavigationLink { ProvenanceEventView(event: event, model: model, historical: historical) } label: { ProvenanceEventRow(event: event) }
                }
            }
            if !historical, model.snapshot.memories[memory.id]?.isArchived == false {
                Section("Topics") {
                    ForEach(model.snapshot.activeClusters) { cluster in
                        Toggle(cluster.title, isOn: Binding(get: { selected.contains(cluster.id) }, set: {
                            if $0 { selected.insert(cluster.id) } else { selected.remove(cluster.id) }
                        }))
                    }
                    Button("Save topic correction") { Task { await model.assign(memory.id, clusters: selected) } }
                    Text("Choose several topics, or clear all to start a separate thread. Your choice is preserved during automatic organization.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Archive memory") { Task { await model.archive(memory.id, archived: true) } }
            }
        }.navigationTitle(historical ? "Saved revision" : "Memory").quickLookPreview($preview)
            .onAppear { selected = model.snapshot.memberships[memory.id, default: []] }
            .safeAreaInset(edge: .bottom) { ProjectStatusView(model: model) }
    }
}

struct ProjectArchiveView: View {
    let model: ProjectViewModel
    var body: some View {
        List {
            Section { Text("Archived originals and history stay on this device. Restore a memory to return it to browsing and search.").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(model.snapshot.memories.values.filter(\.isArchived).sorted { $0.updatedAt > $1.updatedAt }) { memory in
                VStack(alignment: .leading, spacing: 8) {
                    NavigationLink { ProjectSourceView(memory: memory, model: model, historical: true) } label: { Text(memory.displayTitle) }
                    Button("Restore") { Task { await model.archive(memory.id, archived: false) } }
                        .accessibilityLabel("Restore \(memory.displayTitle)")
                }
            }
        }.navigationTitle("Archive").safeAreaInset(edge: .bottom) { ProjectStatusView(model: model) }
    }
}
