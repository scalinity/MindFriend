import Foundation
import HealthKit

/// Extracts HRV-based polyvagal features from HealthKit
final class HRVPolyvagalExtractor {
    // MARK: - Properties

    private let healthKitService: HealthKitService
    
    // PERFORMANCE: Cache recent HRV query results
    private var cachedHRVFeatures: PolyvagalHRVFeatures?
    private var cacheTimestamp: Date?
    private let cacheValidityDuration: TimeInterval = 60 // 1 minute cache

    // MARK: - Initialization

    init(healthKitService: HealthKitService) {
        self.healthKitService = healthKitService
    }

    // MARK: - Public Interface

    /// Extract recent HRV data for polyvagal classification
    /// - Parameter lookbackMinutes: How far back to query (default 5 minutes)
    /// - Returns: HRV polyvagal features, or nil if no data available
    func extractRecentHRV(lookbackMinutes: Int = 5) async throws -> PolyvagalHRVFeatures? {
        // PERFORMANCE: Return cached value if still valid
        if let cached = cachedHRVFeatures,
           let cacheTime = cacheTimestamp,
           Date().timeIntervalSince(cacheTime) < cacheValidityDuration {
            return cached
        }
        
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

        let features = PolyvagalHRVFeatures(
            rmssd: rmssd,
            sdnn: sdnn,
            timestamp: samples.last?.endDate ?? Date()
        )
        
        // Cache the result
        cachedHRVFeatures = features
        cacheTimestamp = Date()
        
        return features
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

        // Extract SDNN values from HealthKit (heartRateVariabilitySDNN)
        let sdnnValues = samples.map { $0.quantity.doubleValue(for: unit) }

        // Use most recent SDNN value
        let sdnn = sdnnValues.last ?? 0

        // Note: HealthKit doesn't provide raw RR intervals, so we can't calculate true RMSSD.
        // For MVP, we use SDNN as a proxy for both metrics since SDNN is the only available HRV metric.
        // This is documented as a known limitation - future versions could use HealthKit's
        // heartbeatSeries API to calculate true RMSSD from RR intervals.
        let rmssd = sdnn

        return (rmssd, sdnn)
    }
}
