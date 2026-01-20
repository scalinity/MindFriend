import Foundation
import OSLog

@MainActor
final class StressSignatureViewModel: ObservableObject {
    @Published private(set) var signature: StressSignature?
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?

    private let dataService: SupabaseDataService

    init(dataService: SupabaseDataService) {
        self.dataService = dataService
    }

    /// Fetch stress signature from server
    func fetchSignature() async {
        isLoading = true
        error = nil

        do {
            signature = try await dataService.fetchStressSignature()
            print("[StressSignature] Loaded signature with \(self.signature?.patterns.count ?? 0) patterns")
        } catch {
            self.error = error
            print("[StressSignature] Failed to load signature: \(error)")
        }

        isLoading = false
    }

    /// Refresh signature data
    func refreshSignature() async {
        await fetchSignature()
    }

    /// Clear error state
    func clearError() {
        error = nil
    }
}
