//
//  View+Localization.swift
//  MindFriendApp
//
//  Created by dev-pipeline on 2026-01-19.
//  SwiftUI view modifier for RTL layout support
//

import SwiftUI

// MARK: - Environment Key

struct LayoutDirectionKey: EnvironmentKey {
    static let defaultValue: LayoutDirection = .leftToRight
}

extension EnvironmentValues {
    var appLayoutDirection: LayoutDirection {
        get { self[LayoutDirectionKey.self] }
        set { self[LayoutDirectionKey.self] = newValue }
    }
}

// MARK: - View Modifier

/// View modifier that applies correct layout direction for RTL languages
struct LocalizedView: ViewModifier {
    @ObservedObject var localization = LocalizationService.shared

    func body(content: Content) -> some View {
        content
            .environment(\.layoutDirection, localization.isRTL ? .rightToLeft : .leftToRight)
            .environment(\.appLayoutDirection, localization.isRTL ? .rightToLeft : .leftToRight)
    }
}

extension View {
    /// Apply localization with RTL support
    /// Usage: MyView().localized()
    func localized() -> some View {
        modifier(LocalizedView())
    }
}
