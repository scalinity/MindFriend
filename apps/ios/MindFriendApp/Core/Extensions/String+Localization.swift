//
//  String+Localization.swift
//  MindFriendApp
//
//  Created by dev-pipeline on 2026-01-19.
//  String extension for easy localization
//

import Foundation

extension String {
    /// Localize this string using LocalizationService
    /// Usage: "home.greeting".localized
    var localized: String {
        LocalizationService.shared.translate(self)
    }

    /// Localize string with format arguments
    /// Usage: "welcome.message".localized(with: userName)
    func localized(with arguments: CVarArg...) -> String {
        LocalizationService.shared.translate(self, arguments: arguments)
    }
}
