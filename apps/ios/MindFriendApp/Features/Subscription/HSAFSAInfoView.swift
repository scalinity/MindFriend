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
                VStack(spacing: SupportTheme.Spacing.l) {
                    // Header
                    VStack(spacing: SupportTheme.Spacing.s) {
                        Image(systemName: "heart.text.square.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(SupportTheme.accent)

                        Text("HSA/FSA Eligible")
                            .font(.title2)
                            .accessibilityAddTraits(.isHeader)
                            .fontWeight(.semibold)

                        Text("Use your health savings account for MindFriend Premium")
                            .font(.subheadline)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                    .multilineTextAlignment(.center)

                    // About Section
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                        HStack(spacing: SupportTheme.Spacing.xs) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(SupportTheme.accent)
                                .frame(width: 24)

                            Text("About HSA/FSA Eligibility")
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                        }

                        Text(
                            "MindFriend Premium is recognized by the IRS as an eligible mental health and wellness expense under Health Savings Accounts (HSA) and Flexible Spending Accounts (FSA). This means you can use pre-tax healthcare funds to cover your subscription."
                        )
                        .font(.body)
                        .foregroundStyle(SupportTheme.textSecondary)
                        .lineSpacing(1.2)
                    }
                    .padding()
                    .background(SupportTheme.surface)
                    .cornerRadius(SupportTheme.controlRadius)

                    // How It Works Section
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                        HStack(spacing: SupportTheme.Spacing.xs) {
                            Image(systemName: "checklist")
                                .foregroundStyle(SupportTheme.accent)
                                .frame(width: 24)

                            Text("How It Works")
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                        }

                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
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
                    .background(SupportTheme.surface)
                    .cornerRadius(SupportTheme.controlRadius)

                    // Receipt Section
                    if hasActiveSubscription {
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                            HStack(spacing: SupportTheme.Spacing.xs) {
                                Image(systemName: "receipt.fill")
                                    .foregroundStyle(SupportTheme.accent)
                                    .frame(width: 24)

                                Text("Your Receipt")
                                    .font(.headline)
                                    .accessibilityAddTraits(.isHeader)
                            }

                            if let url = generatedReceiptURL {
                                HStack(spacing: SupportTheme.Spacing.s) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(SupportTheme.accent)

                                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                                        Text("Receipt Generated")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)

                                        Text("Ready to submit")
                                            .font(.caption)
                                            .foregroundStyle(SupportTheme.textSecondary)
                                    }

                                    Spacer()
                                }
                                .padding()
                                .background(SupportTheme.surface)
                                .cornerRadius(SupportTheme.controlRadius)

                                ShareLink(
                                    item: url,
                                    subject: Text("MindFriend Premium Receipt"),
                                    message: Text("Here's my MindFriend Premium receipt for HSA/FSA reimbursement"),
                                    label: {
                                        HStack(spacing: SupportTheme.Spacing.xs) {
                                            Image(systemName: "square.and.arrow.up")
                                            Text("Share Receipt")
                                                .fontWeight(.semibold)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(SupportTheme.accent)
                                        .foregroundStyle(SupportTheme.onAccent)
                                        .cornerRadius(SupportTheme.controlRadius)
                                    }
                                )
                                .accessibilityLabel("Share receipt button")
                            } else {
                                Button {
                                    generateReceipt()
                                } label: {
                                    HStack(spacing: SupportTheme.Spacing.xs) {
                                        if isGeneratingReceipt {
                                            ProgressView()
                                                .tint(SupportTheme.textPrimary)
                                        } else {
                                            Image(systemName: "doc.badge.gearshape")
                                            Text("Generate Receipt")
                                                .fontWeight(.semibold)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(SupportTheme.accent)
                                    .foregroundStyle(SupportTheme.onAccent)
                                    .cornerRadius(SupportTheme.controlRadius)
                                }
                                .disabled(isGeneratingReceipt)
                                .accessibilityLabel("Generate receipt button")
                            }
                        }
                        .padding()
                        .background(SupportTheme.surface)
                        .cornerRadius(SupportTheme.controlRadius)
                    } else {
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                            HStack(spacing: SupportTheme.Spacing.xs) {
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(SupportTheme.textSecondary)
                                    .frame(width: 24)

                                Text("Active Subscription Required")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }

                            Text(
                                "You need an active MindFriend Premium subscription to generate receipts. Subscribe to get started."
                            )
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                        }
                        .padding()
                        .background(SupportTheme.surface)
                        .cornerRadius(SupportTheme.controlRadius)
                    }

                    // Disclaimers
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                        Text("Important Notes")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)

                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                            DiscaimerText(
                                "MindFriend's HSA/FSA eligibility is based on current IRS guidance. Individual plan eligibility varies."
                            )

                            DiscaimerText(
                                "Consult with your HSA/FSA plan administrator before submitting. They have final discretion on approval."
                            )

                            DiscaimerText(
                                "This receipt is provided for informational purposes and does not guarantee reimbursement."
                            )

                            DiscaimerText(
                                "We're not tax advisors. Consult a qualified tax professional for personalized advice.")
                        }
                    }
                    .supportCard()

                    // Error
                    if showError, let error = error {
                        HStack(spacing: SupportTheme.Spacing.xs) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)

                            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
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
                        .cornerRadius(SupportTheme.controlRadius)
                    }

                    Spacer(minLength: 20)
                }
                .padding()
            }
            .supportScreen()
            .foregroundStyle(SupportTheme.textPrimary)
            .navigationTitle("HSA/FSA Eligibility")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                    .accessibilityLabel("Close button")
                }
            }
            .task {
                do {
                    try await billingService.loadHSARecord()
                } catch {
                    Log.billing.error("Failed to load HSA record", error: error)
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
        HStack(alignment: .top, spacing: SupportTheme.Spacing.s) {
            Text("\(number)")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .fontWeight(.semibold)
                .foregroundStyle(SupportTheme.onAccent)
                .frame(width: 32, height: 32)
                .background(SupportTheme.accent)
                .cornerRadius(SupportTheme.controlRadius)

            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
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
        HStack(alignment: .top, spacing: SupportTheme.Spacing.xs) {
            Image(systemName: "circle.fill")
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
                .padding(.top, SupportTheme.Spacing.xxs)

            Text(text)
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
                .lineSpacing(1.1)
        }
    }
}

#Preview {
    HSAFSAInfoView()
        .environmentObject(DependencyContainer())
}
