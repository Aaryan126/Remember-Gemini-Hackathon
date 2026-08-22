import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel = LibraryViewModel()

    var body: some View {
        TabView {
            MemoryLibraryView(viewModel: viewModel)
                .tabItem {
                    Label("Memories", systemImage: "square.grid.2x2")
                }

            if viewModel.livingWikiEnabled {
                LivingWikiView(viewModel: viewModel)
                    .tabItem {
                        Label("Wiki", systemImage: "books.vertical.fill")
                    }
            }

            AskRememberView(viewModel: viewModel)
                .tabItem {
                    Label("Ask", systemImage: "bubble.left.and.bubble.right")
                }

            OrganizeView(viewModel: viewModel)
                .tabItem {
                    Label("Organize", systemImage: "folder")
                }

            PrivacyDashboardView(viewModel: viewModel)
                .tabItem {
                    Label("Privacy", systemImage: "lock.shield")
                }
        }
        .task {
            await viewModel.synchronize()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else {
                return
            }
            Task { await viewModel.synchronize() }
        }
    }
}

private struct MemoryLibraryView: View {
    let viewModel: LibraryViewModel
    @State private var showsVoiceCapture = false
    @State private var isSearchPresented = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.items.isEmpty, !viewModel.isSynchronizing {
                    emptyLibrary
                } else {
                    library
                }
            }
            .navigationTitle("Remember")
            .searchable(
                text: Binding(
                    get: { viewModel.searchQuery },
                    set: { viewModel.searchQuery = $0 }
                ),
                isPresented: $isSearchPresented,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search your memories"
            )
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Label("On-device", systemImage: "lock.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .accessibilityLabel("Private, on-device processing")
                    Button("Record Voice Memory", systemImage: "mic.circle.fill") {
                        showsVoiceCapture = true
                    }
                    Menu("Remember experience", systemImage: "ellipsis.circle") {
                        Toggle(
                            "Living Wiki",
                            isOn: Binding(
                                get: { viewModel.livingWikiEnabled },
                                set: { viewModel.setLivingWikiEnabled($0) }
                            )
                        )
                        Text("Turn this off to return to the v1 experience. Wiki data is preserved.")
                    }
                }
            }
            .sheet(isPresented: $showsVoiceCapture) {
                VoiceCaptureView(viewModel: viewModel)
            }
            .overlay {
                if viewModel.items.isEmpty, viewModel.isSynchronizing {
                    ProgressView("Opening your library…")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let errorMessage = viewModel.errorMessage {
                    errorBanner(errorMessage)
                }
            }
            .task(id: viewModel.searchRequest) {
                guard viewModel.searchRequest.isActive else {
                    viewModel.clearSearch()
                    return
                }
                do {
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    return
                }
                await viewModel.search()
            }
            .onSubmit(of: .search) {
                Task { await viewModel.searchWithGemma() }
            }
        }
    }

    private var library: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SearchFiltersView(viewModel: viewModel)

                if viewModel.isSynchronizing {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Importing and analyzing on this iPhone")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }

                if viewModel.searchRequest.isActive {
                    searchStatus
                }

                if viewModel.visibleItems.isEmpty, viewModel.searchRequest.isActive, !viewModel.isSearching {
                    noSearchResults
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(viewModel.visibleItems) { item in
                            NavigationLink {
                                MemoryDetailView(memoryID: item.id, viewModel: viewModel)
                            } label: {
                                MemoryCard(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .simultaneousGesture(
            TapGesture().onEnded {
                isSearchPresented = false
            }
        )
        .refreshable {
            await viewModel.synchronize()
        }
    }

    private var searchStatus: some View {
        HStack(spacing: 8) {
            if viewModel.isSearching {
                ProgressView()
                    .controlSize(.small)
                Text(viewModel.isGemmaSearching ? "Gemma is understanding your query…" : "Searching on this iPhone…")
            } else {
                Text("\(viewModel.visibleItems.count) \(viewModel.visibleItems.count == 1 ? "result" : "results")")
            }
            Spacer()
            if viewModel.usedGemmaForCurrentSearch {
                Label("Gemma", systemImage: "sparkles")
                    .foregroundStyle(.blue)
            } else if !viewModel.searchRequest.normalizedQuery.isEmpty {
                Button("Search with Gemma", systemImage: "sparkles") {
                    Task { await viewModel.searchWithGemma() }
                }
                .disabled(viewModel.isSearching)
            } else {
                Label("Private", systemImage: "lock.fill")
                    .foregroundStyle(.green)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private var noSearchResults: some View {
        ContentUnavailableView {
            Label("No matching memories", systemImage: "magnifyingglass")
        } description: {
            Text("Try different words or clear one of the filters. Only memories that have finished analyzing are searchable.")
        } actions: {
            Button("Clear Search") {
                viewModel.clearSearch()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var emptyLibrary: some View {
        ContentUnavailableView {
            Label("Start remembering", systemImage: "sparkles.rectangle.stack")
        } description: {
            Text("Share something from another app or record a voice memory. It stays on your iPhone and is organized here.")
        } actions: {
            Button("Record Voice Memory", systemImage: "mic.fill") {
                showsVoiceCapture = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Dismiss") { viewModel.clearError() }
                .font(.footnote.weight(.semibold))
        }
        .padding()
        .background(.bar)
    }
}

private struct SearchFiltersView: View {
    let viewModel: LibraryViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    filterButton("All types", selected: viewModel.selectedKind == nil) {
                        viewModel.selectedKind = nil
                    }
                    filterButton("Voice", selected: viewModel.selectedKind == .audio) {
                        viewModel.selectedKind = .audio
                    }
                    filterButton("Images", selected: viewModel.selectedKind == .image) {
                        viewModel.selectedKind = .image
                    }
                    filterButton("Links", selected: viewModel.selectedKind == .link) {
                        viewModel.selectedKind = .link
                    }
                    filterButton("PDFs", selected: viewModel.selectedKind == .pdf) {
                        viewModel.selectedKind = .pdf
                    }
                    filterButton("Text", selected: viewModel.selectedKind == .text) {
                        viewModel.selectedKind = .text
                    }
                } label: {
                    FilterPill(
                        title: viewModel.selectedKind?.filterLabel ?? "All types",
                        systemImage: viewModel.selectedKind?.filterSymbol ?? "square.grid.2x2",
                        isSelected: viewModel.selectedKind != nil
                    )
                }

                Menu {
                    ForEach(MemoryDateRange.allCases) { dateRange in
                        filterButton(dateRange.label, selected: viewModel.selectedDateRange == dateRange) {
                            viewModel.selectedDateRange = dateRange
                        }
                    }
                } label: {
                    FilterPill(
                        title: viewModel.selectedDateRange.label,
                        systemImage: "calendar",
                        isSelected: viewModel.selectedDateRange != .anytime
                    )
                }

                if !viewModel.availableTags.isEmpty {
                    Menu {
                        filterButton("All tags", selected: viewModel.selectedTag == nil) {
                            viewModel.selectedTag = nil
                        }
                        ForEach(viewModel.availableTags, id: \.self) { tag in
                            filterButton(tag, selected: viewModel.selectedTag == tag) {
                                viewModel.selectedTag = tag
                            }
                        }
                    } label: {
                        FilterPill(
                            title: viewModel.selectedTag ?? "All tags",
                            systemImage: "tag",
                            isSelected: viewModel.selectedTag != nil
                        )
                    }
                }

                if viewModel.searchRequest.isActive {
                    Button("Clear", systemImage: "xmark.circle.fill") {
                        viewModel.clearSearch()
                    }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
                    .accessibilityHint("Clears the query and all filters")
                }
            }
        }
        .accessibilityLabel("Search filters")
    }

    private func filterButton(
        _ title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            if selected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}

private struct FilterPill: View {
    let title: String
    let systemImage: String
    let isSelected: Bool

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isSelected ? Color.accentColor.opacity(0.14) : Color(uiColor: .secondarySystemBackground),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08))
            }
    }
}

private extension MemoryKind {
    var filterLabel: String {
        switch self {
        case .audio: "Voice"
        case .image: "Images"
        case .link: "Links"
        case .pdf: "PDFs"
        case .text: "Text"
        }
    }

    var filterSymbol: String {
        switch self {
        case .audio: "waveform"
        case .image: "photo"
        case .link: "link"
        case .pdf: "doc.richtext"
        case .text: "text.quote"
        }
    }
}

private struct MemoryCard: View {
    let item: MemoryLibraryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            preview
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipped()

            VStack(alignment: .leading, spacing: 8) {
                Text(item.memory.displayTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if let summary = item.memory.displaySummary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                ProcessingStateLabel(state: item.memory.state)
            }
            .padding(12)
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.06))
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens memory details")
    }

    @ViewBuilder
    private var preview: some View {
        switch item.memory.kind {
        case .audio:
            placeholderPreview(systemImage: "waveform", color: .orange)
        case .image:
            LocalImageView(url: item.originalURL, maximumPixelSize: 600)
        case .link:
            placeholderPreview(systemImage: "link", color: .blue)
        case .pdf:
            placeholderPreview(systemImage: "doc.richtext", color: .red)
        case .text:
            placeholderPreview(systemImage: "text.quote", color: .accentColor)
        }
    }

    private func placeholderPreview(systemImage: String, color: Color) -> some View {
            ZStack(alignment: .topLeading) {
                color.opacity(0.12)
                Image(systemName: systemImage)
                    .font(.largeTitle)
                    .foregroundStyle(color)
                    .padding(20)
            }
    }
}

struct ProcessingStateLabel: View {
    let state: MemoryProcessingState

    var body: some View {
        Label(state.label, systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
    }

    private var symbol: String {
        switch state {
        case .captured: "tray.and.arrow.down.fill"
        case .processing: "sparkles"
        case .indexed: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle.fill"
        }
    }

    private var color: Color {
        switch state {
        case .captured: .secondary
        case .processing: .blue
        case .indexed: .green
        case .failed: .orange
        }
    }
}

#Preview {
    ContentView()
}
