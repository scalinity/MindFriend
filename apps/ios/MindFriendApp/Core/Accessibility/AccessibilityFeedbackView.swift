// Spec 14: Accessibility Feedback
// Report accessibility issues and provide feedback to improve feature coverage

import SwiftUI

struct AccessibilityFeedbackView: View {
    @State private var feedbackType = "feature_request"
    @State private var affectedFeature = ""
    @State private var severity = "medium"
    @State private var description = ""
    @State private var includeContact = false
    @State private var email = ""
    @State private var showSubmitConfirmation = false
    @Environment(\.dismiss) var dismiss

    var isFormValid: Bool {
        !affectedFeature.trimmingCharacters(in: .whitespaces).isEmpty &&
        !description.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Feedback Type") {
                    Picker("Type", selection: $feedbackType) {
                        Text("Feature Request").tag("feature_request")
                        Text("Bug Report").tag("bug_report")
                        Text("Improvement").tag("improvement")
                        Text("Content Issue").tag("content_issue")
                        Text("Other").tag("other")
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel("Feedback Type")
                    .accessibilityHint("Select the type of feedback you want to provide")
                }

                Section("Affected Feature") {
                    Picker("Which feature?", selection: $affectedFeature) {
                        Text("Visual Accessibility").tag("visual")
                        Text("Audio & Captions").tag("audio")
                        Text("Text Size").tag("text_size")
                        Text("Language & Localization").tag("language")
                        Text("Motor & Interaction").tag("motor")
                        Text("Sign Language Videos").tag("sign_language")
                        Text("General/Other").tag("other")
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel("Affected Feature")
                    .accessibilityHint("Select which feature your feedback is about")
                }

                if feedbackType == "bug_report" {
                    Section("Severity") {
                        Picker("How severe?", selection: $severity) {
                            Text("Minor - Cosmetic issue").tag("minor")
                            Text("Medium - Affects usage").tag("medium")
                            Text("Critical - Blocks access").tag("critical")
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Section("Details") {
                    TextEditor(text: $description)
                        .frame(minHeight: 120)
                        .placeholder(when: description.isEmpty) {
                            Text("Describe the issue or suggestion in detail...")
                                .foregroundColor(.gray)
                        }
                }

                Section("Contact Information") {
                    Toggle("I'd like to be contacted about this feedback", isOn: $includeContact)

                    if includeContact {
                        TextField("Your email", text: $email)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                    }
                }

                Section("Privacy Notice") {
                    Label("Your feedback helps us improve accessibility for everyone", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section {
                    Button(action: submitFeedback) {
                        Text("Submit Feedback")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isFormValid)
                }
            }
            .navigationTitle("Report Issue")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Feedback Submitted", isPresented: $showSubmitConfirmation) {
                Button("Done") {
                    dismiss()
                }
            } message: {
                Text("Thank you for helping us improve accessibility. Your feedback has been received.")
            }
        }
    }

    private func submitFeedback() {
        // TODO: Submit feedback to Edge Function or database
        // - Log to accessibility_feedback table
        // - Include: type, affected_feature, severity, description, email (if provided)
        // - Send to support team via email or notification
        showSubmitConfirmation = true
    }
}

// MARK: - Placeholder Modifier

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

#Preview {
    AccessibilityFeedbackView()
}
