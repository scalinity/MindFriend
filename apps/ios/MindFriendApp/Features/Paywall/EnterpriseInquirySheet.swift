import SwiftUI
import Supabase

// MARK: - Request/Response Types

private struct EnterpriseInquiryRequest: Codable {
    let name: String
    let email: String
    let companyName: String
    let employeeCount: String
    let message: String
}

private struct EnterpriseInquiryResponse: Codable {
    let success: Bool
    let inquiryId: String?
    let message: String?
    let error: String?
}

// MARK: - View

struct EnterpriseInquirySheet: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss

    @State private var name: String = ""
    @State private var email: String = ""
    @State private var companyName: String = ""
    @State private var employeeCount: String = "11-50"
    @State private var message: String = ""

    @State private var isSubmitting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false

    @State private var nameError: String?
    @State private var emailError: String?
    @State private var companyError: String?

    private let employeeCountOptions = ["1-10", "11-50", "51-200", "201-500", "500+"]
    private let maxNameLength = 100
    private let maxCompanyLength = 200
    private let maxMessageLength = 2000

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Full Name", text: $name)
                            .textContentType(.name)
                            .autocorrectionDisabled()
                            .onChange(of: name) { _, newValue in
                                if newValue.count > maxNameLength {
                                    name = String(newValue.prefix(maxNameLength))
                                }
                                nameError = nil
                            }

                        if let error = nameError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .accessibilityLabel("Name error: \(error)")
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Work Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: email) { _, _ in
                                emailError = nil
                            }

                        if let error = emailError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .accessibilityLabel("Email error: \(error)")
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Company Name", text: $companyName)
                            .autocorrectionDisabled()
                            .onChange(of: companyName) { _, newValue in
                                if newValue.count > maxCompanyLength {
                                    companyName = String(newValue.prefix(maxCompanyLength))
                                }
                                companyError = nil
                            }

                        if let error = companyError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .accessibilityLabel("Company error: \(error)")
                        }
                    }

                    Picker("Number of Employees", selection: $employeeCount) {
                        ForEach(employeeCountOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                } header: {
                    Text("Contact Information")
                }

                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        TextEditor(text: $message)
                            .frame(minHeight: 100)
                            .accessibilityLabel("Message")
                            .accessibilityHint("Optional message about your team's mental health needs")
                            .onChange(of: message) { _, newValue in
                                if newValue.count > maxMessageLength {
                                    message = String(newValue.prefix(maxMessageLength))
                                }
                            }

                        HStack {
                            Spacer()
                            Text("\(message.count)/\(maxMessageLength)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Message (Optional)")
                } footer: {
                    Text("Tell us about your team's mental health needs and any specific requirements.")
                }

                Section {
                    Button(action: submitInquiry) {
                        if isSubmitting {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .tint(.white)
                                Text("Submitting...")
                                    .foregroundStyle(.white)
                                Spacer()
                            }
                        } else {
                            HStack {
                                Spacer()
                                Text("Submit Inquiry")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                    }
                    .listRowBackground(Color.accentColor)
                    .foregroundStyle(.white)
                    .disabled(isSubmitting)
                }
            }
            .navigationTitle("Contact Sales")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .alert("Thank You!", isPresented: $showSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Your inquiry has been submitted. Our team will contact you within 24 hours.")
            }
            .interactiveDismissDisabled(isSubmitting)
            .keyboardDoneButton()
        }
    }

    private func validateForm() -> Bool {
        var isValid = true

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            nameError = "Name is required"
            isValid = false
        }

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedEmail.isEmpty {
            emailError = "Email is required"
            isValid = false
        } else if !isValidEmail(trimmedEmail) {
            emailError = "Please enter a valid email address"
            isValid = false
        }

        let trimmedCompany = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedCompany.isEmpty {
            companyError = "Company name is required"
            isValid = false
        }

        return isValid
    }

    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#
        let emailPredicate = NSPredicate(format: "SELF MATCHES[c] %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }

    private func submitInquiry() {
        guard validateForm() else { return }

        isSubmitting = true

        Task {
            do {
                let request = EnterpriseInquiryRequest(
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                    companyName: companyName.trimmingCharacters(in: .whitespacesAndNewlines),
                    employeeCount: employeeCount,
                    message: message.trimmingCharacters(in: .whitespacesAndNewlines)
                )

                let response: EnterpriseInquiryResponse = try await container.supabaseDataService.functions.invoke(
                    "enterprise-inquiry",
                    options: .init(body: request)
                )

                await MainActor.run {
                    if response.success {
                        showSuccess = true
                    } else if let error = response.error {
                        errorMessage = error
                        showError = true
                    } else {
                        showSuccess = true
                    }
                    isSubmitting = false
                }
            } catch {
                await MainActor.run {
                    if error.localizedDescription.contains("network") ||
                       error.localizedDescription.contains("connection") {
                        errorMessage = "Unable to submit inquiry. Please check your connection and try again."
                    } else {
                        errorMessage = "Something went wrong. Please try again or email support@getmindfriend.app directly."
                    }
                    showError = true
                    isSubmitting = false
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    EnterpriseInquirySheet()
}
#endif
