// Spec 14: Accessibility Settings
// Main accessibility settings page with 6 sections

import SwiftUI

struct AccessibilitySettingsView: View {
    @EnvironmentObject var container: DependencyContainer
    @State private var hapticFeedbackEnabled = true
    @State private var soundEffectsEnabled = true
    @State private var reduceMotionEnabled = false

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
                    Toggle("Haptic Feedback", isOn: $hapticFeedbackEnabled)
                        .onChange(of: hapticFeedbackEnabled) { _, value in
                            Task {
                                // Persist change via service
                                Log.ui.info("Haptic feedback changed to: \(value)")
                            }
                        }
                    Toggle("Sound Effects", isOn: $soundEffectsEnabled)
                        .onChange(of: soundEffectsEnabled) { _, value in
                            Task {
                                // Persist change via service
                                Log.ui.info("Sound effects changed to: \(value)")
                            }
                        }
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
                    Toggle("Reduce Motion", isOn: $reduceMotionEnabled)
                        .onChange(of: reduceMotionEnabled) { _, value in
                            Task {
                                // Persist change via service
                                Log.ui.info("Reduce motion changed to: \(value)")
                            }
                        }
                    Toggle("Button Shapes", isOn: .constant(true))
                        .disabled(true)
                        .accessibilityHint("Button shapes setting is system-wide")
                    Stepper("Touch Area Size", value: .constant(1.0), in: 0.8...1.5, step: 0.1)
                        .accessibilityLabel("Touch Area Size")
                        .accessibilityValue("1.0x")
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
