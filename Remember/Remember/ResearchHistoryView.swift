import SwiftUI

struct ResearchHistoryView: View {
    let viewModel: LibraryViewModel

    @State private var history: [ProjectMemoryRunSnapshot] = []
    @State private var pages: [WikiPageSnapshot] = []
    @State private var selectedMode: ProjectMemoryHistoryMode = .story
    @State private var isLoading = true
    @State private var isChecking = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("Project memory view", selection: $selectedMode) {
                ForEach(ProjectMemoryHistoryMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            Group {
                switch selectedMode {
                case .story:
                    ProjectStoryView(
                        history: history,
                        viewModel: viewModel,
                        isChecking: isChecking,
                        runCheck: runCheck
                    )
                case .map:
                    ProjectMemoryMapView(pages: pages, viewModel: viewModel)
                case .audit:
                    ProjectMemoryAuditView(history: history, viewModel: viewModel)
                }
            }
        }
        .navigationTitle("Project Story")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading {
                ProgressView("Opening project memory…")
            }
        }
        .task { await reload() }
    }

    private func reload() async {
        isLoading = true
        async let loadedHistory = viewModel.projectMemoryHistory()
        async let loadedPages = viewModel.projectMemoryPageSnapshots()
        history = await loadedHistory
        pages = await loadedPages
        isLoading = false
    }

    private func runCheck() {
        guard !isChecking else { return }
        isChecking = true
        Task {
            await viewModel.runProjectMemoryCheck()
            await reload()
            isChecking = false
        }
    }
}

private enum ProjectMemoryHistoryMode: String, CaseIterable, Identifiable {
    case story
    case map
    case audit

    var id: String { rawValue }
    var label: String {
        switch self {
        case .story: "Story"
        case .map: "Map"
        case .audit: "Audit"
        }
    }
    var systemImage: String {
        switch self {
        case .story: "text.book.closed"
        case .map: "point.3.connected.trianglepath.dotted"
        case .audit: "checklist.checked"
        }
    }
}

private struct ProjectStoryView: View {
    let history: [ProjectMemoryRunSnapshot]
    let viewModel: LibraryViewModel
    let isChecking: Bool
    let runCheck: () -> Void

    private var storyRuns: [ProjectMemoryRunSnapshot] {
        let integrations = history.filter { $0.run.operation == .compile }
        guard let latestCheck = history.first(where: { $0.run.operation == .lint }) else {
            return integrations
        }
        return (integrations + [latestCheck]).sorted { $0.run.startedAt > $1.run.startedAt }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("How your project knowledge evolved", systemImage: "sparkles.rectangle.stack.fill")
                        .font(.headline)
                    Text("Each chapter shows which saved item changed durable knowledge. Open it to inspect the exact evidence and checks.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section {
                Button(action: runCheck) {
                    Label(isChecking ? "Checking project memory…" : "Check project memory quality", systemImage: "checkmark.shield")
                }
                .disabled(isChecking)
            } footer: {
                Text("This local check looks for broken evidence, revision problems, and likely duplicate pages. It never changes content.")
            }

            if storyRuns.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No project story yet",
                        systemImage: "text.book.closed",
                        description: Text("The next saved item that changes Project Memory will begin the story.")
                    )
                }
            } else {
                Section("Latest chapters") {
                    ForEach(storyRuns) { snapshot in
                        NavigationLink {
                            ResearchRunDetailView(snapshot: snapshot, viewModel: viewModel)
                        } label: {
                            ProjectStoryCard(snapshot: snapshot)
                        }
                    }
                }
            }
        }
        .refreshable {
            // Pull-to-refresh is handled by the parent task after navigation; this
            // keeps the story surface read-only and avoids duplicate compiler runs.
        }
    }
}

