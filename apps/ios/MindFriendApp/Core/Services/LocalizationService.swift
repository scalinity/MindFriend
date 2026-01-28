//
//  LocalizationService.swift
//  MindFriendApp
//
//  Created by dev-pipeline on 2026-01-19.
//  Manages user language preferences, translation loading, and RTL support
//

import Foundation
import Supabase
import SwiftUI

// MARK: - Bundle Extension for Runtime Language Switching

private var bundleKey: UInt8 = 0

/// Custom bundle class that loads resources from a specific language bundle
final class LocalizedBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        guard let bundle = objc_getAssociatedObject(self, &bundleKey) as? Bundle else {
            return super.localizedString(forKey: key, value: value, table: tableName)
        }
        return bundle.localizedString(forKey: key, value: value, table: tableName)
    }
}

extension Bundle {
    /// The currently selected language bundle for localization
    private(set) static var languageBundle: Bundle?
    
    /// Set the app's language bundle for runtime language switching
    static func setLanguage(_ languageCode: String) {
        // Set AppleLanguages preference (iOS respects this for localization)
        UserDefaults.standard.set([languageCode], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
        
        // Map language code to bundle path
        let bundlePath: String?
        switch languageCode {
        case "pt-BR":
            // Try Portuguese (Brazil) first, then generic Portuguese
            bundlePath = Bundle.main.path(forResource: "pt-BR", ofType: "lproj")
                ?? Bundle.main.path(forResource: "pt", ofType: "lproj")
        case "zh-CN":
            bundlePath = Bundle.main.path(forResource: "zh-Hans", ofType: "lproj")
        case "zh-TW":
            bundlePath = Bundle.main.path(forResource: "zh-Hant", ofType: "lproj")
        default:
            bundlePath = Bundle.main.path(forResource: languageCode, ofType: "lproj")
        }
        
        // Fall back to Base or English if language bundle not found
        let finalPath = bundlePath
            ?? Bundle.main.path(forResource: "Base", ofType: "lproj")
            ?? Bundle.main.path(forResource: "en", ofType: "lproj")
        
        if let path = finalPath, let bundle = Bundle(path: path) {
            // Store the language bundle for direct access
            languageBundle = bundle
            
            // Swap the main bundle class to our custom one
            object_setClass(Bundle.main, LocalizedBundle.self)
            objc_setAssociatedObject(Bundle.main, &bundleKey, bundle, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            print("ℹ️ Language bundle set to: \(path)")
        } else {
            print("⚠️ Could not find bundle for language: \(languageCode)")
        }
    }
    
    /// Reset to system language
    static func resetLanguage() {
        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
        languageBundle = nil
        objc_setAssociatedObject(Bundle.main, &bundleKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let languageDidChange = Notification.Name("languageDidChange")
}

// MARK: - Localization Service

@MainActor
class LocalizationService: ObservableObject {
    static let shared = LocalizationService()

    // MARK: - Published Properties

    @Published var currentLanguage: String = "en"
    @Published var isRTL: Bool = false
    
    /// Increment this to force SwiftUI views to refresh when language changes
    @Published var refreshTrigger: Int = 0

    // MARK: - Private Properties

    private var cachedTranslations: [String: String] = [:]
    private var contentTranslationsCache: [String: ContentTranslation] = [:]
    private var supabase: SupabaseClient?

    // MARK: - Initialization

    init(supabase: SupabaseClient? = nil) {
        self.supabase = supabase
        loadSavedLanguage()
    }
    
    /// Configure the service with a Supabase client (called from DependencyContainer)
    func configure(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    // MARK: - Language Selection

    /// Load saved language preference from UserDefaults or detect from device
    private func loadSavedLanguage() {
        if let saved = UserDefaults.standard.string(forKey: "preferred_language") {
            currentLanguage = saved
        } else {
            // Auto-detect from device locale
            if let deviceLanguage = Locale.current.language.languageCode?.identifier {
                // Check if device language is supported
                let supportedCodes = ["en", "es", "pt-BR", "fr", "de", "it", "nl", "pl", "ja", "ko", "zh-CN", "ar", "he"]
                currentLanguage = supportedCodes.contains(deviceLanguage) ? deviceLanguage : "en"
            } else {
                currentLanguage = "en"
            }
        }
        // Apply the saved language to the bundle
        Bundle.setLanguage(currentLanguage)
        updateDirection()
    }

    /// Set user's preferred language (saves preference, doesn't trigger UI refresh)
    /// - Returns: Whether a restart is needed for the language change
    @discardableResult
    func setLanguage(_ languageCode: String) async throws -> Bool {
        let previousLanguage = currentLanguage
        currentLanguage = languageCode
        UserDefaults.standard.set(languageCode, forKey: "preferred_language")
        
        // Apply language to bundle immediately
        Bundle.setLanguage(languageCode)
        updateDirection()
        
        // Note: We don't increment refreshTrigger here because that would destroy
        // the settings view before the restart alert can be shown.
        // The refresh will happen when the app restarts.

        // Update server preference (if authenticated)
        do {
            if let client = supabase {
                let session = try await client.auth.session
                let userId = session.user.id
                try await client
                    .from("profiles")
                    .update(["preferred_language": languageCode])
                    .eq("id", value: userId.uuidString)
                    .execute()
            }
        } catch {
            // If not authenticated or server update fails, continue with local update
            print("⚠️ Could not update server language preference: \(error)")
        }

        // Reload translations for new language
        try await loadTranslations()
        
        // Post notification for any observers that need to know about language change
        NotificationCenter.default.post(name: .languageDidChange, object: nil, userInfo: ["language": languageCode])
        
        // Return whether language actually changed (restart is needed)
        return previousLanguage != languageCode
    }
    
    /// Force the app to restart with new language (call from UI after language change)
    func forceLanguageRestart() {
        // The most reliable way to apply language changes is to restart the app
        // This exits the app - user will need to relaunch
        exit(0)
    }
    
    /// Trigger a UI refresh (use sparingly - causes full view recreation)
    func triggerRefresh() {
        refreshTrigger += 1
    }

    /// Update RTL flag based on current language
    private func updateDirection() {
        let rtlLanguages = ["ar", "he", "fa", "ur"]
        isRTL = rtlLanguages.contains(currentLanguage)
    }

    // MARK: - UI Translations

    /// Load all UI translations from server for current language
    func loadTranslations() async throws {
        let translations: [UITranslation] = (try await supabase?
            .from("ui_translations")
            .select()
            .eq("language_code", value: currentLanguage)
            .execute()
            .value) ?? []

        // Populate cache
        cachedTranslations = Dictionary(
            uniqueKeysWithValues: translations.map { ($0.stringKey, $0.translation) }
        )

        print("ℹ️ Loaded \(cachedTranslations.count) translations for \(currentLanguage)")
    }

    /// Translate a UI string with fallback chain
    func translate(_ key: String, default defaultValue: String? = nil) -> String {
        // Step 1: Check cached translations (fastest)
        if let translation = cachedTranslations[key] {
            return translation
        }

        // Step 2: Check bundle for NSLocalizedString (compiled-in fallback)
        let bundleTranslation = NSLocalizedString(key, bundle: .main, comment: "")
        if bundleTranslation != key {
            return bundleTranslation
        }

        // Step 3: Use provided default value
        if let defaultValue = defaultValue {
            return defaultValue
        }

        // Step 4: Return the key itself (last resort)
        #if DEBUG
        print("⚠️ Missing translation: \(key) for language: \(currentLanguage)")
        #endif
        return key
    }

    /// Translate a string with format arguments
    func translate(_ key: String, arguments: CVarArg...) -> String {
        let format = translate(key)
        return String(format: format, arguments: arguments)
    }

    // MARK: - Content Translations

    /// Get translated content with fallback chain
    func getContentTranslation(
        type: String,
        id: UUID,
        field: String
    ) async throws -> String? {
        let cacheKey = "\(type)-\(id.uuidString)-\(currentLanguage)"

        // Check cache first
        if let cached = contentTranslationsCache[cacheKey] {
            return extractField(from: cached, field: field)
        }

        // Step 1: Try user's preferred language
        if let translation = try await fetchContentTranslation(
            type: type,
            id: id,
            language: currentLanguage
        ) {
            contentTranslationsCache[cacheKey] = translation
            return extractField(from: translation, field: field)
        }

        // Step 2: Fallback to English if not user's language
        if currentLanguage != "en" {
            if let englishTranslation = try await fetchContentTranslation(
                type: type,
                id: id,
                language: "en"
            ) {
                return extractField(from: englishTranslation, field: field)
            }
        }

        // Step 3: Return nil (caller should fall back to original content)
        #if DEBUG
        print("⚠️ Missing content translation: \(type).\(field) (\(id)) for language: \(currentLanguage)")
        #endif
        return nil
    }

    /// Fetch content translation from server
    private func fetchContentTranslation(
        type: String,
        id: UUID,
        language: String
    ) async throws -> ContentTranslation? {
        let result: [ContentTranslation] = (try await supabase?
            .from("content_translations")
            .select()
            .eq("content_type", value: type)
            .eq("content_id", value: id.uuidString)
            .eq("language_code", value: language)
            .eq("is_verified", value: true)
            .execute()
            .value) ?? []

        return result.first
    }

    /// Extract specific field from content translation
    private func extractField(from translation: ContentTranslation, field: String) -> String? {
        switch field {
        case "title":
            return translation.title
        case "description":
            return translation.description
        case "content":
            return translation.content
        default:
            return nil
        }
    }

    // MARK: - Crisis Resources

    /// Get localized crisis resources for user's country and language
    func getCrisisResources() async throws -> CrisisResources {
        // Detect country from device region
        let countryCode = Locale.current.region?.identifier ?? "US"

        // Try to fetch localized resources
        let result: [LocalizedCrisisResources] = (try await supabase?
            .from("localized_crisis_resources")
            .select()
            .eq("country_code", value: countryCode)
            .eq("language_code", value: currentLanguage)
            .eq("is_active", value: true)
            .execute()
            .value) ?? []

        if let resource = result.first {
            return CrisisResources(from: resource)
        }

        // Fallback to English for same country
        if currentLanguage != "en" {
            let englishResult: [LocalizedCrisisResources] = (try await supabase?
                .from("localized_crisis_resources")
                .select()
                .eq("country_code", value: countryCode)
                .eq("language_code", value: "en")
                .eq("is_active", value: true)
                .execute()
                .value) ?? []

            if let resource = englishResult.first {
                return CrisisResources(from: resource)
            }
        }

        // Ultimate fallback to US English (hardcoded, always available)
        return CrisisResources.usDefault
    }

    // MARK: - Available Languages

    /// Fetch list of active languages for language picker
    func fetchAvailableLanguages() async throws -> [SupportedLanguage] {
        let languages: [SupportedLanguage] = (try await supabase?
            .from("supported_languages")
            .select()
            .eq("is_active", value: true)
            .order("name", ascending: true)
            .execute()
            .value) ?? []

        return languages
    }
}
