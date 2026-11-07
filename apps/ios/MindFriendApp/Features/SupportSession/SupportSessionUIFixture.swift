#if DEBUG
import SwiftUI

/// Runs the production views with a separate synthetic journal and a network-free SDK session.
enum SupportSessionUIFixture {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("--support-session-ui-test") }
    static let ownerID = UUID(uuidString: "f0000000-0000-4000-8000-000000000001")!
    static let memorySessionID = UUID(uuidString: "f0000000-0000-4000-8000-000000000002")!
    static let memoryConversationID = UUID(uuidString: "f0000000-0000-4000-8000-000000000003")!
    static let memoryMessageID = UUID(uuidString: "f0000000-0000-4000-8000-000000000004")!
    static let memoryPreviewText = "I prefer short replies. " + String(repeating: "Synthetic selected-source preview. ", count: 20) + "END OF SYNTHETIC PREVIEW"
    static func value(after flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }
    static var textSize: DynamicTypeSize {
        switch value(after: "--support-text-size") {
        case "xSmall": return .xSmall
        case "small": return .small
        case "medium": return .medium
        case "xLarge": return .xLarge
        case "xxLarge": return .xxLarge
        case "xxxLarge": return .xxxLarge
        case "accessibility1": return .accessibility1
        case "accessibility2": return .accessibility2
        case "accessibility3": return .accessibility3
        case "accessibility4": return .accessibility4
        case "accessibility5": return .accessibility5
        default: return .large
        }
    }
    static let networkSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SupportFixtureURLProtocol.self]
        return URLSession(configuration: configuration)
    }()
}

private final class SupportFixtureURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        // One read-only preview fixture. No generate response, provider, account write or network is available.
        var requestData = request.httpBody ?? Data()
        if requestData.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1_024)
            while stream.hasBytesAvailable && requestData.count <= 8_192 {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                requestData.append(buffer, count: count)
            }
        }
        let operation = (try? JSONSerialization.jsonObject(with: requestData) as? [String: Any])?["op"] as? String
        if request.url?.host == "support-suggestions.fixture.invalid", operation == "prepare" {
            let text = SupportSessionUIFixture.memoryPreviewText
            let body: [String: Any] = ["ok": true, "op": "prepare",
                "session_id": SupportSessionUIFixture.memorySessionID.uuidString.lowercased(),
                "conversation_id": SupportSessionUIFixture.memoryConversationID.uuidString.lowercased(),
                "session_status": "open", "privacy_revision": 1,
                "limits": ["max_messages": 12, "max_total_bytes": 16_384],
                "messages": [["id": SupportSessionUIFixture.memoryMessageID.uuidString.lowercased(), "revision": 0,
                    "created_at": "2026-11-07T06:00:00Z", "text": text, "utf8_bytes": text.utf8.count]],
                "excluded": ["suppressed": 0, "too_long": 0, "conversation_suppressed": false],
                "disclosure": ["prompt_version": "synthetic-preview", "provider": ["vendor": "openai", "model": "gpt-6-luna"],
                    "system_prompt": "Synthetic fixed instructions.", "instructions": "Only a read-only layout fixture.",
                    "not_sent": ["assistant_replies", "other_conversations", "health_data", "private_vault", "unshared_activity_notes", "saved_memories"],
                    "stored_by_provider": "requested_not_stored"]]
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: (try? JSONSerialization.data(withJSONObject: body)) ?? Data())
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

