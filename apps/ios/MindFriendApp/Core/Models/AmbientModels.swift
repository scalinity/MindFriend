// MARK: - Ambient Wellness Presence Models
// Theme enums, color palettes, and background types for ambient visual system

import SwiftUI

// MARK: - Ambient Theme

/// Available ambient themes for the app's visual environment.
/// Dawn, Day, Dusk, and Night automatically adjust based on time of day.
/// Ocean, Forest, and Calm are manual selections.
enum AmbientTheme: String, Codable, CaseIterable, Identifiable {
    case auto     // Represents current time-based theme
    case dawn     // 5:00 AM - 8:59 AM
    case day      // 9:00 AM - 4:59 PM
    case dusk     // 5:00 PM - 8:59 PM
    case night    // 9:00 PM - 4:59 AM
    case ocean    // Manual - blue/teal gradients
    case forest   // Manual - green gradients
    case calm     // Manual - neutral/lavender gradients

    var id: String { rawValue }

    /// Whether this theme participates in time-based auto-adjustment
    var isAutoAdjustable: Bool {
        switch self {
        case .auto, .dawn, .day, .dusk, .night:
            return true
        case .ocean, .forest, .calm:
            return false
        }
    }

    /// User-friendly display name
    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .dawn: return "Dawn"
        case .day: return "Day"
        case .dusk: return "Dusk"
        case .night: return "Night"
        case .ocean: return "Ocean"
        case .forest: return "Forest"
        case .calm: return "Calm"
        }
    }

    /// Description for settings UI
    var themeDescription: String {
        switch self {
        case .auto: return "Automatically adjusts to time of day"
        case .dawn: return "Soft pinks and oranges (5-9 AM)"
        case .day: return "Bright blues and whites (9 AM-5 PM)"
        case .dusk: return "Purple and orange gradients (5-9 PM)"
        case .night: return "Deep blues and purples (9 PM-5 AM)"
        case .ocean: return "Calming blue-teal gradients"
        case .forest: return "Peaceful green tones"
        case .calm: return "Soft neutral lavender"
        }
    }

    /// Icon for theme picker
    var icon: String {
        switch self {
        case .auto: return "clock.fill"
        case .dawn: return "sunrise.fill"
        case .day: return "sun.max.fill"
        case .dusk: return "sunset.fill"
        case .night: return "moon.stars.fill"
        case .ocean: return "water.waves"
        case .forest: return "leaf.fill"
        case .calm: return "cloud.fill"
        }
    }

    // MARK: - Color Palettes

    /// Primary gradient color (top/left)
    var primaryColor: Color {
        switch self {
        case .auto: return resolvedTheme.primaryColor
        case .dawn: return Color(red: 1.0, green: 0.7, blue: 0.73)    // #FFB3BA soft pink
        case .day: return Color(red: 0.73, green: 0.88, blue: 1.0)    // #BAE1FF sky blue
        case .dusk: return Color(red: 0.83, green: 0.73, blue: 1.0)   // #D4BAFF purple
        case .night: return Color(red: 0.10, green: 0.10, blue: 0.24) // #1A1A3E deep blue
        case .ocean: return Color(red: 0.0, green: 0.55, blue: 0.55)  // #008B8B teal
        case .forest: return Color(red: 0.13, green: 0.55, blue: 0.13) // #228B22 forest green
        case .calm: return Color(red: 0.90, green: 0.90, blue: 0.98)   // #E6E6FA lavender
        }
    }

    /// Secondary gradient color (bottom/right)
    var secondaryColor: Color {
        switch self {
        case .auto: return resolvedTheme.secondaryColor
        case .dawn: return Color(red: 1.0, green: 0.87, blue: 0.73)   // #FFDFBA light orange
        case .day: return Color(red: 0.73, green: 1.0, blue: 0.79)    // #BAFFC9 light cyan
        case .dusk: return Color(red: 1.0, green: 0.73, blue: 0.80)   // #FFBACC deep orange-pink
        case .night: return Color(red: 0.18, green: 0.18, blue: 0.37) // #2E2E5E dark purple
        case .ocean: return Color(red: 0.27, green: 0.51, blue: 0.71) // #4682B4 steel blue
        case .forest: return Color(red: 0.42, green: 0.56, blue: 0.14) // #6B8E23 olive
        case .calm: return Color(red: 0.69, green: 0.77, blue: 0.87)   // #B0C4DE pale blue
        }
    }

    /// Accent color for UI elements (buttons, highlights)
    var accentColor: Color {
        switch self {
        case .auto: return resolvedTheme.accentColor
        case .dawn: return Color(red: 1.0, green: 0.84, blue: 0.0)    // Gold
        case .day: return Color(red: 1.0, green: 0.84, blue: 0.0)     // Yellow
        case .dusk: return Color(red: 1.0, green: 0.73, blue: 0.95)   // #FFBAF3 pink
        case .night: return Color(red: 0.75, green: 0.75, blue: 0.75) // Silver
        case .ocean: return Color(red: 0.0, green: 0.81, blue: 0.82)  // #00CED1 cyan
        case .forest: return Color(red: 0.56, green: 0.93, blue: 0.56) // #90EE90 lime
        case .calm: return Color(red: 0.96, green: 0.96, blue: 0.96)   // Soft white
        }
    }

    /// Text color that contrasts with the gradient background
    var textColor: Color {
        switch self {
        case .auto: return resolvedTheme.textColor
        case .dawn, .day, .ocean, .forest, .calm:
            return Color(red: 0.15, green: 0.15, blue: 0.20)  // Dark text for light themes
        case .dusk, .night:
            return Color.white  // Light text for dark themes
        }
    }

    /// Gradient angle in degrees
    var gradientAngle: Angle {
        switch self {
        case .auto: return resolvedTheme.gradientAngle
        case .dawn: return .degrees(45)
        case .day: return .degrees(90)
        case .dusk: return .degrees(135)
        case .night: return .degrees(180)
        case .ocean: return .degrees(120)
        case .forest: return .degrees(60)
        case .calm: return .degrees(30)
        }
    }

    /// SF Symbol for particle animation
    var particleSymbol: String {
        switch self {
        case .auto: return resolvedTheme.particleSymbol
        case .dawn, .day, .dusk, .night, .calm:
            return "star.fill"
        case .ocean:
            return "drop.fill"
        case .forest:
            return "leaf.fill"
        }
    }

    /// Number of particles for animated background
    var particleCount: Int {
        switch self {
        case .auto: return resolvedTheme.particleCount
        case .dawn, .day: return 15
        case .dusk, .night: return 20
        case .ocean, .forest: return 25
        case .calm: return 10
        }
    }

    /// Particle velocity (points per second)
    var particleVelocity: CGFloat {
        switch self {
        case .auto: return resolvedTheme.particleVelocity
        case .dawn, .day: return 20   // Slow float up
        case .dusk, .night: return 15 // Slow float down
        case .ocean: return 40        // Rain effect
        case .forest: return 25       // Gentle drift
        case .calm: return 10         // Minimal drift
        }
    }

    /// Particle direction (degrees, 0 = right, 90 = up)
    var particleDirection: Angle {
        switch self {
        case .auto: return resolvedTheme.particleDirection
        case .dawn, .day: return .degrees(90)   // Up
        case .dusk, .night: return .degrees(270) // Down
        case .ocean: return .degrees(270)        // Rain down
        case .forest: return .degrees(225)       // Diagonal drift
        case .calm: return .degrees(0)           // Horizontal
        }
    }

    // MARK: - Time-Based Resolution

    /// The resolved theme for auto mode based on current time
    private var resolvedTheme: AmbientTheme {
        guard self == .auto else { return self }
        return AmbientTheme.forTimeOfDay()
    }

    /// Determine appropriate theme based on time of day
    static func forTimeOfDay(_ date: Date = Date()) -> AmbientTheme {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<9:    return .dawn
        case 9..<17:   return .day
        case 17..<21:  return .dusk
        default:       return .night  // 21-4
        }
    }

    /// All themes except 'auto' (for manual selection)
    static var selectableThemes: [AmbientTheme] {
        allCases.filter { $0 != .auto }
    }

    /// Time-based themes only
    static var timeBasedThemes: [AmbientTheme] {
        [.dawn, .day, .dusk, .night]
    }

    /// Manual themes only
    static var manualThemes: [AmbientTheme] {
        [.ocean, .forest, .calm]
    }
}

