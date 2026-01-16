import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss

    @State private var selectedProduct: Product?
    @State private var isPurchasing = false
    @State private var error: Error?
    @State private var showError = false

    // Spec 15: Business Model features
    @State private var promoCode = ""
    @State private var validatedPromo: PromoCode?
    @State private var isValidatingPromo = false
    @State private var showGiftSheet = false
    @State private var showHSAInfo = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 16) {
                        Image(systemName: "star.circle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(.yellow)

                        Text("MindFriend Premium")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text("Unlock unlimited conversations and premium features")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top)

                    // Benefits
                    VStack(alignment: .leading, spacing: 16) {
                        BenefitRow(icon: "infinity", title: "Unlimited AI Chat", description: "No daily message limits")
                        BenefitRow(icon: "sparkles", title: "Priority Responses", description: "Faster AI response times")
                        BenefitRow(icon: "chart.line.uptrend.xyaxis", title: "Advanced Analytics", description: "Detailed mood insights")
                        BenefitRow(icon: "bell.badge.fill", title: "Smart Reminders", description: "Personalized nudges")
                    }
                    .padding(.horizontal)

                    // Products
                    VStack(spacing: 12) {
                        ForEach(container.billingService.products, id: \.id) { product in
                            ProductCard(
                                product: product,
                                isSelected: selectedProduct?.id == product.id,
                                onSelect: { selectedProduct = product }
                            )
                        }
                    }
                    .padding(.horizontal)

                    // Spec 15: HSA/FSA Badge (link to info)
                    Button {
                        showHSAInfo = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "heart.text.square.fill")
                                .foregroundStyle(.blue)

                            Text("HSA/FSA Eligible")
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color.blue.opacity(0.05))
                        .cornerRadius(8)
                        .foregroundStyle(.primary)
                    }
                    .padding(.horizontal)
                    .accessibilityLabel("HSA/FSA eligibility information button")

                    // Spec 15: Promo Code Field
                    PromoCodeField(
                        billingService: container.billingService,
                        code: $promoCode,
                        validatedPromo: $validatedPromo,
                        isValidating: $isValidatingPromo
                    )
                    .padding(.horizontal)

                    // Subscribe button
                    Button {
                        purchase()
                    } label: {
                        if isPurchasing {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Subscribe Now")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(selectedProduct != nil ? Color.accentColor : Color.secondary)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                    .disabled(selectedProduct == nil || isPurchasing)
                    .padding(.horizontal)
                    .accessibilityLabel("Subscribe now button")

                    // Spec 15: Gift Purchase Button
                    Button {
                        showGiftSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "gift.fill")
                            Text("Give as Gift")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.pink.opacity(0.1))
                        .foregroundStyle(Color.pink)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .accessibilityLabel("Give subscription as gift button")

                    // Restore
                    Button("Restore Purchases") {
                        restorePurchases()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Restore purchases button")

                    // Terms
                    Text("Subscription automatically renews unless cancelled at least 24 hours before the end of the current period. Manage subscriptions in Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Spacer(minLength: 32)
                }
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
                }
            }
            .task {
                await container.billingService.loadProducts()
                selectedProduct = container.billingService.products.first
            }
            .alert("Purchase Error", isPresented: $showError, presenting: error) { _ in
                Button("OK", role: .cancel) {}
            } message: { error in
                Text(error.localizedDescription)
            }
            // Spec 15: Gift Purchase Sheet
            .sheet(isPresented: $showGiftSheet) {
                GiftPurchaseSheet()
            }
            // Spec 15: HSA/FSA Info Sheet
            .sheet(isPresented: $showHSAInfo) {
                HSAFSAInfoView()
            }
        }
    }

    private func purchase() {
        guard let product = selectedProduct else { return }

        isPurchasing = true
        Task {
            do {
                // Spec 15: Pass validated promo code if available
                try await container.billingService.purchase(
                    product,
                    promoCode: validatedPromo?.code
                )
                await MainActor.run {
                    appState.updateEntitlements(.premium)
                    dismiss()
                }
            } catch let error as BillingError {
                if error != .cancelled {
                    self.error = error
                    showError = true
                }
            } catch {
                self.error = error
                showError = true
            }
            isPurchasing = false
        }
    }

    private func restorePurchases() {
        isPurchasing = true
        Task {
            do {
                try await container.billingService.restorePurchases()
                if container.billingService.entitlements.tier == .premium {
                    await MainActor.run {
                        appState.updateEntitlements(.premium)
                        dismiss()
                    }
                }
            } catch {
                self.error = error
                showError = true
            }
            isPurchasing = false
        }
    }
}

struct BenefitRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ProductCard: View {
    let product: Product
    let isSelected: Bool
    let onSelect: () -> Void

    var isBestValue: Bool {
        product.id.contains("yearly")
    }

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(product.displayName)
                            .font(.headline)

                        if isBestValue {
                            Text("Best Value")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .foregroundStyle(.white)
                                .cornerRadius(4)
                        }
                    }

                    Text(product.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text(product.displayPrice)
                        .font(.title3)
                        .fontWeight(.bold)

                    if isBestValue {
                        Text("per year")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("per month")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color(.secondarySystemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PaywallView()
        .environmentObject(AppState())
        .environmentObject(DependencyContainer())
}