struct SupportSessionUIFixtureView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var container: DependencyContainer
    @State private var coordinator: SupportSessionCoordinator?
    @State private var error: String?

    var body: some View {
        Group {
            if SupportSessionUIFixture.value(after: "--support-fixture-screen") == "onboarding" {
                OnboardingFlow()
            } else if SupportSessionUIFixture.value(after: "--support-fixture-screen") == "voice-layout" {
                SupportVoiceLayoutFixture()
            } else if let coordinator {
                if SupportSessionUIFixture.value(after: "--support-fixture-screen") == "memory-suggestions" {
                    NavigationStack { SupportMemorySuggestionView(sessionID: SupportSessionUIFixture.memorySessionID) }
                        .environmentObject(coordinator)
                } else { SupportLoadedShell(coordinator: coordinator) }
            }
            else if let error { Text(error).padding() }
            else { ProgressView("Preparing synthetic journal") }
        }
        .dynamicTypeSize(SupportSessionUIFixture.textSize)
        .overlay(alignment: .topTrailing) {
            SupportFixtureAppearanceLabel()
        }
        .task {
            guard !["voice-layout", "onboarding"].contains(SupportSessionUIFixture.value(after: "--support-fixture-screen") ?? "") else { return }
            guard coordinator == nil else { return }
            Analytics.shared.setEnabled(false)
            do {
                let runID = SupportSessionUIFixture.value(after: "--support-fixture-run") ?? UUID().uuidString
                guard UUID(uuidString: runID) != nil else { throw DataError.invalidId }
                let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                    appropriateFor: nil, create: true).appendingPathComponent("MindFriend/SupportUIFixtures/" + runID, isDirectory: true)
                let repository = SupportSessionRepository(identity: .init(ownerID: SupportSessionUIFixture.ownerID),
                    io: FileSupportJournalIO(baseDirectory: base))
                let value = SupportSessionCoordinator(repository: repository)
                try await value.load()
                let user = UserProfile(id: SupportSessionUIFixture.ownerID, handle: "synthetic", displayName: "Synthetic",
                    email: nil, avatarUrl: nil, timezone: "America/New_York", createdAt: nil, onboardingCompletedAt: Date(),
                    stats: nil, settings: nil, entitlements: .init(subscriptionTier: "free", premiumExpiresAt: nil, features: [:]), badges: nil)
                appState.setAuthenticated(user: user)
                var cloud: SupportSessionCloudService?
                if SupportSessionUIFixture.value(after: "--support-fixture-screen") == "memory-suggestions" {
                    _ = try await value.repository.createSession(epoch: value.identity.epochID, id: SupportSessionUIFixture.memorySessionID,
                        title: "Synthetic source session", conversationID: SupportSessionUIFixture.memoryConversationID, contextScope: .conversationOnly)
                    try await value.refreshJournal()
                    let binding = SupportCloudBinding(ownerID: SupportSessionUIFixture.ownerID, accountEpoch: appState.accountEpoch)
                    cloud = SupportSessionCloudService(binding: binding, ownerProof: { binding },
                        tokenSource: { SupportCloudCredential(binding: binding, accessToken: "synthetic-fixture-token") },
                        transport: URLSessionSupportCloudTransport(session: SupportSessionUIFixture.networkSession),
                        projectURL: URL(string: "https://support-suggestions.fixture.invalid")!, apiKey: "synthetic-fixture-public-key")
                }
                container.installSupportFixture(value, accountEpoch: appState.accountEpoch, cloud: cloud)
                coordinator = value
            } catch { self.error = "Synthetic journal could not be prepared." }
        }
    }
}

/// Reports the rendered environment, so a launch argument alone is never appearance evidence.
private struct SupportFixtureAppearanceLabel: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        Text("Synthetic layout fixture")
            .font(.system(size: 11)).padding(4).background(.thinMaterial)
            .accessibilityIdentifier("support-fixture-appearance")
            .accessibilityValue(colorScheme == .dark ? "dark" : "light")
    }
}

/// Illustrates the production caption/layout/control components; no voice service is created.
private struct SupportVoiceLayoutFixture: View {
    @State private var muted = true
    @State private var result: String?
    private let caption = VoiceCaption(localUUID: UUID(), role: .assistant,
        text: String(repeating: "Synthetic partial speech for a layout check. ", count: 30), phase: .live)

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Text("Illustrative voice layout · microphone off")
                    .font(.caption).padding(12).accessibilityAddTraits(.isHeader)
                VoiceActiveLayout(safeBottom: geometry.safeAreaInsets.bottom) {
                    VStack(spacing: 20) {
                        if let result { Text(result).font(.title2) }
                        VoiceCaptionView(caption: caption, reduceMotion: true)
                        Circle().fill(Color.blue.opacity(0.3)).frame(width: 180, height: 180)
                            .overlay(Text("Layout preview"))
                    }.padding(.horizontal, 20)
                } controls: {
                    VoiceCallControls(isMuted: muted, onMute: { muted.toggle() },
                        onEnd: { result = "End control selected" }, onText: { result = "Text control selected" })
                }
            }
        }
        .background(Color.black)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
    }
}
#endif
