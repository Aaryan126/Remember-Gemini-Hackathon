import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system
    @State private var viewModel = LibraryViewModel()
    @State private var projectModel = ProjectViewModel()
    @State private var showsAssistant = false

    var body: some View {
        TabView {
            MemoryLibraryView(viewModel: viewModel, onAsk: openAssistant)
                .tabItem {
                    Label("Memories", systemImage: "square.grid.2x2")
                }

            ProjectView(model: projectModel, onAsk: openAssistant)
                .tabItem {
                    Label("Project", systemImage: "point.3.connected.trianglepath.dotted")
                }

            SettingsView(viewModel: viewModel, projectModel: projectModel, onAsk: openAssistant)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .preferredColorScheme(appearance.colorScheme)
        .fullScreenCover(isPresented: $showsAssistant) {
            AskRememberView(viewModel: viewModel) {
                showsAssistant = false
            }
        }
        .tint(RememberPalette.action)
        .task {
            await viewModel.synchronize()
        }
        .task { await projectModel.observe() }
        .onReceive(NotificationCenter.default.publisher(for: ProjectPreferences.embeddingsAvailable)) { _ in
            Task { await projectModel.refreshOrganization(retryUnavailable: true) }
        }
        .onChange(of: projectModel.snapshot.events.count) { _, _ in
            guard let event = projectModel.snapshot.events.last, (try? event.payload().memory) != nil else { return }
            Task {
                await viewModel.reloadLibraryProjection()
                if projectModel.snapshot.memories.values.contains(where: { $0.state == .captured && !$0.isArchived }) {
                    await viewModel.synchronize()
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else {
                return
            }
            Task {
                await viewModel.synchronize()
                await projectModel.refreshOrganization()
            }
        }
    }

    private func openAssistant() {
        showsAssistant = true
    }
}

struct MemoryLibraryView: View {
    let viewModel: LibraryViewModel
    let onAsk: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @State private var showsVoiceCapture = false
    @State private var showsNoteCapture = false
    @State private var showsCamera = false
    @State private var showsPhotoPicker = false
    @State private var showsFileImporter = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var pendingImage: PendingImage?
    @State private var pendingMediaCleanupURL: URL?
    @State private var isLoadingPhoto = false
    @State private var isSearchPresented = false
    @State private var isCaptureMenuExpanded = false
    @State private var detailPath: [UUID] = []

    var body: some View {
        NavigationStack(path: $detailPath) {
            Group {
                if viewModel.items.isEmpty, !viewModel.isSynchronizing {
                    emptyLibrary
                } else {
                    library
                }
            }
            .rememberCanvas(dark: .systemBackground)
            .navigationTitle("")
            .navigationDestination(for: UUID.self) { id in
                MemoryDetailView(memoryID: id, viewModel: viewModel)
            }
            .navigationBarTitleDisplayMode(.inline)
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
                TopLevelToolbar(title: "Remember", onAsk: onAsk)
            }
            .sheet(isPresented: $showsVoiceCapture) {
                VoiceCaptureView(viewModel: viewModel)
            }
            .sheet(isPresented: $showsNoteCapture) {
                NewNoteCaptureView(viewModel: viewModel)
            }
            .sheet(item: $pendingImage, onDismiss: releasePendingMedia) { pending in
                ImageCaptureConfirmationView(imageURL: pending.url, kind: pending.kind, viewModel: viewModel)
            }
            .fullScreenCover(isPresented: $showsCamera) {
                CameraPicker { image in
                    do {
                        let url = try image.rememberTemporaryJPEGURL()
                        showsCamera = false
                        pendingMediaCleanupURL = url
                        pendingImage = PendingImage(url: url)
                    } catch {
                        showsCamera = false
                        viewModel.reportError(error)
                    }
                } onCancel: {
                    showsCamera = false
                }
                .ignoresSafeArea()
            }
            .photosPicker(
                isPresented: $showsPhotoPicker,
                selection: $selectedPhoto,
                matching: .any(of: [.images, .videos]),
                preferredItemEncoding: .current
            )
            .fileImporter(
                isPresented: $showsFileImporter,
                allowedContentTypes: [.image, .movie, .pdf, .plainText],
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result, let url = urls.first else {
                    if case .failure(let error) = result { viewModel.reportError(error) }
                    return
                }
                Task { _ = await viewModel.saveImportedFile(from: url) }
            }
            .overlay {
                if isLoadingPhoto {
                    VStack(spacing: 16) {
                        ProgressView("Loading from Photos…")
                        Text("Videos stored in iCloud may take a moment.").font(.footnote)
                        Button("Cancel import") { selectedPhoto = nil }
                    }
                    .padding(24)
                    .background(.regularMaterial, in: .rect(cornerRadius: 24))
                } else if viewModel.items.isEmpty, viewModel.isSynchronizing {
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
                Task { await viewModel.searchWithAI() }
            }
            .task(id: selectedPhoto) {
                guard let item = selectedPhoto else { isLoadingPhoto = false; return }
                isLoadingPhoto = true
                defer { isLoadingPhoto = false }
                do {
                    let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
                    let url: URL
                    if isVideo {
                        guard let video = try await item.loadTransferable(type: PhotoVideoTransfer.self) else {
                            throw InAppCaptureError.unsupportedFile
                        }
                        url = video.url
                    } else {
                        url = try await item.temporaryImageURL()
                    }
                    guard !Task.isCancelled else {
                        try? FileManager.default.removeItem(at: url)
                        return
                    }
                    pendingMediaCleanupURL = url
                    pendingImage = PendingImage(url: url, kind: isVideo ? .video : .image)
                    selectedPhoto = nil
                } catch is CancellationError {
                    return
                } catch {
                    if !Task.isCancelled {
                        viewModel.reportError(error)
                        selectedPhoto = nil
                    }
                }
            }
        }
        .blur(radius: isCaptureMenuExpanded && !reduceTransparency ? 12 : 0)
        .allowsHitTesting(!isCaptureMenuExpanded)
        .accessibilityHidden(isCaptureMenuExpanded)
        .overlay {
            if isCaptureMenuExpanded {
                ZStack {
                    if reduceTransparency {
                        Color(uiColor: .systemBackground)
                    } else {
                        Rectangle().fill(.regularMaterial).opacity(0.55)
                        Color.black.opacity(colorScheme == .dark ? 0.18 : 0.06)
                    }
                }
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                        isCaptureMenuExpanded = false
                    }
                }
                .transition(.opacity)
                .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if detailPath.isEmpty && !isLoadingPhoto {
                CaptureMenuButton(
                    isExpanded: $isCaptureMenuExpanded,
                    onSelect: selectCaptureAction
                )
            }
        }
        .onChange(of: detailPath) { _, path in
            if !path.isEmpty { isCaptureMenuExpanded = false }
        }
    }

    private func releasePendingMedia() {
        // Sheet handoffs can make the preview disappear transiently. Cleanup belongs
        // to the presentation owner, only after the confirmation has actually closed.
        if let url = pendingMediaCleanupURL {
            try? FileManager.default.removeItem(at: url)
            pendingMediaCleanupURL = nil
        }
    }

    private var library: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if viewModel.isSynchronizing {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Importing and analyzing your memory")
                            .font(.subheadline)
                            .foregroundStyle(RememberPalette.secondaryText)
                    }
                    .accessibilityElement(children: .combine)
                }

                if viewModel.searchRequest.isActive {
                    searchStatus
                }

                if viewModel.visibleItems.isEmpty, viewModel.searchRequest.isActive, !viewModel.isSearching {
                    noSearchResults
                } else {
                    MasonryLayout(spacing: 18) {
                        ForEach(viewModel.visibleItems) { item in
                            NavigationLink(value: item.id) {
                                MemoryCard(item: item)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("library-memory-\(item.id)")
                        }
                    }
                    .padding(.top, 10)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            await viewModel.synchronize()
        }
    }

    private var searchStatus: some View {
        HStack(spacing: 8) {
            if viewModel.isSearching {
                ProgressView()
                    .controlSize(.small)
                Text(viewModel.isAISearching ? "Understanding your query…" : "Searching your memories…")
            } else {
                Text("\(viewModel.visibleItems.count) \(viewModel.visibleItems.count == 1 ? "result" : "results")")
            }
            Spacer()
            if viewModel.usedAIForCurrentSearch {
                Label("AI-assisted", systemImage: "sparkles")
                    .foregroundStyle(RememberPalette.action)
            } else if !viewModel.searchRequest.normalizedQuery.isEmpty {
                Button("Try AI search", systemImage: "sparkles") {
                    Task { await viewModel.searchWithAI() }
                }
                .disabled(viewModel.isSearching)
            } else {
                Label("Private", systemImage: "lock.fill")
                    .foregroundStyle(RememberPalette.success)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(RememberPalette.secondaryText)
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
            Label("Save your first memory", systemImage: "sparkles.rectangle.stack")
        } description: {
            Text("Add a note, photo, file, or voice recording here—or share something to Remember from another app. Originals are stored in your local vault; analysis uses the configured OpenAI service.")
        } actions: {
            Button("Write a Note", systemImage: "square.and.pencil") {
                showsNoteCapture = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(RememberPalette.warning)
            Text(message)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Dismiss") { viewModel.clearError() }
                .font(.footnote.weight(.semibold))
        }
        .padding()
        .background(.bar)
    }

    private func selectCaptureAction(_ action: CaptureAction) {
        switch action {
        case .note:
            showsNoteCapture = true
        case .camera:
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                viewModel.reportError(CaptureUIError.cameraUnavailable)
                return
            }
            showsCamera = true
        case .photo:
            showsPhotoPicker = true
        case .file:
            showsFileImporter = true
        case .voice:
            showsVoiceCapture = true
        }
    }
}

nonisolated enum AppAppearance: String, CaseIterable, Identifiable {
    static let storageKey = "remember.appearance"

    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct TopLevelToolbar: ToolbarContent {
    let title: String
    let onAsk: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Text(title)
                .font(.largeTitle.bold())
                .fixedSize()
                .accessibilityAddTraits(.isHeader)
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: onAsk) {
                RememberAssistantMark()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("AI Help")
            .accessibilityHint("Ask a temporary question about your memories")
        }
        .sharedBackgroundVisibility(.hidden)
    }
}

