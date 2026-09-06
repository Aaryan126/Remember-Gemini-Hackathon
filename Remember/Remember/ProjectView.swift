import SwiftUI

struct ProjectView: View {
    let onAsk: () -> Void

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Project is being rebuilt", systemImage: "hammer.fill")
            } description: {
                Text("The previous map and story experience has been removed. This tab is the clean starting point for the new Project design.")
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                TopLevelToolbar(title: "Project", onAsk: onAsk)
            }
        }
    }
}
