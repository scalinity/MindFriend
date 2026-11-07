import Foundation

@MainActor
protocol ConnectivityProviding {
    var isReachable: Bool { get }
    func sendMoodToPhone(_ mood: String, score: Int) throws
    func sendBreathingCompletedToPhone(cycles: Int) throws
    func sendQuestCompletedToPhone(questId: String) throws
    func requestSyncFromPhone()
}
