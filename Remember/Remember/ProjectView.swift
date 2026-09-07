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
        }
    }

    private var timeline: some View {
        List {
            Section {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(model.snapshot.activeClusters) { cluster in
                            NavigationLink { ClusterRiverView(clusterID: cluster.id, model: model) } label: {
                                Text(cluster.title).font(.subheadline.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(.tint.opacity(0.1), in: Capsule())
                            }.buttonStyle(.plain).accessibilityIdentifier("project-topic-\(cluster.id)")
                        }
                    }
                }.scrollIndicators(.hidden)
                Picker("Source", selection: $kind) {
                    Text("All sources").tag(nil as MemoryKind?)
                    ForEach([MemoryKind.text, .image, .audio, .pdf, .link], id: \.self) { Text($0.rawValue.capitalized).tag(Optional($0)) }
                }
                Picker("Date", selection: $range) { ForEach(MemoryDateRange.allCases) { Text($0.label).tag($0) } }
                Picker("Topic", selection: $topic) {
                    Text("All topics").tag(nil as UUID?)
                    ForEach(model.snapshot.activeClusters) { Text($0.title).tag(Optional($0.id)) }
                }
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
