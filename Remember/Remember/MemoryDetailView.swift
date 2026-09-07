import SwiftUI

struct MemoryDetailView: View {
    let memoryID: UUID
    let viewModel: LibraryViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var showsEditor = false
    @State private var showsInformation = false
    @State private var isEditingNote = false
    @State private var noteTitle = ""
    @State private var noteBody = ""
    @State private var isSavingNote = false
    @State private var showsNoteDeleteConfirmation = false
    @State private var isDeletingNote = false
    @FocusState private var focusedNoteField: NoteField?

    private enum NoteField {
        case title
        case body
    }

    var body: some View {
        Group {
            if let item = viewModel.item(id: memoryID) {
                detail(for: item)
                    .toolbar {
                        if item.memory.kind == .text && isEditingNote {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Cancel") {
                                    cancelNoteEditing()
                                }
                                .disabled(isSavingNote || isDeletingNote)
                            }
                            ToolbarItem(placement: .topBarTrailing) {
                                Button(role: .destructive) {
                                    showsNoteDeleteConfirmation = true
                                } label: {
                                    Image(systemName: "archivebox")
                                }
                                .accessibilityLabel("Archive Note")
                                .disabled(isSavingNote || isDeletingNote)
                            }
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") {
                                    saveNote()
                                }
                                .disabled(
                                    isSavingNote
                                        || isDeletingNote
                                        || editedNote.text.isEmpty
                                        || editedNote.text.count > InAppCaptureService.maximumNoteLength
                                )
                            }
                        } else {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button {
                                    showsInformation = true
                                } label: {
                                    Image(systemName: "info")
                                }
                                .accessibilityLabel("Memory details")
                            }
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Edit") {
                                    if item.memory.kind == .text {
                                        beginEditingNote(item)
                                    } else {
                                        showsEditor = true
                                    }
                                }
                            }
                        }
                    }
                    .sheet(isPresented: $showsEditor) {
                        if let currentItem = viewModel.item(id: memoryID) {
                            MemoryEditSheet(
                                item: currentItem,
                                viewModel: viewModel,
                                onDeleted: { dismiss() }
                            )
                        }
                    }
                    .sheet(isPresented: $showsInformation) {
                        if let currentItem = viewModel.item(id: memoryID) {
                            MemoryInformationSheet(item: currentItem)
                        }
                    }
                    .navigationBarBackButtonHidden(item.memory.kind == .text && isEditingNote)
            } else {
                ContentUnavailableView("Memory unavailable", systemImage: "questionmark.folder")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .confirmationDialog(
            "Archive this note?",
            isPresented: $showsNoteDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Archive Note") {
                deleteNote()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The note and its history will be kept. Restore it from Project’s archive.")
        }
    }

    @ViewBuilder
    private func detail(for item: MemoryLibraryItem) -> some View {
        if item.memory.kind == .image {
            immersivePhoto(for: item)
                .navigationTitle("")
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
        } else if item.memory.kind == .text && isEditingNote {
            noteEditor
                .navigationTitle("")
                .toolbarBackground(.automatic, for: .navigationBar)
        } else {
            standardDetail(for: item)
                .navigationTitle(item.memory.kind.detailTitle)
                .toolbarBackground(.automatic, for: .navigationBar)
        }
    }

    private func immersivePhoto(for item: MemoryLibraryItem) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                Color.black

                LocalImageView(
                    url: item.originalURL,
                    maximumPixelSize: 2_400,
                    contentMode: .fill
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .accessibilityLabel("Saved photo")

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.42),
                        .init(color: .black.opacity(0.18), location: 0.64),
                        .init(color: .black.opacity(0.92), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 9) {
                    Text(item.memory.displayTitle)
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(item.memory.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))

                    if !item.memory.tags.isEmpty {
                        WrappingTags(tags: item.memory.tags, color: .white)
                    }

                    processingNotice(for: item.memory)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, max(proxy.safeAreaInsets.bottom + 24, 34))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Color.black)
        .ignoresSafeArea()
    }

    private func standardDetail(for item: MemoryLibraryItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if item.memory.kind == .text {
                    noteContent(for: item)
                } else {
                    originalPreview(for: item)
                    memoryDescription(for: item.memory)
                }

                processingNotice(for: item.memory)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 48)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(uiColor: .systemBackground))
    }

    private func noteContent(for item: MemoryLibraryItem) -> some View {
        let note = NoteDocument(text: originalText(for: item))

        return VStack(alignment: .leading, spacing: 18) {
            Text(note.displayTitle)
                .font(.largeTitle.bold())
                .textSelection(.enabled)

            if !note.body.isEmpty {
                Text(note.body)
                    .font(.body)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !item.memory.tags.isEmpty {
                WrappingTags(tags: item.memory.tags)
            }

            Text(item.memory.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }

    private var noteEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Title", text: $noteTitle, axis: .vertical)
                .font(.largeTitle.bold())
                .lineLimit(1...3)
                .submitLabel(.next)
                .focused($focusedNoteField, equals: .title)
                .onSubmit { focusedNoteField = .body }

            TextEditor(text: $noteBody)
                .font(.body)
                .focused($focusedNoteField, equals: .body)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, -5)
                .overlay(alignment: .topLeading) {
                    if noteBody.isEmpty {
                        Text("Start writing…")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }

            if editedNote.text.count > InAppCaptureService.maximumNoteLength {
                Text("Note is too long")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .background(Color(uiColor: .systemBackground))
    }

    @ViewBuilder
    private func originalPreview(for item: MemoryLibraryItem) -> some View {
        switch item.memory.kind {
        case .audio:
            AudioMemoryPlayerView(url: item.originalURL)
        case .link:
            if let value = try? String(contentsOf: item.originalURL, encoding: .utf8),
               let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                Link(destination: url) {
                    Label(url.host() ?? url.absoluteString, systemImage: "arrow.up.right")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
                }
            }
        case .pdf:
            Label(item.originalURL.lastPathComponent, systemImage: "doc.richtext")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
        case .image, .text:
            EmptyView()
        }
    }

    private func memoryDescription(for memory: MemoryItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(memory.displayTitle)
                .font(.title.bold())

            if let summary = distinctSummary(for: memory) {
                Text(summary)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            if !memory.tags.isEmpty {
                WrappingTags(tags: memory.tags)
            }

            if let extractedText = memory.extractedText,
               !extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               memory.kind == .audio {
                DisclosureGroup("Transcript") {
                    Text(extractedText)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 10)
                }
            }
        }
    }

    @ViewBuilder
    private func processingNotice(for memory: MemoryItem) -> some View {
        switch memory.state {
        case .captured, .processing:
            Label(memory.state == .captured ? "Waiting to analyze" : "Analyzing", systemImage: "sparkles")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(memory.kind == .image ? Color.white.opacity(0.8) : Color.secondary)
        case .failed:
            VStack(alignment: .leading, spacing: 10) {
                Label("Analysis needs attention", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
                Button("Try Again", systemImage: "arrow.clockwise") {
                    Task { await viewModel.retry(id: memoryID) }
                }
                .buttonStyle(.bordered)
                .tint(memory.kind == .image ? .white : .accentColor)
            }
        case .indexed:
            EmptyView()
        }
    }

    private func originalText(for item: MemoryLibraryItem) -> String {
        if let value = try? String(contentsOf: item.originalURL, encoding: .utf8) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return item.memory.extractedText
            ?? item.memory.userCaption
            ?? item.memory.displaySummary
            ?? item.memory.displayTitle
    }

    private var editedNote: NoteDocument {
        NoteDocument(title: noteTitle, body: noteBody)
    }

    private func beginEditingNote(_ item: MemoryLibraryItem) {
        let note = NoteDocument(text: originalText(for: item))
        noteTitle = note.title
        noteBody = note.body
        isEditingNote = true
        Task {
            await Task.yield()
            focusedNoteField = note.body.isEmpty ? .title : .body
        }
    }

    private func cancelNoteEditing() {
        focusedNoteField = nil
        isEditingNote = false
    }

    private func saveNote() {
        focusedNoteField = nil
        let note = editedNote
        Task {
            isSavingNote = true
            let saved = await viewModel.updateNote(
                id: memoryID,
                title: note.title,
                body: note.body
            )
            isSavingNote = false
            if saved { isEditingNote = false }
        }
    }

    private func deleteNote() {
        focusedNoteField = nil
        Task {
            isDeletingNote = true
            if await viewModel.delete(id: memoryID) {
                dismiss()
            }
            isDeletingNote = false
        }
    }

    private func distinctSummary(for memory: MemoryItem) -> String? {
        guard let summary = memory.displaySummary,
              !sameText(summary, memory.displayTitle) else {
            return nil
        }
        return summary
    }

    private func sameText(_ first: String, _ second: String) -> Bool {
        first.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(second.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }
}

private struct MemoryEditSheet: View {
    let item: MemoryLibraryItem
    let viewModel: LibraryViewModel
    let onDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var primaryText: String
    @State private var summary: String
    @State private var tags: String
    @State private var isSaving = false
    @State private var showsDeleteConfirmation = false
    @State private var isDeleting = false

    init(item: MemoryLibraryItem, viewModel: LibraryViewModel, onDeleted: @escaping () -> Void) {
        self.item = item
        self.viewModel = viewModel
        self.onDeleted = onDeleted
        _primaryText = State(initialValue: item.memory.displayTitle)
        _summary = State(initialValue: item.memory.displaySummary ?? "")
        _tags = State(initialValue: item.memory.tags.joined(separator: ", "))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    editorField(
                        title: item.memory.kind == .image ? "Caption" : "Title",
                        placeholder: item.memory.kind == .image ? "Add a caption" : "Name this memory",
                        text: $primaryText,
                        lineLimit: item.memory.kind == .image ? 1...4 : 1...3
                    )

                    if item.memory.kind != .image && item.memory.kind != .text {
                        editorField(
                            title: "Description",
                            placeholder: "Add a description",
                            text: $summary,
                            lineLimit: 2...6
                        )
                    }

                    editorField(
                        title: "Tags",
                        placeholder: "Add tags, separated by commas",
                        text: $tags,
                        lineLimit: 1...3
                    )
                    .textInputAutocapitalization(.never)

                    Button(role: .destructive) {
                        showsDeleteConfirmation = true
                    } label: {
                        Label("Archive Memory", systemImage: "archivebox")
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .background(
                        Color(uiColor: .secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                    .disabled(isSaving || isDeleting)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(editorTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving || isDeleting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(
                            isSaving
                                || isDeleting
                                || primaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                }
            }
        }
        .presentationDetents(editorDetents)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSaving || isDeleting)
        .confirmationDialog(
            "Archive this memory?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Archive Memory") {
                deleteMemory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The memory and its history will be kept. Restore it from Project’s archive.")
        }
    }

    private func editorField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        lineLimit: ClosedRange<Int>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text, axis: .vertical)
                .lineLimit(lineLimit)
                .padding(.horizontal, 14)
                .frame(minHeight: 52)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var editorTitle: String {
        switch item.memory.kind {
        case .image: "Edit Photo"
        case .text: "Edit Note"
        case .audio: "Edit Recording"
        case .link: "Edit Link"
        case .pdf: "Edit PDF"
        }
    }

    private var editorDetents: Set<PresentationDetent> {
        if item.memory.kind == .image || item.memory.kind == .text {
            return [.height(330), .large]
        }
        return [.medium, .large]
    }

    private func save() {
        let cleanPrimaryText = primaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedSummary: String
        if item.memory.kind == .image {
            savedSummary = cleanPrimaryText
        } else if item.memory.kind == .text {
            let existingSummary = item.memory.displaySummary ?? ""
            savedSummary = sameText(existingSummary, item.memory.displayTitle)
                ? cleanPrimaryText
                : existingSummary
        } else {
            savedSummary = summary
        }

        Task {
            isSaving = true
            let saved = await viewModel.update(
                id: item.id,
                title: cleanPrimaryText,
                summary: savedSummary,
                tagsText: tags
            )
            isSaving = false
            if saved { dismiss() }
        }
    }

    private func deleteMemory() {
        Task {
            isDeleting = true
            if await viewModel.delete(id: item.id) {
                dismiss()
                onDeleted()
            }
            isDeleting = false
        }
    }

    private func sameText(_ first: String, _ second: String) -> Bool {
        first.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(second.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }
}

private struct MemoryInformationSheet: View {
    let item: MemoryLibraryItem

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Details") {
                    LabeledContent("Saved", value: item.memory.createdAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Type", value: item.memory.kind.sourceLabel)
                    LabeledContent("Storage", value: "On this iPhone")
                }

                if item.memory.state != .indexed {
                    Section("Status") {
                        LabeledContent("Analysis", value: item.memory.state.label)
                        if let error = item.memory.processingError, !error.isEmpty {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

            }
            .navigationTitle("Memory Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(260), .large])
        .presentationDragIndicator(.visible)
    }
}

private struct WrappingTags: View {
    let tags: [String]
    var color: Color = .accentColor

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
                .foregroundStyle(color)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(color.opacity(0.14), in: Capsule())
        }
    }
}

private extension MemoryKind {
    var detailTitle: String {
        switch self {
        case .audio: "Recording"
        case .image: "Photo"
        case .link: "Link"
        case .pdf: "PDF"
        case .text: "Note"
        }
    }

    var sourceLabel: String {
        switch self {
        case .audio: "Voice recording"
        case .image: "Photo"
        case .link: "Link"
        case .pdf: "PDF document"
        case .text: "Note"
        }
    }
}