struct RememberAssistantMark: View {
    var size = CGFloat(30)

    var body: some View {
        Image(systemName: "apple.intelligence")
            .font(.system(size: size * 0.82, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private struct PendingImage: Identifiable {
    let id = UUID()
    let url: URL
    var kind: MemoryKind = .image
}

private enum CaptureUIError: LocalizedError {
    case cameraUnavailable

    var errorDescription: String? {
        "A camera is not available on this device. Choose a photo instead."
    }
}

private struct MemoryCard: View {
    let item: MemoryLibraryItem

    var body: some View {
        Group {
            if item.memory.kind == .image || item.memory.kind == .video {
                imageCard
            } else {
                compactCard
            }
        }
        .rememberCard(raised: true)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens memory details")
    }

    private var imageCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if item.memory.kind == .video {
                    LocalVideoPosterView(url: item.originalURL)
                        .overlay(alignment: .bottomLeading) {
                            Label("Video", systemImage: "play.fill")
                                .font(.caption.bold()).foregroundStyle(.white)
                                .padding(8).background(.black.opacity(0.65), in: .capsule).padding(8)
                        }
                } else {
                    LocalImageView(url: item.originalURL, maximumPixelSize: 900, contentMode: .fit)
                }
            }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 96)
                .background(RememberPalette.inset)

            VStack(alignment: .leading, spacing: 8) {
                Text(item.memory.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                processingState
            }
            .padding(12)
        }
    }

    private var compactCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.memory.displayTitle)
                .font(.headline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if let summary = distinctSummary {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(RememberPalette.secondaryText)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
            }

            processingState
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
    }

