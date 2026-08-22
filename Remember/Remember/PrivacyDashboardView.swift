import SwiftUI

struct PrivacyDashboardView: View {
    let viewModel: LibraryViewModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 14) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 46))
                            .foregroundStyle(.green)
                            .accessibilityHidden(true)
                        Text("On-device by design")
                            .font(.title2.bold())
                        Text(RememberNetworkPolicy.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                }

                Section("Privacy status") {
                    PrivacyStatusRow(
                        title: "Outbound app features",
                        value: RememberNetworkPolicy.outboundRequestsImplemented ? "Enabled" : "None",
                        systemImage: "network.slash",
                        color: .green
                    )
                    PrivacyStatusRow(
                        title: "AI processing",
                        value: "Gemma + BGE on this iPhone",
                        systemImage: "iphone.gen3",
                        color: .green
                    )
                    PrivacyStatusRow(
                        title: "Model weights",
                        value: "Local app storage",
                        systemImage: "internaldrive",
                        color: .green
                    )
                    PrivacyStatusRow(
                        title: "Account or cloud sync",
                        value: "None",
                        systemImage: "person.crop.circle.badge.xmark",
                        color: .green
                    )
                }

                Section("What this proves") {
                    Text(RememberNetworkPolicy.limitation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("The activity log stores operation metadata only. It does not store your prompts, OCR text, images, or generated answers.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("App experience") {
                    Toggle(
                        "Living Wiki",
                        isOn: Binding(
                            get: { viewModel.livingWikiEnabled },
                            set: { viewModel.setLivingWikiEnabled($0) }
                        )
                    )
                    Text("Turn this off to return to the original v1 memories, search, chat, organize, and privacy experience. Wiki pages and history remain stored locally and can be re-enabled at any time.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    if viewModel.activities.isEmpty {
                        ContentUnavailableView(
                            "No AI activity yet",
                            systemImage: "clock.badge.checkmark",
                            description: Text("Transcription, analysis, wiki compilation, local semantic search, and Ask Remember operations will appear here.")
                        )
                    } else {
                        ForEach(viewModel.activities) { activity in
                            ActivityRow(activity: activity)
                        }
                    }
                } header: {
                    Text("Local AI activity")
                } footer: {
                    Text("Newest first · stored only in Remember's protected SQLite database")
                }
            }
            .navigationTitle("Privacy")
            .refreshable {
                await viewModel.refreshActivities()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await viewModel.refreshActivities() }
                    }
                }
            }
        }
    }
}

private struct PrivacyStatusRow: View {
    let title: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        LabeledContent {
            Text(value)
                .foregroundStyle(color)
                .fontWeight(.semibold)
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}

private struct ActivityRow: View {
    let activity: LocalAIActivity

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: activity.kind.systemImage)
                .foregroundStyle(statusColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(activity.kind.label)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(activity.status.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor)
                }
                Text(activity.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(activity.modelVersion)
                    if activity.sourceCount > 0 {
                        Text("· \(activity.sourceCount) \(activity.sourceCount == 1 ? "source" : "sources")")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var statusColor: Color {
        switch activity.status {
        case .running: .blue
        case .completed: .green
        case .failed: .orange
        case .interrupted: .secondary
        }
    }
}
