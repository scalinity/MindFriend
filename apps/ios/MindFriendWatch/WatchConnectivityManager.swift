import WatchConnectivity
import Foundation

// MARK: - Watch Connectivity Manager

public final class WatchConnectivityManager: NSObject, WCSessionDelegate, ObservableObject {
    public static let shared = WatchConnectivityManager()

    @Published public var isReachable = false

    private var session: WCSession?

    override private init() {
        super.init()
        setupWatchConnectivity()
    }

    private func setupWatchConnectivity() {
        #if os(iOS)
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
        #elseif os(watchOS)
        session = WCSession.default
        session?.delegate = self
        session?.activate()
        #endif
    }

    // MARK: - Send to Watch

    public func sendStreak(_ streak: Int) {
        #if os(iOS)
        guard let session = session, session.isPaired && session.isWatchAppInstalled else {
            return
        }

        let data: [String: Any] = [
            "streak": streak,
            "timestamp": Date().timeIntervalSince1970
        ]

        do {
            try session.updateApplicationContext(data)
        } catch {
            print("Failed to send streak to watch: \(error)")
        }
        #endif
    }

    public func sendDailyProgress(completed: Int, goal: Int) {
        #if os(iOS)
        guard let session = session, session.isPaired && session.isWatchAppInstalled else {
            return
        }

        let data: [String: Any] = [
            "completedToday": completed,
            "dailyGoal": goal,
            "timestamp": Date().timeIntervalSince1970
        ]

        do {
            try session.updateApplicationContext(data)
        } catch {
            print("Failed to send daily progress to watch: \(error)")
        }
        #endif
    }

    // MARK: - Receive from Watch

    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            if let mood = applicationContext["mood"] as? String {
                self.handleMoodFromWatch(mood)
            }
        }
    }

    public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            #if DEBUG
            print("Received message from watch: \(message)")
            #endif
        }
    }

    // MARK: - WCSessionDelegate

    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.isReachable = session.isReachable
        }
    }

    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {
        self.session = session
    }

    public func sessionDidDeactivate(_ session: WCSession) {
        self.session?.activate()
    }
    #endif

    // MARK: - Helpers

    private func handleMoodFromWatch(_ mood: String) {
        // Update main app with mood from watch
        print("Received mood from watch: \(mood)")
    }
}
