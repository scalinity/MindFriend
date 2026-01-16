// Spec 14: Accessibility Settings
// Main accessibility settings page with 6 sections

import SwiftUI

struct AccessibilitySettingsView: View {
    @EnvironmentObject var container: DependencyContainer
    @State private var accessibility: AccessibilityService?

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Visual Accessibility
                Section("Visual") {
                    NavigationLink(destination: VisualAccessibilityView()) {
                        Label("Colors & Contrast", systemImage: "eye.fill")
                    }
                    NavigationLink(destination: TextSizeSettingsView()) {
                        Label("Text Size", systemImage: "textformat.size")
                    }
                }

                // MARK: - Audio & Captions
                Section("Audio") {
                    NavigationLink(destination: CaptionsView()) {
                        Label("Captions", systemImage: "captions.bubble.fill")
                    }
                    Toggle("Haptic Feedback", isOn: .constant(true))
                    Toggle("Sound Effects", isOn: .constant(true))
                }

                // MARK: - Language & Localization
                Section("Language") {
                    NavigationLink(destination: LanguageSettingsView()) {
                        Label("Language", systemImage: "globe")
                    }
                    NavigationLink(destination: TranscriptView()) {
                        Label("Transcripts", systemImage: "doc.text.fill")
                    }
                }

                // MARK: - Motor & Interaction
                Section("Motor") {
                    Toggle("Reduce Motion", isOn: .constant(false))
                    Toggle("Button Shapes", isOn: .constant(true))
                    Stepper("Touch Area Size", value: .constant(1.0), in: 0.8...1.5, step: 0.1)
                }

                // MARK: - Sign Language
                Section("Sign Language") {
                    NavigationLink(destination: SignLanguageView()) {
                        Label("Sign Language Videos", systemImage: "hand.raised.fill")
                    }
                }

                // MARK: - Feedback & Support
                Section("Support") {
                    NavigationLink(destination: AccessibilityFeedbackView()) {
                        Label("Report Issue", systemImage: "exclamationmark.bubble.fill")
                    }
                    Link(destination: URL(string: "https://getmindfriend.app/accessibility")!) {
                        Label("Accessibility Guide", systemImage: "book.fill")
                    }
                }
            }
            .navigationTitle("Accessibility")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    AccessibilitySettingsView()
        .environmentObject(DependencyContainer.preview)
}
