//
//  String+Localization.swift
//  MindFriendApp
//
//  Created by dev-pipeline on 2026-01-19.
//  String extension for easy localization
//

import Foundation

extension String {
    /// Localize this string using the current language bundle
    /// Usage: "home.greeting".localized
    var localized: String {
        // Use the language bundle if available, otherwise fall back to main bundle
        if let bundle = Bundle.languageBundle {
            let translation = bundle.localizedString(forKey: self, value: nil, table: nil)
            // If translation is same as key, the string wasn't found - try main bundle
            if translation == self {
                return Bundle.main.localizedString(forKey: self, value: nil, table: nil)
            }
            return translation
        }
        return NSLocalizedString(self, comment: "")
    }

    /// Localize string with format arguments
    /// Usage: "welcome.message".localized(with: userName)
    func localized(with arguments: CVarArg...) -> String {
        String(format: self.localized, arguments: arguments)
    }
}
