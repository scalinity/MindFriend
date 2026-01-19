//
//  SentryReplayMasking.swift
//  MindFriendApp
//
//  Created by Claude Code on 2026-01-18.
//  Copyright © 2026 MindFriend. All rights reserved.
//

import SwiftUI
import Sentry

// MARK: - UIView Subclasses for Sentry Masking

/// Custom UIView subclass that Sentry will mask in session replays.
/// Used internally by the `.sentryMask()` modifier.
private final class SensitiveContentView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        // Programmatic initialization only - this view is never used in Interface Builder
        super.init(coder: coder)
    }
}

/// Custom UIView subclass for mood-related content masking.
private final class MoodInputView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        // Programmatic initialization only - this view is never used in Interface Builder
        super.init(coder: coder)
    }
}

/// Custom UIView subclass for chat content masking.
private final class ChatContentView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        // Programmatic initialization only - this view is never used in Interface Builder
        super.init(coder: coder)
    }
}

// MARK: - UIViewRepresentable Wrapper

/// Generic UIViewRepresentable that wraps content in a specified UIView subclass for Sentry masking.
///
/// This generic wrapper eliminates code duplication by providing a single implementation
/// that works with any UIView subclass (SensitiveContentView, MoodInputView, ChatContentView).
///
/// - Parameters:
///   - MaskView: The UIView subclass to use as the masking container
///   - Content: The SwiftUI view content to be masked
private struct MaskedContentWrapper<MaskView: UIView, Content: View>: UIViewRepresentable {
    let content: Content

    final class Coordinator {
        let hostingController: UIHostingController<Content>

        init(rootView: Content) {
            self.hostingController = UIHostingController(rootView: rootView)
            self.hostingController.view.backgroundColor = .clear
        }

        func update(content: Content) {
            hostingController.rootView = content
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(rootView: content)
    }

    func makeUIView(context: Context) -> MaskView {
        let view = MaskView()
        let hostingController = context.coordinator.hostingController
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        return view
    }

    func updateUIView(_ uiView: MaskView, context: Context) {
        context.coordinator.update(content: content)
    }
}

// MARK: - SwiftUI View Extensions

extension View {
    /// Marks this view as sensitive content that should be masked in Sentry session replays.
    ///
    /// This modifier wraps the view in a UIView subclass that Sentry will replace with a solid
    /// gray block in session recordings. Use this for any content containing:
    /// - Personal health information
    /// - User-generated content (journal entries, chat messages)
    /// - Mood scores and emotional states
    /// - Crisis-related content
    ///
    /// **Privacy Note:** Even with global `maskAllText=true`, apply this modifier to sensitive
    /// screens as defense-in-depth protection.
    ///
    /// - Returns: A view wrapped in a masking container that Sentry will redact
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
        MaskedContentWrapper<SensitiveContentView, Self>(content: self)
    }

    /// Marks mood-related content for masking in Sentry session replays.
    ///
    /// Specialized variant of `sentryMask()` for mood tracking screens. Creates a
    /// MoodInputView wrapper that can be specifically tracked and analyzed.
    ///
    /// - Returns: A view wrapped in a mood-specific masking container
    func sentryMaskMood() -> some View {
        MaskedContentWrapper<MoodInputView, Self>(content: self)
    }

    /// Marks chat content for masking in Sentry session replays.
    ///
    /// Specialized variant of `sentryMask()` for chat/conversation screens. Creates a
    /// ChatContentView wrapper that can be specifically tracked and analyzed.
    ///
    /// - Returns: A view wrapped in a chat-specific masking container
    func sentryMaskChat() -> some View {
        MaskedContentWrapper<ChatContentView, Self>(content: self)
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
    /// 3. Custom UIView subclasses for granular control (third layer)
    ///
    /// **Security Rationale:**
    /// Mental health apps contain highly sensitive personal health information (PHI).
    /// The no-op implementation ensures we CANNOT accidentally unmask sensitive content,
    /// even if `sentryUnmask()` is misapplied. The global `maskAllText=true` always wins.
    ///
    /// **Future Implementation Path:**
    /// If selective unmasking becomes necessary (e.g., for debugging specific UI elements),
    /// implement this by:
    /// 1. Create a `UnmaskedContentView: UIView` subclass
    /// 2. Add to Sentry's `unmaskViewTypes` configuration
    /// 3. Wrap content in `UIViewRepresentable` with `UnmaskedContentView`
    /// 4. **CRITICAL**: Require security review before enabling
    /// 5. **CRITICAL**: Update privacy audit documentation
    ///
    /// **Example Future Implementation:**
    /// ```swift
    /// private final class UnmaskedContentView: UIView { }
    ///
    /// func sentryUnmask() -> some View {
    ///     MaskedContentWrapper<UnmaskedContentView, Self>(content: self)
    /// }
    /// ```
    ///
    /// **Why Not Implement Now:**
    /// We don't currently need selective unmasking. Adding it would:
    /// - Increase attack surface (risk of misuse)
    /// - Complicate security audits
    /// - Violate principle of least privilege
    ///
    /// - Returns: The original view (unmodified - global masking still applies)
    func sentryUnmask() -> some View {
        // Intentional no-op: global maskAllText=true in CrashReporter provides
        // defense-in-depth. Cannot selectively unmask without UIView subclass.
        self
    }
}

// MARK: - Registration Helper

/// Registers custom UIView subclasses with Sentry for session replay masking.
///
/// Call this during Sentry SDK initialization in CrashReporter.swift:
///
/// ```swift
/// SentrySDK.start { options in
///     // ... other options ...
///     options.sessionReplay.redactViewTypes = SentryReplayMasking.sensitiveViewTypes
/// }
/// ```
enum SentryReplayMasking {
    /// Array of UIView subclasses that should be masked in session replays.
    static let sensitiveViewTypes: [AnyClass] = [
        SensitiveContentView.self,
        MoodInputView.self,
        ChatContentView.self
    ]
}
