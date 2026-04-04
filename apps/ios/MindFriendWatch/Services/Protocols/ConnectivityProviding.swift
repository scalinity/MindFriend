import Foundation

/// Protocol for Watch connectivity abstraction (enables testing without paired device)
@MainActor
protocol ConnectivityProviding {
    var isReachable: Bool { get }

    // Watch → iOS
    func sendMoodToPhone(_ mood: String, score: Int)
    func sendBreathingCompletedToPhone(cycles: Int)
    func sendQuestCompletedToPhone(questId: String)
    func requestSyncFromPhone()

    // Callbacks
    var onMoodReceived: ((String, Int) -> Void)? { get set }
    var onQuestCompleted: ((String) -> Void)? { get set }
    var onBreathingCompleted: ((Int) -> Void)? { get set }
    var onSyncRequested: (() -> Void)? { get set }
}
