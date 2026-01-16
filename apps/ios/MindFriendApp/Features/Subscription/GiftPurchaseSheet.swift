import SwiftUI

// MARK: - Spec 15: Gift Purchase Component
// Requires: DependencyContainer, BillingService, SubscriptionPlan (from BusinessModels)
// Types are resolved from module scope at compile time

/// Modal sheet for purchasing a subscription as a gift
struct GiftPurchaseSheet: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss

    @State private var selectedPlan: SubscriptionPlan?
    @State private var recipientEmail = ""
    @State private var recipientName = ""
    @State private var personalMessage = ""
    @State private var deliveryDate = Date().addingTimeInterval(86400) // Tomorrow
    @State private var isPurchasing = false
    @State private var error: Error?
    @State private var showError = false
    @State private var success = false

    private var billingService: BillingService {
        container.billingService
    }

    private var isFormValid: Bool {
        selectedPlan != nil
            && !recipientEmail.trimmingCharacters(in: .whitespaces).isEmpty
            && recipientEmail.contains("@")
            && deliveryDate > Date()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.pink)

                        Text("Give MindFriend Premium")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("Send a subscription to someone special")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)

                    Form {
                        // Plan Selection
                        Section("Select Plan") {
                            if billingService.availablePlans.isEmpty {
                                ProgressView()
                                    .frame(maxWidth: .infinity, alignment: .center)
                            } else {
                                Picker("Plan", selection: $selectedPlan) {
                                    ForEach(billingService.availablePlans, id: \.id) { plan in
                                        Text("\(plan.name) — \(plan.displayPrice)")
                                            .tag(Optional(plan))
                                    }
                                }
                            }
                        }

                        // Recipient Information
                        Section("Recipient") {
                            TextField("Email address", text: $recipientEmail)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .autocorrectionDisabled()
                                .accessibilityLabel("Recipient email field")

                            TextField("Name (optional)", text: $recipientName)
                                .textInputAutocapitalization(.words)
                                .accessibilityLabel("Recipient name field")
                        }

                        // Delivery Date
                        Section("Delivery") {
                            DatePicker(
                                "Send on",
                                selection: $deliveryDate,
                                in: Date()...,
                                displayedComponents: [.date]
                            )
                            .accessibilityLabel("Delivery date picker")
                        }

                        // Personal Message
                        Section("Personal Message (optional)") {
                            TextEditor(text: $personalMessage)
                                .frame(minHeight: 80)
                                .font(.body)
                                .accessibilityLabel("Personal message field")

                            HStack {
                                Spacer()
                                Text("\(personalMessage.count)/500")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onReceive(personalMessage.publisher.collect()) { _ in
                            if personalMessage.count > 500 {
                                personalMessage = String(personalMessage.prefix(500))
                            }
                        }
                    }

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

                    // Success
                    if success {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Gift Sent!")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)

                                Text("Your gift will be delivered on the scheduled date")
                                    .font(.caption)
                            }

                            Spacer()
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    }

                    // Purchase Button
                    Button {
                        purchaseGift()
                    } label: {
                        HStack(spacing: 8) {
                            if isPurchasing {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "gift.fill")
                                Text("Send Gift")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isFormValid && !isPurchasing ? Color.accentColor : Color.secondary)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                    }
                    .disabled(!isFormValid || isPurchasing || success)
                    .accessibilityLabel("Send gift subscription button")

                    Spacer(minLength: 20)
                }
                .padding()
            }
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
                if billingService.availablePlans.isEmpty {
                    do {
                        try await billingService.loadAvailablePlans()
                        // Auto-select first plan
                        selectedPlan = billingService.availablePlans.first
                    } catch {
                        self.error = error
                        showError = true
                    }
                } else {
                    selectedPlan = billingService.availablePlans.first
                }
            }
        }
    }

    private func purchaseGift() {
        guard let plan = selectedPlan else { return }

        isPurchasing = true
        showError = false

        Task {
            do {
                let recipient = GiftRecipient(
                    email: recipientEmail.trimmingCharacters(in: .whitespaces),
                    name: recipientName.isEmpty ? nil : recipientName,
                    message: personalMessage.isEmpty ? nil : personalMessage,
                    deliveryDate: deliveryDate,
                    paymentMethodId: "" // Will be handled by Edge Function
                )

                let _ = try await billingService.purchaseGift(plan: plan, recipient: recipient)

                await MainActor.run {
                    success = true
                    isPurchasing = false

                    // Auto-dismiss after 2 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        dismiss()
                    }
                }
            } catch let error as BillingError {
                await MainActor.run {
                    self.error = error
                    showError = true
                    isPurchasing = false
                }
            } catch {
                await MainActor.run {
                    self.error = error
                    showError = true
                    isPurchasing = false
                }
            }
        }
    }
}

#Preview {
    GiftPurchaseSheet()
        .environmentObject(DependencyContainer())
}
