//
//  SentryReplayMasking.swift
//  MindFriendApp
//
//  Created by Claude Code on 2026-01-18.
//  Copyright © 2026 MindFriend. All rights reserved.
//

import SwiftUI
import Sentry
// Note: privacySensitive() is available in Sentry module for SDK 8.x+
// import SentrySwiftUI

// MARK: - SwiftUI View Extensions for Sentry Session Replay

/// Extension providing semantic masking modifiers for Sentry session replay.
///
/// These modifiers wrap the SDK's built-in `privacySensitive()` with semantic names
/// that document the type of sensitive content being masked. This approach:
/// 1. Uses the SDK's official SwiftUI masking mechanism
/// 2. Provides semantic clarity about what content is being protected
/// 3. Makes code audits easier by clearly identifying sensitive UI elements
///
/// **Privacy Configuration (CrashReporter.swift):**
/// - `maskAllText = true` - All text is masked by default
/// - `maskAllImages = true` - All images are masked by default
/// - These modifiers provide explicit, defense-in-depth protection
extension View {
    /// Marks this view as sensitive content that should be masked in Sentry session replays.
    ///
    /// This modifier uses Sentry's built-in `privacySensitive()` for masking. Use this for
    /// any content containing:
    /// - Personal health information
    /// - User-generated content (journal entries, chat messages)
    /// - Mood scores and emotional states
    /// - Crisis-related content
    ///
    /// **Privacy Note:** Even with global `maskAllText=true`, apply this modifier to sensitive
    /// screens as defense-in-depth protection.
    ///
    /// - Returns: A view that Sentry will redact in session replays
    ///
    /// Example:
    /// ```swift
    /// VStack {
    ///     Text("How are you feeling?")
    ///     TextField("Share your thoughts...", text: $notes)
    ///         .sentryMask() // This text field will be masked
    /// }
    /// ```
    func sentryMask() -> some View {
        self.privacySensitive()
    }

    /// Marks mood-related content for masking in Sentry session replays.
    ///
    /// Semantic variant of `sentryMask()` for mood tracking screens. Helps identify
    /// mood-specific sensitive content during code audits.
    ///
    /// - Returns: A view that Sentry will redact in session replays
    func sentryMaskMood() -> some View {
        self.privacySensitive()
    }

    /// Marks chat content for masking in Sentry session replays.
    ///
    /// Semantic variant of `sentryMask()` for chat/conversation screens. Helps identify
    /// chat-specific sensitive content during code audits.
    ///
    /// - Returns: A view that Sentry will redact in session replays
    func sentryMaskChat() -> some View {
        self.privacySensitive()
    }

    /// Explicitly allows this view to be shown in Sentry session replays.
    ///
    /// **⚠️ USE WITH EXTREME CAUTION ⚠️**
    ///
    /// This modifier should ONLY be used for non-sensitive UI elements like:
    /// - Generic buttons ("Continue", "Cancel")
    /// - Navigation titles
    /// - Static labels
    ///
    /// **NEVER use on:**
    /// - User-generated content
    /// - Personal health information
    /// - Emotional state indicators
    /// - Crisis-related content
    ///
    /// ## Current Implementation: No-Op (By Design)
    ///
    /// **Why This Is Currently A No-Op:**
    /// This method intentionally does nothing because we use Sentry's global
    /// `maskAllText=true` setting configured in `CrashReporter.swift`. This provides
    /// a defense-in-depth security approach where:
    /// 1. Global setting masks ALL text by default (first layer)
    /// 2. Explicit `sentryMask()` on sensitive views (second layer)
    ///
    /// **Security Rationale:**
    /// Mental health apps contain highly sensitive personal health information (PHI).
    /// The no-op implementation ensures we CANNOT accidentally unmask sensitive content,
    /// even if `sentryUnmask()` is misapplied. The global `maskAllText=true` always wins.
    ///
    /// **Future Implementation Path:**
    /// If selective unmasking becomes necessary (e.g., for debugging specific UI elements):
    /// 1. Use `self.sentryReplayUnmask()` from Sentry SDK
    /// 2. **CRITICAL**: Require security review before enabling
    /// 3. **CRITICAL**: Update privacy audit documentation
    ///
    /// - Returns: The original view (unmodified - global masking still applies)
    func sentryUnmask() -> some View {
        // Intentional no-op: global maskAllText=true in CrashReporter provides
        // defense-in-depth. Cannot selectively unmask without security review.
        // To enable: replace with `self.sentryReplayUnmask()`
        self
    }
}

// MARK: - Legacy Support (Deprecated)

/// Legacy registration helper for custom UIView subclasses.
///
/// **DEPRECATED:** Sentry SDK 9.x provides built-in SwiftUI modifiers (`privacySensitive()`).
/// This enum is retained for backward compatibility but the custom view classes are no longer needed.
///
/// The SDK's built-in modifiers are now used directly in the View extension above.
@available(*, deprecated, message: "Use the SDK's built-in privacySensitive() modifier instead")
enum SentryReplayMasking {
    /// Empty array - custom view types are no longer needed with SDK 9.x built-in modifiers.
    /// Masking is now handled by the SDK's `privacySensitive()` SwiftUI modifier.
    static let sensitiveViewTypes: [AnyClass] = []
}
