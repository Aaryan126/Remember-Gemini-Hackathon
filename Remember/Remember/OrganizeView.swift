import SwiftUI

struct OrganizeView: View {
    let viewModel: LibraryViewModel

    @State private var editor: OrganizationEditor?
    @State private var deletion: OrganizationDeletion?

    var body: some View {
        List {
                Section {
                    if viewModel.collections.isEmpty {
                        Text("Create a collection to group related memories without moving or duplicating them.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.collections) { summary in
                            NavigationLink {
                                CollectionDetailView(summary: summary, viewModel: viewModel)
                            } label: {
                                Label {
                                    LabeledContent(
                                        summary.collection.name,
                                        value: "\(summary.memoryCount)"
                                    )
                                } icon: {
                                    Image(systemName: "folder.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    deletion = .collection(summary)
                                }
                                Button("Rename", systemImage: "pencil") {
                                    editor = .renameCollection(summary)
                                }
                                .tint(.blue)
                            }
                        }
                    }
                } header: {
                    Text("Collections")
                } footer: {
                    Text("Deleting a collection never deletes its memories.")
                }

                Section {
                    if viewModel.tagSummaries.isEmpty {
                        Text("Tags suggested during analysis—or added while editing a memory—will appear here.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.tagSummaries) { tag in
                            NavigationLink {
                                TagDetailView(tag: tag.name, viewModel: viewModel)
                            } label: {
                                Label {
                                    LabeledContent(tag.name, value: "\(tag.memoryCount)")
                                } icon: {
                                    Image(systemName: "tag.fill")
                                        .foregroundStyle(.purple)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    deletion = .tag(tag)
                                }
                                Button("Rename", systemImage: "pencil") {
                                    editor = .renameTag(tag)
                                }
                                .tint(.purple)
                            }
                        }
                    }
                } header: {
                    Text("Tags")
                } footer: {
                    Text("Renaming or deleting a tag updates every matching memory and its local search index.")
                }
        }
        .navigationTitle("Collections & Tags")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New Collection", systemImage: "folder.badge.plus") {
                    editor = .newCollection
                }
            }
        }
        .sheet(item: $editor) { editor in
            OrganizationNameEditor(
                title: editor.title,
                initialName: editor.initialName,
                placeholder: editor.placeholder
            ) { name in
                switch editor {
                case .newCollection:
                    await viewModel.createCollection(name: name)
                case .renameCollection(let summary):
                    await viewModel.renameCollection(id: summary.id, name: name)
                case .renameTag(let tag):
                    await viewModel.renameTag(tag.name, to: name)
                }
            }
        }
        .alert(item: $deletion) { deletion in
            Alert(
                title: Text(deletion.title),
                message: Text(deletion.message),
                primaryButton: .destructive(Text("Delete")) {
                    Task {
                        switch deletion {
                        case .collection(let summary):
                            _ = await viewModel.deleteCollection(id: summary.id)
                        case .tag(let tag):
                            _ = await viewModel.deleteTag(tag.name)
                        }
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }
}

private enum OrganizationEditor: Identifiable {
    case newCollection
    case renameCollection(MemoryCollectionSummary)
    case renameTag(MemoryTagSummary)

    var id: String {
        switch self {
        case .newCollection: "new-collection"
        case .renameCollection(let summary): "collection-\(summary.id.uuidString)"
        case .renameTag(let tag): "tag-\(tag.id)"
        }
    }

    var title: String {
        switch self {
        case .newCollection: "New Collection"
        case .renameCollection: "Rename Collection"
        case .renameTag: "Rename Tag"
        }
    }

    var initialName: String {
        switch self {
        case .newCollection: ""
        case .renameCollection(let summary): summary.collection.name
        case .renameTag(let tag): tag.name
        }
    }

    var placeholder: String {
        switch self {
        case .newCollection, .renameCollection: "Collection name"
        case .renameTag: "Tag name"
        }
    }
}

private enum OrganizationDeletion: Identifiable {
    case collection(MemoryCollectionSummary)
    case tag(MemoryTagSummary)

    var id: String {
        switch self {
        case .collection(let summary): "collection-\(summary.id.uuidString)"
        case .tag(let tag): "tag-\(tag.id)"
        }
    }

    var title: String {
        switch self {
        case .collection(let summary): "Delete “\(summary.collection.name)”?"
        case .tag(let tag): "Delete #\(tag.name)?"
        }
    }

    var message: String {
        switch self {
        case .collection:
            "The collection will be removed, but every memory inside it will stay in Remember."
        case .tag:
            "This tag will be removed from every matching memory. The memories themselves will stay in Remember."
        }
    }
}

private struct OrganizationNameEditor: View {
    let title: String
    let placeholder: String
    let onSave: @MainActor (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var isSaving = false
    @FocusState private var isNameFocused: Bool

    init(
        title: String,
        initialName: String,
        placeholder: String,
        onSave: @escaping @MainActor (String) async -> Bool
    ) {
        self.title = title
        self.placeholder = placeholder
        self.onSave = onSave
        _name = State(initialValue: initialName)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(placeholder, text: $name)
                    .focused($isNameFocused)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onSubmit { save() }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isNameFocused = false
                    }
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
    }

    private func save() {
        isNameFocused = false
        Task {
            isSaving = true
            let saved = await onSave(name)
            isSaving = false
            if saved { dismiss() }
        }
    }
}

private struct CollectionDetailView: View {
    let summary: MemoryCollectionSummary
    let viewModel: LibraryViewModel

    @State private var items: [MemoryLibraryItem] = []
    @State private var isLoading = true
    @State private var showsMembershipEditor = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Opening collection…")
            } else if items.isEmpty {
                ContentUnavailableView {
                    Label("Empty collection", systemImage: "folder")
                } description: {
                    Text("Choose Add Memories to place saved items here.")
                } actions: {
                    Button("Add Memories", systemImage: "plus") {
                        showsMembershipEditor = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                List(items) { item in
                    NavigationLink {
                        MemoryDetailView(memoryID: item.id, viewModel: viewModel)
                    } label: {
                        OrganizationMemoryRow(item: item)
                    }
                }
            }
        }
        .navigationTitle(summary.collection.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add Memories", systemImage: "plus") {
                    showsMembershipEditor = true
                }
            }
        }
        .task { await reload() }
        .sheet(isPresented: $showsMembershipEditor, onDismiss: {
            Task { await reload() }
        }) {
            CollectionMembershipEditor(
                collection: summary.collection,
                items: viewModel.items,
                selectedIDs: Set(items.map(\.id)),
                viewModel: viewModel
            )
        }
    }

    private func reload() async {
        isLoading = true
        items = await viewModel.collectionItems(id: summary.id)
        isLoading = false
    }
}