// MARK: - Background Type

/// Background rendering modes for ambient visuals
enum BackgroundType: String, Codable, CaseIterable, Identifiable {
    case `static`   // Solid color or simple gradient, no animation
    case dynamic    // Gradient shifts slowly based on time
    case animated   // Gradient + particle effects

    var id: String { rawValue }

    /// User-friendly display name
    var displayName: String {
        switch self {
        case .static: return "Static"
        case .dynamic: return "Dynamic"
        case .animated: return "Animated"
        }
    }

    /// Description for settings UI
    var description: String {
        switch self {
        case .static:
            return "Simple gradient, battery-efficient"
        case .dynamic:
            return "Gradient shifts slowly with time"
        case .animated:
            return "Gradient with gentle particle effects"
        }
    }

    /// Icon for background type picker
    var icon: String {
        switch self {
        case .static: return "square.fill"
        case .dynamic: return "square.stack.fill"
        case .animated: return "sparkles"
        }
    }
}

// MARK: - Ambient Preferences (Database Model)

/// User's ambient preferences stored in Supabase
struct AmbientPreferences: Codable, Equatable {
    let userId: UUID
    var activeTheme: AmbientTheme
    var backgroundType: BackgroundType
    var autoAdjustEnabled: Bool
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case activeTheme = "active_theme"
        case backgroundType = "background_type"
        case autoAdjustEnabled = "auto_adjust_enabled"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Create default preferences for a new user
    static func defaultPreferences(for userId: UUID) -> AmbientPreferences {
        AmbientPreferences(
            userId: userId,
            activeTheme: .auto,
            backgroundType: .dynamic,
            autoAdjustEnabled: true,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

// MARK: - Gradient Extension

extension LinearGradient {
    /// Create a gradient from an ambient theme
    static func forTheme(_ theme: AmbientTheme) -> LinearGradient {
        let angle = theme.gradientAngle
        let startPoint = UnitPoint(
            x: 0.5 + 0.5 * cos(angle.radians + .pi),
            y: 0.5 + 0.5 * sin(angle.radians + .pi)
        )
        let endPoint = UnitPoint(
            x: 0.5 + 0.5 * cos(angle.radians),
            y: 0.5 + 0.5 * sin(angle.radians)
        )

        return LinearGradient(
            colors: [theme.primaryColor, theme.secondaryColor],
            startPoint: startPoint,
            endPoint: endPoint
        )
    }
}
