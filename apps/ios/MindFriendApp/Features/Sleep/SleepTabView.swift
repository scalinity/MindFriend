import SwiftUI

/// Container view for the Sleep tab that handles navigation and deep links
struct SleepTabView: View {
    @EnvironmentObject private var container: DependencyContainer
    @EnvironmentObject private var appState: AppState
    @Binding var contentIdToPlay: String?

    var body: some View {
        SleepHomeView(container: container, appState: appState)
            .onAppear {
                // Handle deep link if present
                if let contentId = contentIdToPlay {
                    // Deep link handling - SleepHomeView will load content
                    // and can use this ID to auto-play
                    Log.general.info("[DeepLink] Sleep tab opened with content: \(contentId)")
                    contentIdToPlay = nil
                }
            }
    }
}

// MARK: - Preview

#Preview {
    SleepTabView(contentIdToPlay: .constant(nil))
        .environmentObject(DependencyContainer.preview)
        .environmentObject(AppState())
}