private struct CollectionMembershipEditor: View {
    let collection: MemoryCollection
    let items: [MemoryLibraryItem]
    let viewModel: LibraryViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<UUID>
    @State private var busyIDs: Set<UUID> = []

    init(
        collection: MemoryCollection,
        items: [MemoryLibraryItem],
        selectedIDs: Set<UUID>,
        viewModel: LibraryViewModel
    ) {
        self.collection = collection
        self.items = items
        self.viewModel = viewModel
        _selectedIDs = State(initialValue: selectedIDs)
    }

    var body: some View {
        NavigationStack {
            List(items) { item in
                Button {
                    toggle(item.id)
                } label: {
                    HStack {
                        OrganizationMemoryRow(item: item)
                        Spacer()
                        if busyIDs.contains(item.id) {
                            ProgressView()
                        } else if selectedIDs.contains(item.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                        } else {
                            Image(systemName: "circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(busyIDs.contains(item.id))
                .accessibilityLabel("\(item.memory.displayTitle), \(selectedIDs.contains(item.id) ? "in collection" : "not in collection")")
            }
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView("No memories yet", systemImage: "square.grid.2x2")
                }
            }
            .navigationTitle("Add to \(collection.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func toggle(_ memoryID: UUID) {
        let shouldAdd = !selectedIDs.contains(memoryID)
        busyIDs.insert(memoryID)
        Task {
            let saved = await viewModel.setMembership(
                memoryID: memoryID,
                collectionID: collection.id,
                isMember: shouldAdd
            )
            if saved {
                if shouldAdd {
                    selectedIDs.insert(memoryID)
                } else {
                    selectedIDs.remove(memoryID)
                }
            }
            busyIDs.remove(memoryID)
        }
    }
}

private struct TagDetailView: View {
    let tag: String
    let viewModel: LibraryViewModel

    private var items: [MemoryLibraryItem] {
        viewModel.items.filter { item in
            item.memory.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
        }
    }

    var body: some View {
        List(items) { item in
            NavigationLink {
                MemoryDetailView(memoryID: item.id, viewModel: viewModel)
            } label: {
                OrganizationMemoryRow(item: item)
            }
        }
        .navigationTitle("#\(tag)")
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("No memories with this tag", systemImage: "tag")
            }
        }
    }
}

private struct OrganizationMemoryRow: View {
    let item: MemoryLibraryItem

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.memory.displayTitle)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                if let summary = item.memory.displaySummary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        } icon: {
            Image(systemName: item.memory.kind.organizationSymbol)
                .foregroundStyle(item.memory.kind.organizationColor)
                .frame(width: 28)
        }
    }
}

private extension MemoryKind {
    var organizationSymbol: String {
        switch self {
        case .audio: "waveform"
        case .image: "photo"
        case .video: "video"
        case .link: "link"
        case .pdf: "doc.richtext"
        case .text: "text.quote"
        }
    }

    var organizationColor: Color {
        switch self {
        case .audio: .orange
        case .image: .green
        case .video: .indigo
        case .link: .blue
        case .pdf: .red
        case .text: .purple
        }
    }
}
