import SwiftUI

struct ResearchHistoryView: View {
    let viewModel: LibraryViewModel

    @State private var history: [ProjectMemoryRunSnapshot] = []
    @State private var isLoading = true

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Inspectable by design", systemImage: "checkmark.shield.fill")
                        .font(.headline)
                    Text("This is the chronological ledger of what Remember proposed, what protected checks found, and why each local change was kept or discarded.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            } footer: {
                Text("Evidence and patch decisions are shown. Hidden model chain-of-thought is neither requested nor stored.")
            }

            if history.isEmpty, !isLoading {
                Section {
                    ContentUnavailableView(
                        "No research history yet",
                        systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                        description: Text("The next project-memory compilation will create the first inspected run.")
                    )
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
        .navigationTitle("Research History")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading {
                ProgressView("Opening history…")
            }
        }
        .task {
            await reload()
        }
        .refreshable {
            await reload()
        }
    }

    private func reload() async {
        isLoading = true
        history = await viewModel.projectMemoryHistory()
        isLoading = false
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
                    Text(snapshot.run.operation.label)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(snapshot.run.status.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(snapshot.run.status.color)
                }
                if let memoryTitle = snapshot.memoryTitle {
                    Text(memoryTitle)
                        .font(.caption)
                        .lineLimit(1)
                }
                Text(runSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(snapshot.run.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private var runSummary: String {
        if snapshot.run.operation == .compile {
            return "\(snapshot.run.acceptedPageCount) of \(snapshot.run.proposedPageCount) proposed changes kept · \(snapshot.checks.filter(\.passed).count)/\(snapshot.checks.count) checks passed"
        }
        return "\(snapshot.checks.filter(\.passed).count)/\(snapshot.checks.count) structural checks passed"
    }
}

private struct ResearchRunDetailView: View {
    let snapshot: ProjectMemoryRunSnapshot
    let viewModel: LibraryViewModel

    var body: some View {
        List {
            Section {
                HStack {
                    Label(snapshot.run.status.label, systemImage: snapshot.run.status.systemImage)
                        .font(.headline)
                        .foregroundStyle(snapshot.run.status.color)
                    Spacer()
                    Text(snapshot.run.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(snapshot.run.rationale)
                    .font(.body)
                if snapshot.run.operation == .compile {
                    LabeledContent("Patch result", value: "\(snapshot.run.acceptedPageCount) of \(snapshot.run.proposedPageCount) kept")
                }
            }

            if let memoryID = snapshot.run.memoryID,
               let memoryTitle = snapshot.memoryTitle {
                Section("Source") {
                    NavigationLink {
                        MemoryDetailView(memoryID: memoryID, viewModel: viewModel)
                    } label: {
                        Label(memoryTitle, systemImage: "doc.text.image")
                    }
                }
            }

            if !snapshot.changes.isEmpty {
                Section("Accepted changes") {
                    ForEach(snapshot.changes) { change in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(change.pageTitle, systemImage: change.pageKind.systemImage)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("v\(change.revision.revisionNumber)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Text(change.revision.rationale)
                                .font(.footnote)
                            if let previous = change.revision.previousSummary,
                               previous != change.revision.newSummary {
                                DisclosureGroup("Inspect patch") {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Before").font(.caption.bold())
                                        Text(previous).font(.caption).foregroundStyle(.secondary)
                                        Text("After").font(.caption.bold())
                                        Text(change.revision.newSummary).font(.caption)
                                    }
                                    .padding(.top, 4)
                                }
                            } else {
                                Text(change.revision.newSummary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
            }

            Section("Protected checks") {
                if snapshot.checks.isEmpty {
                    Text("This run predates stored checks or ended before evaluation.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.checks) { check in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: check.passed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(check.passed ? .green : check.severity == .warning ? .orange : .red)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(check.label)
                                    .font(.subheadline.weight(.semibold))
                                Text(check.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(check.severity.rawValue.capitalized)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tertiary)
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
            }
            .font(.caption)
        }
        .navigationTitle(snapshot.run.operation.label)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension ProjectMemoryRunStatus {
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
