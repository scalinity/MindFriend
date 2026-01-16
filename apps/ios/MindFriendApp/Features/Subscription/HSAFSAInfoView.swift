import SwiftUI

// MARK: - Spec 15: HSA/FSA Receipt Generation
// Requires: DependencyContainer, BillingService, HSAFSARecord (from BusinessModels)
// Types resolved from module scope at compile time
// IRS Compliance: Generates receipts for CPT code 90899 (behavioral telehealth)

/// Educational view and receipt generator for HSA/FSA eligibility
struct HSAFSAInfoView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss

    @State private var isGeneratingReceipt = false
    @State private var generatedReceiptURL: URL?
    @State private var error: Error?
    @State private var showError = false

    private var billingService: BillingService {
        container.billingService
    }

    private var hasActiveSubscription: Bool {
        billingService.subscription?.status == .active
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "heart.text.square.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.blue)

                        Text("HSA/FSA Eligible")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("Use your health savings account for MindFriend Premium")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)

                    // About Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(.blue)
                                .frame(width: 24)

                            Text("About HSA/FSA Eligibility")
                                .font(.headline)
                        }

                        Text("MindFriend Premium is recognized by the IRS as an eligible mental health and wellness expense under Health Savings Accounts (HSA) and Flexible Spending Accounts (FSA). This means you can use pre-tax healthcare funds to cover your subscription.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineSpacing(1.2)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(12)

                    // How It Works Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "checklist")
                                .foregroundStyle(.green)
                                .frame(width: 24)

                            Text("How It Works")
                                .font(.headline)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            StepRow(
                                number: 1,
                                title: "Subscribe to Premium",
                                description: "Choose your plan and complete your subscription"
                            )

                            StepRow(
                                number: 2,
                                title: "Generate Receipt",
                                description: "Request an itemized receipt in this section"
                            )

                            StepRow(
                                number: 3,
                                title: "Submit to Your HSA/FSA",
                                description: "Provide the receipt to your account administrator"
                            )

                            StepRow(
                                number: 4,
                                title: "Get Reimbursed",
                                description: "Receive reimbursement from your healthcare account"
                            )
                        }
                    }
                    .padding()
                    .background(Color.green.opacity(0.05))
                    .cornerRadius(12)

                    // Receipt Section
                    if hasActiveSubscription {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "receipt.fill")
                                    .foregroundStyle(.orange)
                                    .frame(width: 24)

                                Text("Your Receipt")
                                    .font(.headline)
                            }

                            if let url = generatedReceiptURL {
                                HStack(spacing: 12) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Receipt Generated")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)

                                        Text("Ready to submit")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()
                                }
                                .padding()
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(8)

                                ShareLink(
                                    item: url,
                                    subject: Text("MindFriend Premium Receipt"),
                                    message: Text("Here's my MindFriend Premium receipt for HSA/FSA reimbursement"),
                                    label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "square.and.arrow.up")
                                            Text("Share Receipt")
                                                .fontWeight(.semibold)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.accentColor)
                                        .foregroundStyle(.white)
                                        .cornerRadius(8)
                                    }
                                )
                                .accessibilityLabel("Share receipt button")
                            } else {
                                Button {
                                    generateReceipt()
                                } label: {
                                    HStack(spacing: 8) {
                                        if isGeneratingReceipt {
                                            ProgressView()
                                                .tint(.white)
                                        } else {
                                            Image(systemName: "doc.badge.gearshape")
                                            Text("Generate Receipt")
                                                .fontWeight(.semibold)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.orange)
                                    .foregroundStyle(.white)
                                    .cornerRadius(8)
                                }
                                .disabled(isGeneratingReceipt)
                                .accessibilityLabel("Generate receipt button")
                            }
                        }
                        .padding()
                        .background(Color.orange.opacity(0.05))
                        .cornerRadius(12)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24)

                                Text("Active Subscription Required")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }

                            Text("You need an active MindFriend Premium subscription to generate receipts. Subscribe to get started.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(12)
                    }

                    // Disclaimers
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Important Notes")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 6) {
                            DiscaimerText("MindFriend's HSA/FSA eligibility is based on current IRS guidance. Individual plan eligibility varies.")

                            DiscaimerText("Consult with your HSA/FSA plan administrator before submitting. They have final discretion on approval.")

                            DiscaimerText("This receipt is provided for informational purposes and does not guarantee reimbursement.")

                            DiscaimerText("We're not tax advisors. Consult a qualified tax professional for personalized advice.")
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)

                    // Error
                    if showError, let error = error {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Error")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)

                                Text(error.localizedDescription)
                                    .font(.caption)
                            }

                            Spacer()
                        }
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                    }

                    Spacer(minLength: 20)
                }
                .padding()
            }
            .navigationTitle("HSA/FSA Eligibility")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Close button")
                }
            }
            .task {
                do {
                    try await billingService.loadHSARecord()
                } catch {
                    print("Failed to load HSA record: \(error)")
                }
            }
        }
    }

    private func generateReceipt() {
        isGeneratingReceipt = true
        showError = false

        Task {
            do {
                let url = try await billingService.generateHSAReceipt()
                await MainActor.run {
                    generatedReceiptURL = url
                    isGeneratingReceipt = false
                }
            } catch let error as BillingError {
                await MainActor.run {
                    self.error = error
                    showError = true
                    isGeneratingReceipt = false
                }
            } catch {
                await MainActor.run {
                    self.error = error
                    showError = true
                    isGeneratingReceipt = false
                }
            }
        }
    }
}

// MARK: - Step Row

private struct StepRow: View {
    let number: Int
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color.green)
                .cornerRadius(16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

// MARK: - Disclaimer Text

private struct DiscaimerText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(1.1)
        }
    }
}

#Preview {
    HSAFSAInfoView()
        .environmentObject(DependencyContainer())
}
