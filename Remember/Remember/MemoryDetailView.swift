import SwiftUI

struct MemoryDetailView: View {
    let memoryID: UUID
    let viewModel: LibraryViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false
    @State private var isSaving = false
    @State private var showsDeleteConfirmation = false
    @State private var title = ""
    @State private var summary = ""
    @State private var tags = ""

    var body: some View {
        Group {
            if let item = viewModel.item(id: memoryID) {
                detail(for: item)
            } else {
                ContentUnavailableView("Memory unavailable", systemImage: "questionmark.folder")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.item(id: memoryID) != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "Cancel" : "Edit") {
                        if isEditing, let item = viewModel.item(id: memoryID) {
                            loadDraft(from: item.memory)
                        }
                        isEditing.toggle()
                    }
                    .disabled(isSaving)
                }
            }
        }
        .task(id: memoryID) {
            if let item = viewModel.item(id: memoryID) {
                loadDraft(from: item.memory)
            }
        }
        .confirmationDialog(
            "Delete this memory?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Memory", role: .destructive) {
                Task {
                    if await viewModel.delete(id: memoryID) {
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The saved copy and its on-device analysis will be permanently removed from Remember.")
        }
    }

    private func detail(for item: MemoryLibraryItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                originalPreview(for: item)

                if isEditing {
                    editForm
                } else {
                    analysis(for: item.memory)
                }

                sourceInformation(for: item.memory)

                if item.memory.state == .failed {
                    Button {
                        Task { await viewModel.retry(id: memoryID) }
                    } label: {
                        Label("Retry on-device analysis", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button(role: .destructive) {
                    showsDeleteConfirmation = true
                } label: {
                    Label("Delete Memory", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(16)
        }
        .navigationTitle(item.memory.displayTitle)
    }

    @ViewBuilder
    private func originalPreview(for item: MemoryLibraryItem) -> some View {
        switch item.memory.kind {
        case .audio:
            AudioMemoryPlayerView(url: item.originalURL)
        case .image:
            LocalImageView(url: item.originalURL, maximumPixelSize: 1_600, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        case .link:
            if let value = try? String(contentsOf: item.originalURL, encoding: .utf8),
               let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                Link(destination: url) {
                    Label(url.absoluteString, systemImage: "link")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 20))
                }
            }
        case .pdf:
            Label("Saved PDF · \(item.originalURL.lastPathComponent)", systemImage: "doc.richtext")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 20))
        case .text:
            Text(item.memory.extractedText ?? item.memory.userCaption ?? "Saved text")
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private func analysis(for memory: MemoryItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(memory.displayTitle)
                    .font(.title2.bold())
                Spacer()
                ProcessingStateLabel(state: memory.state)
            }

            if let summary = memory.displaySummary {
                Text(summary)
                    .font(.body)
            }

            if !memory.tags.isEmpty {
                WrappingTags(tags: memory.tags)
            }

            if let error = memory.processingError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            if let extractedText = memory.extractedText,
               !extractedText.isEmpty,
               memory.kind == .image || memory.kind == .audio {
                DisclosureGroup(memory.kind == .audio ? "Voice transcript" : "Text found in image") {
                    Text(extractedText)
                        .font(.footnote)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }
            }
        }
    }

    private var editForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Title", text: $title, axis: .vertical)
                .textFieldStyle(.roundedBorder)

            TextField("Summary", text: $summary, axis: .vertical)
                .lineLimit(3...8)
                .textFieldStyle(.roundedBorder)

            TextField("Tags, separated by commas", text: $tags, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)

            Button {
                Task {
                    isSaving = true
                    let saved = await viewModel.update(
                        id: memoryID,
                        title: title,
                        summary: summary,
                        tagsText: tags
                    )
                    isSaving = false
                    if saved {
                        isEditing = false
                    }
                }
            } label: {
                if isSaving {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Save Changes")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func sourceInformation(for memory: MemoryItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About this memory")
                .font(.headline)
            LabeledContent("Saved", value: memory.createdAt.formatted(date: .abbreviated, time: .shortened))
            LabeledContent("Source", value: sourceLabel(for: memory.kind))
            LabeledContent("Storage", value: "On this iPhone")
            if let modelVersion = memory.modelVersion {
                LabeledContent("Analyzed by", value: modelVersion)
            }
            if memory.kind == .audio {
                LabeledContent("Transcribed by", value: "On-device SpeechTranscriber")
            }
        }
        .font(.subheadline)
    }

    private func sourceLabel(for kind: MemoryKind) -> String {
        switch kind {
        case .audio: "Recorded voice memory"
        case .image: "Shared image"
        case .link: "Shared link"
        case .pdf: "Shared PDF"
        case .text: "Shared text"
        }
    }

    private func loadDraft(from memory: MemoryItem) {
        title = memory.displayTitle
        summary = memory.displaySummary ?? ""
        tags = memory.tags.joined(separator: ", ")
    }
}

private struct WrappingTags: View {
    let tags: [String]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { tagViews }
            VStack(alignment: .leading, spacing: 6) { tagViews }
        }
    }

    @ViewBuilder
    private var tagViews: some View {
        ForEach(tags, id: \.self) { tag in
            Text(tag)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.tint.opacity(0.12), in: Capsule())
        }
    }
}
