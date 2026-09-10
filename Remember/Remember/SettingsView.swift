import SwiftUI

struct SettingsView: View {
    let viewModel: LibraryViewModel
    let projectModel: ProjectViewModel
    let onAsk: () -> Void
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system
    @AppStorage(ProjectPreferences.cloudKey) private var cloudAssistance = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(selection: $appearance) {
                        ForEach(AppAppearance.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    } label: {
                        SettingsLabel(
                            title: "Appearance",
                            systemImage: "circle.lefthalf.filled"
                        )
                    }
                    .pickerStyle(.menu)
                    .accessibilityHint("Changes Remember's color scheme")
                } footer: {
                    Text("System matches your iPhone's current appearance.")
                }

                Section("Library") {
                    NavigationLink { ProjectArchiveView(model: projectModel) } label: {
                        SettingsRow(title: "Archive", detail: "Restore memories and their history", systemImage: "archivebox")
                    }
                    NavigationLink {
                        OrganizeView(viewModel: viewModel)
                    } label: {
                        SettingsRow(
                            title: "Collections & Tags",
                            detail: librarySummary,
                            systemImage: "folder.fill"
                        )
                    }
                }

                Section {
                    Toggle("Cloud assistance", isOn: $cloudAssistance)
                    NavigationLink {
                        PrivacyDashboardView(viewModel: viewModel)
                    } label: {
                        SettingsRow(
                            title: "Privacy & AI",
                            detail: "Models and activity",
                            systemImage: "hand.raised.fill"
                        )
                    }
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Automatic capture and topic organization use Apple’s on-device tools by default. Cloud assistance sends source excerpts (and images during enrichment) to the configured OpenAI service. Ask and AI search send relevant content when you explicitly use them, independently of this setting.")
                }
            }
            .rememberGroupedList()
            .listSectionSpacing(16)
            .environment(\.defaultMinListRowHeight, 52)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                TopLevelToolbar(title: "Settings", onAsk: onAsk)
            }
            .safeAreaInset(edge: .bottom) {
                if let errorMessage = viewModel.errorMessage {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(RememberPalette.warning)
                        Text(errorMessage).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
                        Button("Dismiss") { viewModel.clearError() }.font(.footnote.weight(.semibold))
                    }
                    .padding()
                    .background(.bar)
                }
            }
        }
    }

    private var librarySummary: String {
        "\(viewModel.collections.count) collections · \(viewModel.tagSummaries.count) tags"
    }
}

private struct SettingsRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(systemImage: systemImage)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(RememberPalette.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct SettingsLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(systemImage: systemImage)
            Text(title)
                .foregroundStyle(.primary)
        }
    }
}

private struct SettingsIcon: View {
    let systemImage: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 30, height: 30)
            .background(scheme == .light ? RememberPalette.inset : .clear, in: .rect(cornerRadius: 8))
            .accessibilityHidden(true)
    }
}