private struct ProjectStoryCard: View {
    let snapshot: ProjectMemoryRunSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: storyIcon)
                    .foregroundStyle(storyColor)
                    .frame(width: 28, height: 28)
                    .background(storyColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(storyTitle)
                        .font(.headline)
                    Text(snapshot.run.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Text(storySummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let source = snapshot.memoryTitle {
                flowStep(icon: "doc.text.image", title: source, caption: "Saved memory", color: .blue)
                Image(systemName: "arrow.down")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 11)
            }

            ForEach(snapshot.changes) { change in
                flowStep(
                    icon: change.pageKind.systemImage,
                    title: change.pageTitle,
                    caption: change.revision.effect.userFacingLabel,
                    color: change.revision.effect.color
                )
            }

            if snapshot.changes.isEmpty {
                Label(emptyResultLabel, systemImage: snapshot.run.status.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(snapshot.run.status.color)
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }

    private func flowStep(icon: String, title: String, caption: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var storyTitle: String {
        if snapshot.run.operation == .lint {
            return snapshot.run.status == .attention ? "Project memory noticed a possible overlap" : "Project memory passed its quality check"
        }
        switch snapshot.run.status {
        case .kept: return snapshot.changes.count == 1 ? "Project knowledge changed" : "Several project pages evolved"
        case .discarded: return "No durable change was needed"
        case .failed: return "A memory could not be integrated"
        default: return snapshot.run.operation.label
        }
    }

    private var storySummary: String {
        if snapshot.run.operation == .lint,
           let duplicateCheck = snapshot.checks.first(where: { $0.checkID == "wiki.semantic_uniqueness" }),
           !duplicateCheck.passed {
            return duplicateCheck.message
        }
        if let change = snapshot.changes.first {
            return change.revision.rationale
        }
        return snapshot.run.rationale
    }

    private var emptyResultLabel: String {
        switch snapshot.run.status {
        case .discarded: "Kept the existing project memory unchanged"
        case .attention: "Both source histories were preserved"
        case .failed: "The original saved item is still safe"
        default: snapshot.run.status.label
        }
    }

    private var storyIcon: String {
        snapshot.run.operation == .lint ? "checkmark.shield.fill" : snapshot.run.status.systemImage
    }

    private var storyColor: Color {
        snapshot.run.operation == .lint && snapshot.run.status == .passed ? .green : snapshot.run.status.color
    }
}

private struct ProjectMemoryMapView: View {
    let pages: [WikiPageSnapshot]
    let viewModel: LibraryViewModel

    private var layout: ProjectMemoryMapLayout { ProjectMemoryMapLayout(pages: pages) }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Knowledge map", systemImage: "point.3.connected.trianglepath.dotted")
                        .font(.headline)
                    Text("Solid lines are explicit connections. Dotted lines mean two pages grew from the same saved evidence.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            if pages.isEmpty {
                Section {
                    ContentUnavailableView("No pages to map", systemImage: "point.3.connected.trianglepath.dotted")
                }
            } else {
                Section("Project knowledge") {
                    ScrollView([.horizontal, .vertical]) {
                        ZStack(alignment: .topLeading) {
                            Canvas { context, _ in
                                for edge in layout.edges {
                                    guard let start = layout.positions[edge.sourceID],
                                          let end = layout.positions[edge.targetID] else { continue }
                                    var path = Path()
                                    path.move(to: start)
                                    path.addLine(to: end)
                                    context.stroke(
                                        path,
                                        with: .color(edge.isExplicit ? .indigo.opacity(0.75) : .secondary.opacity(0.45)),
                                        style: StrokeStyle(lineWidth: edge.isExplicit ? 2 : 1.5, dash: edge.isExplicit ? [] : [5, 5])
                                    )
                                }
                            }
                            .accessibilityHidden(true)

                            ForEach(pages, id: \.page.id) { snapshot in
                                NavigationLink {
                                    LivingWikiPageDetailView(pageID: snapshot.page.id, viewModel: viewModel)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Label(snapshot.page.kind.singularLabel, systemImage: snapshot.page.kind.systemImage)
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(snapshot.page.kind.mapColor)
                                        Text(snapshot.page.title)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)
                                        Text("\(snapshot.evidence.count) source\(snapshot.evidence.count == 1 ? "" : "s")")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(width: 152, height: 72, alignment: .leading)
                                    .padding(10)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(snapshot.page.kind.mapColor.opacity(0.45)))
                                }
                                .buttonStyle(.plain)
                                .position(layout.positions[snapshot.page.id] ?? .zero)
                            }
                        }
                        .frame(width: layout.width, height: layout.height)
                        .padding(8)
                    }
                    .frame(minHeight: min(layout.height + 16, 520))
                }

                if !layout.edges.isEmpty {
                    Section("Connections") {
                        ForEach(layout.edges) { edge in
                            HStack(spacing: 8) {
                                Image(systemName: edge.isExplicit ? "link" : "doc.on.doc")
                                    .foregroundStyle(edge.isExplicit ? .indigo : .secondary)
                                Text("\(layout.title(for: edge.sourceID)) → \(layout.title(for: edge.targetID))")
                                    .font(.caption)
                                Spacer()
                                Text(edge.isExplicit ? "Linked" : "Shared source")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct ProjectMemoryMapEdge: Identifiable {
    let sourceID: UUID
    let targetID: UUID
    let isExplicit: Bool
    var id: String { "\(sourceID.uuidString):\(targetID.uuidString)" }
}

private struct ProjectMemoryMapLayout {
    let snapshots: [WikiPageSnapshot]
    let positions: [UUID: CGPoint]
    let edges: [ProjectMemoryMapEdge]
    let width: CGFloat
    let height: CGFloat

    init(pages: [WikiPageSnapshot]) {
        snapshots = pages
        let grouped = Dictionary(grouping: pages, by: \.page.kind)
        let populatedKinds = WikiPageKind.allCases.filter { grouped[$0]?.isEmpty == false }
        var builtPositions: [UUID: CGPoint] = [:]
        var largestColumn = 1
        for (column, kind) in populatedKinds.enumerated() {
            let columnPages = (grouped[kind] ?? []).sorted { $0.page.title < $1.page.title }
            largestColumn = max(largestColumn, columnPages.count)
            for (row, snapshot) in columnPages.enumerated() {
                builtPositions[snapshot.page.id] = CGPoint(x: 105 + CGFloat(column) * 210, y: 58 + CGFloat(row) * 112)
            }
        }
        positions = builtPositions
        width = max(320, 210 * CGFloat(max(populatedKinds.count, 1)))
        height = max(180, 112 * CGFloat(largestColumn))

        let pageIDs = Set(pages.map(\.page.id))
        var edgeByKey: [String: ProjectMemoryMapEdge] = [:]
        func key(_ left: UUID, _ right: UUID) -> String {
            [left.uuidString, right.uuidString].sorted().joined(separator: ":")
        }
        for snapshot in pages {
            for link in snapshot.linkedPages where pageIDs.contains(link.page.id) {
                let edgeKey = key(snapshot.page.id, link.page.id)
                edgeByKey[edgeKey] = ProjectMemoryMapEdge(sourceID: snapshot.page.id, targetID: link.page.id, isExplicit: true)
            }
        }
        for leftIndex in pages.indices {
            for rightIndex in pages.indices where rightIndex > leftIndex {
                let left = pages[leftIndex]
                let right = pages[rightIndex]
                let sharedEvidence = !Set(left.evidence.map(\.memory.id)).isDisjoint(with: Set(right.evidence.map(\.memory.id)))
                let edgeKey = key(left.page.id, right.page.id)
                if sharedEvidence, edgeByKey[edgeKey] == nil {
                    edgeByKey[edgeKey] = ProjectMemoryMapEdge(sourceID: left.page.id, targetID: right.page.id, isExplicit: false)
                }
            }
        }
        edges = edgeByKey.values.sorted { $0.id < $1.id }
    }

    func title(for id: UUID) -> String {
        snapshots.first(where: { $0.page.id == id })?.page.title ?? "Page"
    }
}

private struct ProjectMemoryAuditView: View {
    let history: [ProjectMemoryRunSnapshot]
    let viewModel: LibraryViewModel

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Inspectable by design", systemImage: "checkmark.shield.fill")
                        .font(.headline)
                    Text("The chronological ledger of proposals, protected checks, and keep-or-discard decisions.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            } footer: {
                Text("Evidence and patch decisions are shown. Hidden model chain-of-thought is neither requested nor stored.")
            }

            if history.isEmpty {
                Section {
                    ContentUnavailableView("No audit runs yet", systemImage: "checklist.checked")
                }
            } else {
                Section("Operation log") {
                    ForEach(history) { snapshot in
                        NavigationLink {
                            ResearchRunDetailView(snapshot: snapshot, viewModel: viewModel)
                        } label: {
                            ResearchRunRow(snapshot: snapshot)
                        }
                    }
                }
            }
        }
    }
}

private struct ResearchRunRow: View {
    let snapshot: ProjectMemoryRunSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: snapshot.run.status.systemImage)
                .foregroundStyle(snapshot.run.status.color)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(snapshot.run.operation.label).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(snapshot.run.status.label).font(.caption.weight(.semibold)).foregroundStyle(snapshot.run.status.color)
                }
                if let memoryTitle = snapshot.memoryTitle {
                    Text(memoryTitle).font(.caption).lineLimit(1)
                }
                Text(runSummary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Text(snapshot.run.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private var runSummary: String {
        if snapshot.run.operation == .compile {
            return "\(snapshot.run.acceptedPageCount) of \(snapshot.run.proposedPageCount) proposed changes kept · \(snapshot.checks.filter(\.passed).count)/\(snapshot.checks.count) checks passed"
        }
        return "\(snapshot.checks.filter(\.passed).count)/\(snapshot.checks.count) quality checks passed"
    }
}

struct ResearchRunDetailView: View {
    let snapshot: ProjectMemoryRunSnapshot
    let viewModel: LibraryViewModel

    var body: some View {
        List {
            Section {
                HStack {
                    Label(snapshot.run.status.label, systemImage: snapshot.run.status.systemImage)
                        .font(.headline).foregroundStyle(snapshot.run.status.color)
                    Spacer()
                    Text(snapshot.run.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(snapshot.run.rationale)
                if snapshot.run.operation == .compile {
                    LabeledContent("Patch result", value: "\(snapshot.run.acceptedPageCount) of \(snapshot.run.proposedPageCount) kept")
                }
            }

            if let memoryID = snapshot.run.memoryID, let memoryTitle = snapshot.memoryTitle {
                Section("Source") {
                    NavigationLink { MemoryDetailView(memoryID: memoryID, viewModel: viewModel) } label: {
                        Label(memoryTitle, systemImage: "doc.text.image")
                    }
                }
            }

            if !snapshot.changes.isEmpty {
                Section("Accepted changes") {
                    ForEach(snapshot.changes) { change in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(change.pageTitle, systemImage: change.pageKind.systemImage).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("v\(change.revision.revisionNumber)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            Text(change.revision.rationale).font(.footnote)
                            if let previous = change.revision.previousSummary, previous != change.revision.newSummary {
                                DisclosureGroup("Inspect patch") {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Before").font(.caption.bold())
                                        Text(previous).font(.caption).foregroundStyle(.secondary)
                                        Text("After").font(.caption.bold())
                                        Text(change.revision.newSummary).font(.caption)
                                    }.padding(.top, 4)
                                }
                            } else {
                                Text(change.revision.newSummary).font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 3)
                    }
                }
            }

            Section("Protected checks") {
                if snapshot.checks.isEmpty {
                    Text("This run predates stored checks or ended before evaluation.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.checks) { check in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: check.passed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(check.passed ? .green : check.severity == .warning ? .orange : .red)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(check.label).font(.subheadline.weight(.semibold))
                                Text(check.message).font(.caption).foregroundStyle(.secondary)
                                Text(check.severity.rawValue.capitalized).font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }

            Section("Reproducibility") {
                LabeledContent("Program", value: snapshot.run.programVersion)
                LabeledContent("Prompt", value: snapshot.run.promptVersion)
                LabeledContent("Model", value: snapshot.run.modelVersion)
                LabeledContent("Run ID", value: snapshot.run.id.uuidString)
            }.font(.caption)
        }
        .navigationTitle(snapshot.run.operation.label)
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension ProjectMemoryRunStatus {
    var systemImage: String {
        switch self {
        case .running: "hourglass"
        case .kept: "checkmark.circle.fill"
        case .discarded: "minus.circle.fill"
        case .passed: "checkmark.shield.fill"
        case .attention: "exclamationmark.triangle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .running: .blue
        case .kept, .passed: .green
        case .discarded: .secondary
        case .attention: .orange
        case .failed: .red
        }
    }
}

private extension WikiChangeKind {
    var userFacingLabel: String {
        switch self {
        case .introduced: "New project knowledge"
        case .strengthened: "More evidence added"
        case .updated: "Existing knowledge updated"
        case .contradicted: "Possible conflict found"
        case .related: "New connection found"
        }
    }
}

private extension WikiPageKind {
    var mapColor: Color {
        switch self {
        case .project: .blue
        case .decision: .purple
        case .constraint: .orange
        case .experiment: .mint
        case .feedback: .pink
        case .person: .cyan
        case .openQuestion: .teal
        case .concept: .yellow
        }
    }
}
