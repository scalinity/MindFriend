import Foundation

struct PrivacyLockSettings: Codable, Equatable {
    var appLockEnabled: Bool
    var autoLockSeconds: Int
    var quickLockMethod: QuickLockMethod
    var tripleTapEnabled: Bool
    let userId: String?
    let createdAt: Date?
    var updatedAt: Date?

    enum QuickLockMethod: String, Codable, CaseIterable {
        case menu
        case tripleTap

        var displayName: String {
            switch self {
            case .menu: return "Menu"
            case .tripleTap: return "Triple Tap"
            }
        }

        var description: String {
            switch self {
            case .menu: return "Long-press the menu button to lock"
            case .tripleTap: return "Triple-tap anywhere to lock"
            }
        }
    }

    static let `default` = PrivacyLockSettings(
        appLockEnabled: false,
        autoLockSeconds: 300,
        quickLockMethod: .menu,
        tripleTapEnabled: false,
        userId: nil,
        createdAt: nil,
        updatedAt: nil
    )

    enum CodingKeys: String, CodingKey {
        case appLockEnabled = "app_lock_enabled"
        case autoLockSeconds = "auto_lock_seconds"
        case quickLockMethod = "quick_lock_method"
        case tripleTapEnabled = "triple_tap_enabled"
        case userId = "user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum AutoLockTimeout: Int, CaseIterable, Identifiable {
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1800
    case oneHour = 3600
    case never = 0

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .oneMinute: return "1 minute"
        case .fiveMinutes: return "5 minutes"
        case .fifteenMinutes: return "15 minutes"
        case .thirtyMinutes: return "30 minutes"
        case .oneHour: return "1 hour"
        case .never: return "Never"
        }
    }

    var seconds: Int {
        switch self {
        case .never: return Int.max
        default: return rawValue
        }
    }

    init?(seconds: Int) {
        switch seconds {
        case 60: self = .oneMinute
        case 300: self = .fiveMinutes
        case 900: self = .fifteenMinutes
        case 1800: self = .thirtyMinutes
        case 3600: self = .oneHour
        case 0: self = .never
        default: return nil
        }
    }
}
