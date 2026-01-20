import Foundation
import CoreLocation

/// Protocol for location context provision (enables testing)
protocol LocationContextProviding {
    func getContext() async -> LocationContext
    func requestAccess() async -> Bool
}

/// Provides location context using CoreLocation
/// Detects home/work/other context based on significant locations
@MainActor
final class LocationContextProvider: NSObject, LocationContextProviding {
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?

    // Cached significant locations (home/work)
    private var homeLocation: CLLocation?
    private var workLocation: CLLocation?

    // Keys for storing significant locations in UserDefaults
    private enum StorageKeys {
        static let homeLatitude = "smartNotifications.homeLatitude"
        static let homeLongitude = "smartNotifications.homeLongitude"
        static let workLatitude = "smartNotifications.workLatitude"
        static let workLongitude = "smartNotifications.workLongitude"
    }

    // Distance threshold for location matching (meters)
    private let locationThreshold: CLLocationDistance = 200

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        loadSignificantLocations()
    }

    /// Request location access from the user
    func requestAccess() async -> Bool {
        let status = locationManager.authorizationStatus
        switch status {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
            // Wait briefly for authorization
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            return locationManager.authorizationStatus == .authorizedWhenInUse ||
                   locationManager.authorizationStatus == .authorizedAlways
        case .authorizedWhenInUse, .authorizedAlways:
            return true
        default:
            return false
        }
    }

    /// Get current location context
    /// Returns default context if permission denied
    func getContext() async -> LocationContext {
        let status = locationManager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            return .default
        }

        // Get current location
        let location = await getCurrentLocation()
        guard let location = location else {
            return .default
        }

        // Determine location type
        let (locationType, confidence) = determineLocationType(for: location)

        // Optionally update significant locations based on time of day
        updateSignificantLocationsIfNeeded(location: location)

        return LocationContext(
            type: locationType,
            confidenceScore: confidence
        )
    }

    /// Get current location with async/await
    private func getCurrentLocation() async -> CLLocation? {
        // Return cached location if recent (within 5 minutes)
        if let cached = currentLocation,
           Date().timeIntervalSince(cached.timestamp) < 300 {
            return cached
        }

        return await withCheckedContinuation { continuation in
            self.locationContinuation = continuation
            locationManager.requestLocation()

            // Timeout after 10 seconds
            Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if self.locationContinuation != nil {
                    self.locationContinuation?.resume(returning: nil)
                    self.locationContinuation = nil
                }
            }
        }
    }

    /// Determine location type based on distance to known locations
    private func determineLocationType(for location: CLLocation) -> (LocationType, Double) {
        // Check if near home
        if let home = homeLocation {
            let distance = location.distance(from: home)
            if distance < locationThreshold {
                let confidence = max(0, 1.0 - (distance / locationThreshold))
                return (.home, confidence)
            }
        }

        // Check if near work
        if let work = workLocation {
            let distance = location.distance(from: work)
            if distance < locationThreshold {
                let confidence = max(0, 1.0 - (distance / locationThreshold))
                return (.work, confidence)
            }
        }

        // Not near known locations
        return (.other, 0.5)
    }

    /// Update significant locations based on time patterns
    private func updateSignificantLocationsIfNeeded(location: CLLocation) {
        let hour = Calendar.current.component(.hour, from: Date())

        // Late night/early morning (10pm-7am) = likely home
        if hour >= 22 || hour < 7 {
            if homeLocation == nil {
                setHomeLocation(location)
            }
        }

        // Typical work hours (9am-5pm) on weekdays = likely work
        let weekday = Calendar.current.component(.weekday, from: Date())
        let isWeekday = weekday >= 2 && weekday <= 6
        if isWeekday && hour >= 9 && hour < 17 {
            if workLocation == nil {
                setWorkLocation(location)
            }
        }
    }

    // MARK: - Storage

    private func loadSignificantLocations() {
        let defaults = UserDefaults.standard

        if let homeLat = defaults.object(forKey: StorageKeys.homeLatitude) as? Double,
           let homeLon = defaults.object(forKey: StorageKeys.homeLongitude) as? Double {
            homeLocation = CLLocation(latitude: homeLat, longitude: homeLon)
        }

        if let workLat = defaults.object(forKey: StorageKeys.workLatitude) as? Double,
           let workLon = defaults.object(forKey: StorageKeys.workLongitude) as? Double {
            workLocation = CLLocation(latitude: workLat, longitude: workLon)
        }
    }

    /// Set home location (user can also set manually in settings)
    func setHomeLocation(_ location: CLLocation) {
        homeLocation = location
        let defaults = UserDefaults.standard
        defaults.set(location.coordinate.latitude, forKey: StorageKeys.homeLatitude)
        defaults.set(location.coordinate.longitude, forKey: StorageKeys.homeLongitude)
    }

    /// Set work location (user can also set manually in settings)
    func setWorkLocation(_ location: CLLocation) {
        workLocation = location
        let defaults = UserDefaults.standard
        defaults.set(location.coordinate.latitude, forKey: StorageKeys.workLatitude)
        defaults.set(location.coordinate.longitude, forKey: StorageKeys.workLongitude)
    }

    /// Clear significant locations (for privacy)
    func clearSignificantLocations() {
        homeLocation = nil
        workLocation = nil
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: StorageKeys.homeLatitude)
        defaults.removeObject(forKey: StorageKeys.homeLongitude)
        defaults.removeObject(forKey: StorageKeys.workLatitude)
        defaults.removeObject(forKey: StorageKeys.workLongitude)
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationContextProvider: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        Task { @MainActor in
            self.currentLocation = location
            self.locationContinuation?.resume(returning: location)
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Log.notifications.debug("[LocationContext] Location failed: \(error)")

        Task { @MainActor in
            self.locationContinuation?.resume(returning: nil)
            self.locationContinuation = nil
        }
    }
}
