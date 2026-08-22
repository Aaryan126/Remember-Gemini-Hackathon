import SwiftUI

struct LivingWikiView: View {
    let viewModel: LibraryViewModel
    @State private var showsCompilerInfo = false

    var body: some View {
        NavigationStack {
            List {
                compilerSection

                if viewModel.wikiPages.isEmpty, !viewModel.isCompilingWiki {
                    Section {
                        ContentUnavailableView {
                            Label("The wiki is ready to grow", systemImage: "leaf.fill")
                        } description: {
                            Text("Remember automatically turns analyzed memories into projects, concepts, decisions, constraints, and open questions while the app is open.")
                        }
                    }
                } else if viewModel.filteredWikiPages.isEmpty {
                    Section {
                        ContentUnavailableView.search(text: viewModel.wikiSearchQuery)
                    }
                } else {
                    ForEach(WikiPageKind.allCases) { kind in
                        let pages = viewModel.filteredWikiPages.filter { $0.kind == kind }
                        if !pages.isEmpty {
                            Section(kind.label) {
                                ForEach(pages) { page in
                                    NavigationLink {
                                        LivingWikiPageDetailView(pageID: page.id, viewModel: viewModel)
                                    } label: {
                                        WikiPageRow(page: page)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Living Wiki")
            .searchable(text: Binding(
                get: { viewModel.wikiSearchQuery },
                set: { viewModel.wikiSearchQuery = $0 }
            ), prompt: "Search pages and aliases")
            .refreshable {
                await viewModel.synchronize()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Wiki options", systemImage: "ellipsis.circle") {
                        Button("How Living Wiki works", systemImage: "info.circle") {
                            showsCompilerInfo = true
                        }

                        Divider()

                        Button("Return to Remember v1", systemImage: "arrow.uturn.backward") {
                            viewModel.setLivingWikiEnabled(false)
                        }
                    }
                }
            }
            .sheet(isPresented: $showsCompilerInfo) {
                LivingWikiInfoView()
                    .presentationDetents([.medium, .large])
            }
            .safeAreaInset(edge: .bottom) {
                if let errorMessage = viewModel.errorMessage {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(errorMessage)
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Dismiss") { viewModel.clearError() }
                            .font(.footnote.weight(.semibold))
                    }
                    .padding()
                    .background(.bar)
                }
            }
        }
    }

    private var compilerSection: some View {
        Section {
            if viewModel.isCompilingWiki {
                HStack(spacing: 12) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Building from one memory")
                            .font(.subheadline.weight(.semibold))
                        Text("Gemma is checking whether it belongs on an existing page or starts something new.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            } else {
                Label {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(viewModel.wikiPages.count) \(viewModel.wikiPages.count == 1 ? "wiki page" : "wiki pages")")
                                .font(.headline)
                            Text(statusDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                } icon: {
                    Image(systemName: "books.vertical.fill")
                        .foregroundStyle(.indigo)
                }
                if viewModel.wikiQueueSummary.failed > 0 {
                    Label("Some memories need another try", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }

            if viewModel.wikiQueueSummary.failed > 0 {
                Button("Retry unfinished memories", systemImage: "arrow.clockwise") {
                    Task {
                        await viewModel.compileNextWikiMemory(retryFailures: true)
                    }
                }
                .disabled(viewModel.isCompilingWiki)
            }
        } footer: {
            Text("Remember builds automatically, one memory at a time, while the app is open. Your original saved items are never changed.")
        }
    }

    private var statusDescription: String {
        if viewModel.wikiQueueSummary.pending > 0 {
            return "\(viewModel.wikiQueueSummary.pending) \(viewModel.wikiQueueSummary.pending == 1 ? "memory" : "memories") queued automatically"
        }
        if viewModel.wikiQueueSummary.failed > 0 {
            return "Retry unfinished memories"
        }
        return "Up to date"
    }
}

private struct WikiPageRow: View {
    let page: WikiPage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: page.kind.systemImage)
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(page.title)
                    .font(.headline)
                Text(page.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Text(pageMetadata)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the page, sources, connections, and history")
    }

    private var pageMetadata: String {
        let date = page.updatedAt.formatted(date: .abbreviated, time: .omitted)
        if page.revisionNumber > 1 {
            return "Updated \(date) · \(page.revisionNumber) versions"
        }
        return "Created \(date)"
    }

    private var color: Color {
        switch page.kind {
        case .project: .blue
        case .concept: .yellow
        case .decision: .purple
        case .constraint: .orange
        case .openQuestion: .teal
        }
    }
}

private struct LivingWikiPageDetailView: View {
    let pageID: UUID
    let viewModel: LibraryViewModel

    @State private var snapshot: WikiPageSnapshot?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let snapshot {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(snapshot.page.kind.singularLabel, systemImage: snapshot.page.kind.systemImage)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            Text(snapshot.page.summary)
                                .font(.body)
                            if !snapshot.page.aliases.isEmpty {
                                Text("Also known as: \(snapshot.page.aliases.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(pageSourceSummary(snapshot))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 8)
                    }

                    if !snapshot.linkedPages.isEmpty {
                        Section("Connections") {
                            ForEach(snapshot.linkedPages) { link in
                                NavigationLink {
                                    LivingWikiPageDetailView(pageID: link.page.id, viewModel: viewModel)
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Label(link.page.title, systemImage: link.page.kind.systemImage)
                                            .font(.subheadline.weight(.semibold))
                                        Text(link.rationale)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                            }
                        }
                    }

                    Section {
                        if snapshot.evidence.isEmpty {
                            Text("The source memory was deleted. The versioned page remains available.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(snapshot.evidence) { source in
                                NavigationLink {
                                    MemoryDetailView(memoryID: source.memory.id, viewModel: viewModel)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(source.memory.displayTitle)
                                            .font(.subheadline.weight(.semibold))
                                        if source.evidence.effect == .contradicted {
                                            Label("Possible conflict", systemImage: "exclamationmark.triangle.fill")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.orange)
                                        } else {
                                            Text(sourceDescription(source))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(source.evidence.rationale)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(3)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Sources")
                    } footer: {
                        if !snapshot.evidence.isEmpty {
                            Text("These are the saved memories Gemma used to maintain this page.")
                        }
                    }

                    if snapshot.revisions.count > 1 {
                        Section("History") {
                            ForEach(snapshot.revisions) { revision in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Label(revisionTitle(revision), systemImage: revision.effect.systemImage)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(revision.effect.color)
                                        Spacer()
                                        Text("Version \(revision.revisionNumber)")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(revision.rationale)
                                        .font(.footnote)
                                    if let previous = revision.previousSummary,
                                       previous != revision.newSummary {
                                        DisclosureGroup("Compare versions") {
                                            VStack(alignment: .leading, spacing: 8) {
                                                Text("Before")
                                                    .font(.caption.bold())
                                                Text(previous)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                Text("After")
                                                    .font(.caption.bold())
                                                Text(revision.newSummary)
                                                    .font(.caption)
                                            }
                                            .padding(.top, 4)
                                        }
                                    }
                                    Text(revision.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .navigationTitle(snapshot.page.title)
                .navigationBarTitleDisplayMode(.inline)
            } else if isLoading {
                ProgressView("Opening page…")
            } else {
                ContentUnavailableView("Page unavailable", systemImage: "books.vertical")
            }
        }
        .task(id: pageID) {
            isLoading = true
            snapshot = await viewModel.wikiPageSnapshot(id: pageID)
            isLoading = false
        }
    }

    private func pageSourceSummary(_ snapshot: WikiPageSnapshot) -> String {
        let sourceCount = snapshot.evidence.count
        let date = snapshot.page.updatedAt.formatted(date: .abbreviated, time: .omitted)
        return "Built from \(sourceCount) saved \(sourceCount == 1 ? "memory" : "memories") · Updated \(date)"
    }

    private func sourceDescription(_ source: WikiEvidenceSource) -> String {
        let action: String
        switch source.evidence.effect {
        case .introduced: action = "Created this page"
        case .strengthened: action = "Added supporting information"
        case .updated: action = "Updated this page"
        case .contradicted: action = "Raised a possible conflict"
        case .related: action = "Connected to this page"
        }
        let date = source.memory.createdAt.formatted(date: .abbreviated, time: .omitted)
        return "\(action) · Saved \(date)"
    }

    private func revisionTitle(_ revision: WikiRevision) -> String {
        switch revision.effect {
        case .introduced: "Page created"
        case .strengthened: "Supporting evidence added"
        case .updated: "Page updated"
        case .contradicted: "Possible conflict found"
        case .related: "Connection added"
        }
    }
}

private struct LivingWikiInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Your memories stay original", systemImage: "lock.doc.fill")
                    Text("The Living Wiki is a separate layer. Gemma reads saved memories but never rewrites them.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Label("Likely pages are found locally", systemImage: "text.magnifyingglass")
                    Text("Remember combines private semantic similarity with titles, alternate names, summaries, and nearby connections before asking Gemma whether the memory belongs somewhere existing or starts a new page.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Label("Every change keeps its sources", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    Text("When a page changes, Remember stores the supporting memory and a versioned explanation so you can inspect what happened later.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("How Living Wiki works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private extension WikiChangeKind {
    var systemImage: String {
        switch self {
        case .introduced: "plus.circle.fill"
        case .strengthened: "arrow.up.circle.fill"
        case .updated: "arrow.triangle.2.circlepath.circle.fill"
        case .contradicted: "exclamationmark.triangle.fill"
        case .related: "link.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .introduced: .green
        case .strengthened: .blue
        case .updated: .purple
        case .contradicted: .orange
        case .related: .teal
        }
    }
}