    private var distinctSummary: String? {
        guard let summary = item.memory.displaySummary,
              summary.caseInsensitiveCompare(item.memory.displayTitle) != .orderedSame else {
            return nil
        }
        return summary
    }

    @ViewBuilder
    private var processingState: some View {
        if item.memory.state != .indexed {
            Text(item.memory.state.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(item.memory.state == .failed ? RememberPalette.warning : RememberPalette.secondaryText)
        }
    }
}

private struct MasonryLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? 0
        let columnWidth = max(0, (width - spacing) / 2)
        var heights = [CGFloat.zero, CGFloat.zero]

        for subview in subviews {
            let column = heights[0] <= heights[1] ? 0 : 1
            let size = subview.sizeThatFits(.init(width: columnWidth, height: nil))
            heights[column] += size.height + spacing
        }

        let contentHeight = (heights.max() ?? 0) - (subviews.isEmpty ? 0 : spacing)
        return CGSize(width: width, height: max(contentHeight, 0))
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let columnWidth = max(0, (bounds.width - spacing) / 2)
        var heights = [CGFloat.zero, CGFloat.zero]

        for subview in subviews {
            let column = heights[0] <= heights[1] ? 0 : 1
            let itemProposal = ProposedViewSize(width: columnWidth, height: nil)
            let size = subview.sizeThatFits(itemProposal)
            let x = bounds.minX + CGFloat(column) * (columnWidth + spacing)
            let y = bounds.minY + heights[column]
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: itemProposal)
            heights[column] += size.height + spacing
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
        case .processing: RememberPalette.action
        case .indexed: RememberPalette.success
        case .failed: RememberPalette.warning
        }
    }
}

#Preview {
    ContentView()
}
