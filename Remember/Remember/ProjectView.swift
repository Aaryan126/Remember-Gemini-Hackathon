import SwiftUI

struct ProjectView: View {
    let model: ProjectViewModel
    let onAsk: () -> Void
    @AppStorage("remember.project.homeView") private var home = "Timeline"
    @State private var kind: MemoryKind?
    @State private var range = MemoryDateRange.anytime
    @State private var topic: UUID?
    @State private var limit = 60

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Project view", selection: $home) {
                    Text("Timeline").tag("Timeline")
                    Text("Graph").tag("Graph")
                }.pickerStyle(.segmented).accessibilityIdentifier("Project view").padding()
                if model.isLoading {
                    ProgressView("Opening your history…").frame(maxHeight: .infinity)
                } else if model.snapshot.memories.isEmpty {
                    ContentUnavailableView("Every memory starts a thread", systemImage: "point.3.connected.trianglepath.dotted",
                        description: Text("Capture a note, photo, or voice memo in Memories. Its story starts here immediately."))
                } else if home == "Graph" {
                    ProjectGraphView(model: model)
                } else {
                    timeline
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                TopLevelToolbar(title: "Project", onAsk: onAsk)
                ToolbarItem(placement: .secondaryAction) {
                    NavigationLink { ProjectArchiveView(model: model) } label: { Label("Archive", systemImage: "archivebox") }
                }
            }
            .safeAreaInset(edge: .bottom) { ProjectStatusView(model: model) }
            .onChange(of: model.snapshot.activeClusters.map(\.id)) { _, ids in
                if let topic, !ids.contains(topic) { self.topic = nil }
            }
        }
    }

    private var timeline: some View {
        List {
            Section {
                Picker("Source", selection: $kind) {
                    Text("All sources").tag(nil as MemoryKind?)
                    ForEach([MemoryKind.text, .image, .video, .audio, .pdf, .link], id: \.self) { Text($0.rawValue.capitalized).tag(Optional($0)) }
                }
                Picker("Date", selection: $range) { ForEach(MemoryDateRange.allCases) { Text($0.label).tag($0) } }
                Picker("Topic", selection: $topic) {
                    Text("All topics").tag(nil as UUID?)
                    ForEach(model.snapshot.activeClusters) { Text($0.title).tag(Optional($0.id)) }
                }
            }
            Section {
                ForEach(model.snapshot.activeClusters) { cluster in
                    let count = model.snapshot.members(of: cluster.id).count
                    NavigationLink { ClusterRiverView(clusterID: cluster.id, model: model) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(cluster.title).font(.body.weight(.medium))
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(count) \(count == 1 ? "memory" : "memories")")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                    .accessibilityLabel(cluster.title)
                    .accessibilityValue("\(count) \(count == 1 ? "memory" : "memories")")
                    .accessibilityIdentifier("project-topic-\(cluster.id)")
                }
            } header: {
                Text("All threads")
            } footer: {
                Text("Open a thread to explore its River. Map connections reflect shared sources or tags.")
            }
            Section("Your history") {
                ForEach(Array(events.prefix(limit))) { event in
                    NavigationLink { ProvenanceEventView(event: event, model: model) } label: {
                        ProvenanceEventRow(event: event, displayMemory: event.memoryID.flatMap { model.snapshot.memories[$0] })
                    }
                }
                if events.isEmpty { Text("No activity matches these filters.").foregroundStyle(.secondary) }
                if events.count > limit { Button("Show earlier activity") { limit += 60 } }
            }
        }.listStyle(.plain)
    }

    private var events: [ProvenanceEvent] {
        model.snapshot.events.reversed().filter { event in
            guard ![.checkpoint, .enrichment, .recap, .processing].contains(event.kind),
                  range.includes(event.timestamp, now: Date()), let payload = try? event.payload() else { return false }
            if let id = event.memoryID, model.snapshot.memories[id]?.isArchived == true, event.kind != .archive { return false }
            if let kind, event.memoryID.flatMap({ model.snapshot.memories[$0]?.kind }) != kind { return false }
            if let topic {
                return payload.clusterID == topic || payload.parents.contains(topic)
                    || event.memoryID.map { model.snapshot.memberships[$0, default: []].contains(topic) } == true
            }
            return true
        }
    }
}
