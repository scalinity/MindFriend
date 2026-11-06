#if DEBUG
import SwiftUI
import Supabase

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

/// The dependency container is initialized before the fixture view appears.
/// Keep its SDK clients away from persistent auth storage and the network too.
enum AuthUITestBackend {
    static func makeClient() -> SupabaseClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthUITestURLProtocol.self]
        return SupabaseClient(
            supabaseURL: URL(string: "https://auth-ui-test.invalid")!,
            supabaseKey: "auth-ui-test-placeholder",
            options: .init(
                auth: .init(
                    storage: AuthUITestStorage(),
                    autoRefreshToken: false,
                    emitLocalSessionAsInitialSession: true
                ),
                global: .init(session: URLSession(configuration: configuration))
            )
        )
    }
}

final class AuthUITestStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func store(key: String, value: Data) {
        lock.lock()
        defer { lock.unlock() }
        values[key] = value
    }

    func retrieve(key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func remove(key: String) {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: key)
    }
}

private final class AuthUITestURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}
#endif
