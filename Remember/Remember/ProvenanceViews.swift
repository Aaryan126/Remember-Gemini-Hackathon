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
    var showsRiverJunction = false
    var body: some View {
        let payload = try? event.payload()
        HStack(alignment: .top, spacing: 12) {
            if showsIcon {
                Image(systemName: event.kind == .merge ? "arrow.triangle.merge" : event.kind == .archive ? "archivebox" : "circle.fill")
                    .font(.system(size: event.kind == .capture ? 10 : 18)).foregroundStyle(.tint).frame(width: 24, height: 24)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(displayMemory?.displayTitle ?? payload?.memory?.displayTitle ?? payload?.title ?? event.kind.label).font(.headline).lineLimit(2)
                    .modifier(RiverTitleJunction(kind: event.kind, isVisible: showsRiverJunction))
                Text(event.kind.label + " · " + event.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
                if let rationale = payload?.rationale, !rationale.isEmpty, rationale != event.kind.label {
                    Text(rationale).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }.padding(.vertical, 5)
    }
}

struct ClusterRiverView: View {
    let clusterID: UUID
    let model: ProjectViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isHistorical = false
    @State private var date = Date()
    @State private var title = ""
    @State private var showsRename = false
    @State private var showsDelete = false
    @State private var isDeleting = false
    @State private var selectedMemory: MemoryItem?
    @State private var selectedMemoryIsHistorical = false
    @State private var showsMemory = false
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
            Section("River") {
                if events.count > limit {
                    Button("Unfold earlier history") { limit += 50 }
                        .listRowInsets(EdgeInsets(top: 16, leading: 44, bottom: 16, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(RiverStreamMark())
                }
                ForEach(Array(events.suffix(limit))) { event in
                    Group {
                        if let original = event.riverSource {
                            let source = event.riverMemory(in: snapshot)
                            VStack(alignment: .leading, spacing: 12) {
                                Button { openMemory(source ?? original) } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text((source ?? original).displayTitle).font(.headline).lineLimit(3)
                                                .modifier(RiverTitleJunction(kind: event.kind))
                                            Text((event.kind == .revision ? "Revised · " : "") +
                                                 (event.kind == .revision ? event.timestamp : original.createdAt)
                                                    .formatted(date: .abbreviated, time: .shortened))
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Opens this memory; Back returns to the river")
                                .accessibilityIdentifier("project-source-\(original.id)")
                                RiverMediaView(memory: original, onOpenMemory: { openMemory(source ?? original) })
                                    .id(original.originalFilename)
                                if original.kind == .text, let text = original.userCaption, !text.isEmpty {
                                    Text(text).font(.body).textSelection(.enabled)
                                }
                            }
                        } else {
                            NavigationLink { ProvenanceEventView(event: event, model: model, historical: isHistorical) } label: {
                                ProvenanceEventRow(event: event, displayMemory: event.memoryID.flatMap { snapshot.memories[$0] }, showsIcon: false, showsRiverJunction: true)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 16, leading: 44, bottom: 16, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(RiverStreamMark())
                }
            }
        }.listStyle(.insetGrouped).listRowSpacing(0)
            .navigationTitle("Thread history").navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showsMemory) {
                if let selectedMemory {
                    ProjectSourceView(memory: selectedMemory, model: model, historical: selectedMemoryIsHistorical)
                }
            }
            .toolbar {
                if !isHistorical, cluster?.retired == false, !snapshot.archivedClusterIDs.contains(clusterID) {
                    Menu {
                        Button("Edit thread", systemImage: "pencil") { title = cluster?.title ?? ""; showsRename = true }
                        Button("Delete thread…", systemImage: "trash", role: .destructive) { showsDelete = true }
                    } label: {
                        Image(systemName: "ellipsis").rotationEffect(.degrees(90))
                            .frame(width: 28, height: 28)
                    }
                    .accessibilityLabel("Thread options")
                    .disabled(isDeleting)
                }
            }
            .alert("Edit thread", isPresented: $showsRename) {
                TextField("Topic name", text: $title)
                Button("Save") { Task { await model.rename(clusterID, title: title) } }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Delete this thread?", isPresented: $showsDelete, titleVisibility: .visible) {
                Button("Delete thread", role: .destructive) {
                    Task {
                        isDeleting = true
                        let saved = await model.archiveThread(clusterID, archived: true)
                        isDeleting = false
                        if saved { dismiss() }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The thread moves to Archive. Its memories stay in Memories and any other threads. You can restore the thread from Settings → Archive.")
            }
            .task { await model.recap(clusterID) }
            .safeAreaInset(edge: .bottom) { ProjectStatusView(model: model) }
    }
    private func openMemory(_ memory: MemoryItem) {
        selectedMemory = memory
        selectedMemoryIsHistorical = isHistorical ||
            model.snapshot.memories[memory.id]?.originalFilename != memory.originalFilename
        showsMemory = true
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
    var body: some View {
        ZStack {
            Color(uiColor: .secondarySystemGroupedBackground)
            Canvas { context, size in
                // Row backgrounds include the content insets. With zero row
                // spacing, these full-height rails meet even beside tall media.
                let x: CGFloat = 16
                var trunk = Path()
                trunk.move(to: CGPoint(x: x, y: 0))
                trunk.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(trunk, with: .color(.accentColor.opacity(0.45)), lineWidth: 2)
            }
        }.accessibilityHidden(true).allowsHitTesting(false)
    }
}

private struct RiverTitleJunction: ViewModifier {
    let kind: ProvenanceKind
    var isVisible = true
    @ScaledMetric(relativeTo: .headline) private var capHeight = UIFont.preferredFont(
        forTextStyle: .headline,
        compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)
    ).capHeight

    func body(content: Content) -> some View {
        content.overlay(alignment: Alignment(horizontal: .leading, vertical: .firstTextBaseline)) {
            if isVisible {
                Canvas { context, _ in
                    let x: CGFloat = 6
                    let junction: CGFloat = 18
                    var branch = Path()
                    branch.move(to: CGPoint(x: x, y: junction))
                    branch.addLine(to: CGPoint(x: 24, y: junction))
                    context.stroke(branch, with: .color(.accentColor.opacity(0.3)), lineWidth: 2)
                    if kind == .merge {
                        var tributary = Path()
                        tributary.move(to: CGPoint(x: 22, y: 0))
                        tributary.addCurve(to: CGPoint(x: x, y: junction),
                            control1: CGPoint(x: 22, y: 10), control2: CGPoint(x: x, y: 10))
                        context.stroke(tributary, with: .color(.accentColor), lineWidth: 2)
                    }
                    let diameter: CGFloat = kind == .merge ? 12 : 8
                    context.fill(Path(ellipseIn: CGRect(x: x - diameter / 2, y: junction - diameter / 2,
                                                       width: diameter, height: diameter)), with: .color(.accentColor))
                }
                .frame(width: 24, height: 24)
                // The first baseline is measured from the actual title, even
                // when it wraps. Half the scaled cap height gives its optical center.
                .alignmentGuide(.firstTextBaseline) { _ in 18 + capHeight / 2 }
                .offset(x: -34)
                .accessibilityHidden(true).allowsHitTesting(false)
            }
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
                RiverMediaView(memory: memory).id(memory.originalFilename)
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
            .onAppear { selected = model.snapshot.memberships[memory.id, default: []].subtracting(model.snapshot.archivedClusterIDs) }
            .safeAreaInset(edge: .bottom) { ProjectStatusView(model: model) }
    }
}

struct ProjectArchiveView: View {
    let model: ProjectViewModel
    var body: some View {
        List {
            Section { Text("Restore deleted threads or archived memories here. Their originals and history stay on this device.").font(.subheadline).foregroundStyle(.secondary) }
            if !model.snapshot.archivedClusters.isEmpty {
                Section("Threads") {
                    ForEach(model.snapshot.archivedClusters) { cluster in
                        HStack {
                            Text(cluster.title)
                            Spacer()
                            Button("Restore") { Task { _ = await model.archiveThread(cluster.id, archived: false) } }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Restore thread \(cluster.title)")
                        }
                    }
                }
            }
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
