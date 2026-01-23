import Foundation
import HealthKit

/// Extracts HRV-based polyvagal features from HealthKit
final class HRVPolyvagalExtractor {
    // MARK: - Properties

    private let healthKitService: HealthKitService

    // MARK: - Initialization

    init(healthKitService: HealthKitService) {
        self.healthKitService = healthKitService
    }

    // MARK: - Public Interface

    /// Extract recent HRV data for polyvagal classification
    /// - Parameter lookbackMinutes: How far back to query (default 5 minutes)
    /// - Returns: HRV polyvagal features, or nil if no data available
    func extractRecentHRV(lookbackMinutes: Int = 5) async throws -> PolyvagalHRVFeatures? {
        guard healthKitService.isHealthKitAvailable else {
            return nil
        }

        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-Double(lookbackMinutes * 60))

        // Query HRV samples
        let samples = try await queryHRVSamples(from: startDate, to: endDate)

        guard !samples.isEmpty else {
            return nil
        }

        // Calculate RMSSD and SDNN from samples
        let (rmssd, sdnn) = calculateHRVMetrics(from: samples)

        return PolyvagalHRVFeatures(
            rmssd: rmssd,
            sdnn: sdnn,
            timestamp: samples.last?.endDate ?? Date()
        )
    }

    // MARK: - Private Methods - HealthKit Queries

    private func queryHRVSamples(from startDate: Date, to endDate: Date) async throws -> [HKQuantitySample] {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            throw NervousSystemError.healthKitUnauthorized
        }

        // Check authorization
        let authStatus = healthKitService.healthStore.authorizationStatus(for: hrvType)
        guard authStatus == .sharingAuthorized else {
            throw NervousSystemError.healthKitUnauthorized
        }

        // Create predicate for time range
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictEndDate
        )

        // Create query
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrvType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let hrvSamples = samples as? [HKQuantitySample] ?? []
                continuation.resume(returning: hrvSamples)
            }

            healthKitService.healthStore.execute(query)
        }
    }

    // MARK: - Private Methods - HRV Calculations

    private func calculateHRVMetrics(from samples: [HKQuantitySample]) -> (rmssd: Double, sdnn: Double) {
        guard !samples.isEmpty else {
            return (0, 0)
        }

        let unit = HKUnit.secondUnit(with: .milli)

        // Extract HRV values (SDNN from HealthKit)
        let hrvValues = samples.map { $0.quantity.doubleValue(for: unit) }

        // Calculate SDNN (standard deviation of NN intervals)
        // HealthKit already provides SDNN in its heartRateVariabilitySDNN samples
        let sdnn = hrvValues.last ?? 0

        // Calculate RMSSD (root mean square of successive differences)
        // Approximate from SDNN since HealthKit doesn't provide raw RR intervals
        // Clinical approximation: RMSSD ≈ 0.85 * SDNN for short-term HRV
        let rmssd = sdnn * 0.85

        return (rmssd, sdnn)
    }
}
