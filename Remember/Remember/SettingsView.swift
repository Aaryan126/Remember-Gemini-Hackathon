import SwiftUI

struct SettingsView: View {
    let viewModel: LibraryViewModel
    let onAsk: () -> Void
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityHint("Changes Remember's color scheme")
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("System follows your iPhone appearance setting.")
                }

                Section("Organization") {
                    NavigationLink {
                        OrganizeView(viewModel: viewModel)
                    } label: {
                        SettingsRow(
                            title: "Collections & Tags",
                            detail: "\(viewModel.collections.count) collections · \(viewModel.tagSummaries.count) tags",
                            systemImage: "folder.badge.gearshape",
                            color: .blue
                        )
                    }
                }

                Section("Privacy & AI") {
                    NavigationLink {
                        PrivacyDashboardView(viewModel: viewModel)
                    } label: {
                        SettingsRow(
                            title: "Privacy, Models & Activity",
                            detail: "OpenAI processing and the local activity log",
                            systemImage: "lock.shield.fill",
                            color: .green
                        )
                    }
                }

            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                TopLevelToolbar(title: "Settings", onAsk: onAsk)
            }
            .safeAreaInset(edge: .bottom) {
                if let errorMessage = viewModel.errorMessage {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(errorMessage).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
                        Button("Dismiss") { viewModel.clearError() }.font(.footnote.weight(.semibold))
                    }
                    .padding()
                    .background(.bar)
                }
            }
        }
    }

}

private struct SettingsRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .frame(width: 28)
        }
    }
}
