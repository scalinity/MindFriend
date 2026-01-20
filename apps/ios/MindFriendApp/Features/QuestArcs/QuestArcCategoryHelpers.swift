//
//  QuestArcCategoryHelpers.swift
//  MindFriendApp
//
//  Shared helpers for quest arc category icons and colors
//  Eliminates duplication across QuestArcCatalogView, QuestArcDetailView, and QuestArcProgressCard
//

import SwiftUI

enum QuestArcCategory {
    /// Returns the SF Symbol icon name for a given category
    static func iconName(for category: String) -> String {
        switch category {
        case "stress": return "leaf.fill"
        case "sleep": return "moon.zzz.fill"
        case "confidence": return "star.fill"
        case "focus": return "target"
        case "resilience": return "flame.fill"
        default: return "sparkles"
        }
    }
    
    /// Returns the SwiftUI Color for a given category
    static func color(for category: String) -> Color {
        switch category {
        case "stress": return .green
        case "sleep": return .indigo
        case "confidence": return .orange
        case "focus": return .blue
        case "resilience": return .red
        default: return .accentColor
        }
    }
}

// MARK: - QuestArc Extension

extension QuestArc {
    /// Convenience property for category icon
    var categoryIconName: String {
        QuestArcCategory.iconName(for: category)
    }
    
    /// Convenience property for category color
    var categoryColorUI: Color {
        QuestArcCategory.color(for: category)
    }
}

// MARK: - Constants

enum QuestArcConstants {
    /// Number of days before a paused arc expires
    static let pauseExpirationDays = 30
}

// MARK: - Category Benefits

extension QuestArcCategory {
    /// Returns localized benefits description for a given category
    static func benefits(for category: String) -> [String] {
        switch category {
        case "stress":
            return [
                "Daily calming exercises",
                "Stress-relief techniques",
                "Mindful breathing practices",
                "Progressive relaxation skills"
            ]
        case "sleep":
            return [
                "Better sleep hygiene habits",
                "Evening wind-down routines",
                "Relaxation techniques for rest",
                "Sleep quality tracking"
            ]
        case "confidence":
            return [
                "Self-affirmation practices",
                "Positive self-talk exercises",
                "Goal-setting frameworks",
                "Celebrating small wins"
            ]
        case "focus":
            return [
                "Concentration exercises",
                "Distraction management",
                "Mindful attention training",
                "Productivity techniques"
            ]
        case "resilience":
            return [
                "Emotional regulation skills",
                "Coping strategy development",
                "Growth mindset cultivation",
                "Bouncing back from setbacks"
            ]
        default:
            return ["Daily wellness exercises", "Progress tracking", "Milestone celebrations"]
        }
    }
}
