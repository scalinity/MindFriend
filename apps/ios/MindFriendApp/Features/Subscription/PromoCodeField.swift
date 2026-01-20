import SwiftUI

// MARK: - Type Imports (Spec 15)
// NOTE: BillingService, PromoCode, and BillingError are injected via dependency container
// In preview, we create mock instances for demonstration

/// Reusable component for entering and validating promo codes
struct PromoCodeField: View {
    @ObservedObject var billingService: BillingService

    @Binding var code: String
    @Binding var validatedPromo: PromoCode?
    @Binding var isValidating: Bool

    @State private var showError = false
    @State private var errorMessage = ""

    var hasValidatedCode: Bool {
        validatedPromo != nil
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                TextField("Enter promo code", text: $code)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .disabled(hasValidatedCode || isValidating)
                    .accessibilityLabel("Promo code field")
                    .accessibilityHint("Enter uppercase letters and numbers")

                if hasValidatedCode {
                    Button {
                        clearPromoCode()
                    } label: {
                        Text("Clear")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Clear promo code button")
                } else if !code.isEmpty {
                    Button {
                        validateCode()
                    } label: {
                        if isValidating {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Apply")
                                .fontWeight(.semibold)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isValidating)
                    .accessibilityLabel("Apply promo code button")
                }
            }

            // Success message with discount
            if let promo = validatedPromo {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Promo Applied")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.green)

                        Text(promo.discountDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Promo code applied: \(promo.discountDescription)")
            }

            // Error message
            if showError {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Invalid Code")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.red)

                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Error: \(errorMessage)")
            }
        }
    }

    private func validateCode() {
        guard !code.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Please enter a promo code"
            showError = true
            return
        }

        showError = false
        errorMessage = ""
        isValidating = true

        Task {
            do {
                let promo = try await billingService.validatePromoCode(code)
                await MainActor.run {
                    validatedPromo = promo
                    isValidating = false
                }
            } catch let error as BillingError {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isValidating = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to validate code"
                    showError = true
                    isValidating = false
                }
            }
        }
    }

    private func clearPromoCode() {
        code = ""
        validatedPromo = nil
        showError = false
        errorMessage = ""
        billingService.clearValidatedPromoCode()
    }
}

// TODO: Re-enable preview once BusinessModels.swift is added to project
/*
#Preview("Valid Promo Code") {
    PromoCodeFieldPreviewWrapper()
}

private struct PromoCodeFieldPreviewWrapper: View {
    @State var code = "SAVE50"
    @State var validatedPromo: PromoCode? = PromoCode(
        id: UUID(),
        code: "SAVE50",
        discountType: .percent,
        discountValue: 50,
        trialExtensionDays: nil,
        applicablePlans: nil,
        minBillingPeriod: nil,
        firstTimeOnly: false,
        maxUses: nil,
        usesCount: 0,
        maxUsesPerUser: nil,
        validFrom: Date(),
        validUntil: nil,
        isActive: true,
        campaignName: "Summer Sale"
    )
    @State var isValidating = false
    
    var body: some View {
        PromoCodeField(
            billingService: BillingService(authService: SupabaseAuthService()),
            code: $code,
            validatedPromo: $validatedPromo,
            isValidating: $isValidating
        )
    }
}
*/
