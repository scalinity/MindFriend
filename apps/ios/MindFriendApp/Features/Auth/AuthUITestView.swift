#if DEBUG
import SwiftUI

/// Uses the production sign-in screen with an in-memory signed-out state and a
/// deterministic authentication rejection. No saved session or backend is read.
@MainActor
struct AuthUITestView: View {
    @StateObject private var appState: AppState = {
        let state = AppState()
        state.setUnauthenticated()
        return state
    }()

    var body: some View {
        SignInView(testEmailSignIn: { _, _ in
            throw AuthError.invalidCredentials
        })
        .environmentObject(appState)
    }
}
#endif
