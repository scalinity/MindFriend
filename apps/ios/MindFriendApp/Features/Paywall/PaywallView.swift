import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedPlanType: PlanType = .individual
    @State private var selectedBillingPeriod: BillingPeriod = .monthly
    @State private var isPurchasing = false
    @State private var error: Error?
    @State private var showError = false
    @State private var showGiftSheet = false
    @State private var showEnterpriseInquiry = false
    
    private var billingService: BillingService {
        container.billingService
    }

    var selectedPlan: SubscriptionPlan {
        switch selectedBillingPeriod {
        case .monthly:
            return SubscriptionPlan.monthlyPlan(for: selectedPlanType) ?? .premiumMonthly
        case .yearly:
            return SubscriptionPlan.annualPlan(for: selectedPlanType) ?? .premiumAnnual
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    headerSection
                    planTypeSection

                    if selectedPlanType != .enterprise && selectedPlanType != .gift {
                        billingPeriodSection
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    benefitsSection
                    subscribeButton

                    if selectedPlanType != .enterprise && selectedPlanType != .gift {
                        restoreButton
                            .transition(.opacity)
                    }

                    termsSection
                    Spacer(minLength: 32)
                }
                .padding()
                .animation(.easeInOut(duration: 0.25), value: selectedPlanType)
            }
            .navigationTitle("Premium")
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
            .alert("Purchase Error", isPresented: $showError, presenting: error) { _ in
                Button("OK", role: .cancel) {}
            } message: { error in
                Text(error.localizedDescription)
            }
            .sheet(isPresented: $showGiftSheet) {
                GiftPurchaseSheet()
            }
            .sheet(isPresented: $showEnterpriseInquiry) {
                EnterpriseInquirySheet()
            }
            .task {
                await billingService.loadProducts()
            }
        }
    }
    
    // MARK: - View Components
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.yellow)
            
            Text("MindFriend Premium")
                .font(.largeTitle)
                .fontWeight(.bold)
        }
    }
    
    private var planTypeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose Your Plan")
                .font(.title3)
                .fontWeight(.semibold)
            
            // Individual
            PaywallPlanCard(
                planType: .individual,
                isSelected: selectedPlanType == .individual,
                price: priceForPlanType(.individual),
                billingPeriod: selectedBillingPeriod
            ) {
                selectedPlanType = .individual
            }
            
            // Couples
            PaywallPlanCard(
                planType: .couples,
                isSelected: selectedPlanType == .couples,
                price: priceForPlanType(.couples),
                billingPeriod: selectedBillingPeriod
            ) {
                selectedPlanType = .couples
            }
            
            // Family (Best Value)
            PaywallPlanCard(
                planType: .family,
                isSelected: selectedPlanType == .family,
                price: priceForPlanType(.family),
                billingPeriod: selectedBillingPeriod,
                showBestValue: true
            ) {
                selectedPlanType = .family
            }
            
            // Enterprise
            PaywallPlanCard(
                planType: .enterprise,
                isSelected: selectedPlanType == .enterprise,
                price: priceForPlanType(.enterprise),
                billingPeriod: selectedBillingPeriod
            ) {
                selectedPlanType = .enterprise
            }
            
            // Gift
            Button {
                showGiftSheet = true
            } label: {
                HStack(spacing: 16) {
                    Image(systemName: "gift.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(width: 40)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Gift")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("Gift a subscription")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
            }
        }
    }
    
    private var billingPeriodSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Billing Period")
                .font(.title3)
                .fontWeight(.semibold)
            
            HStack(spacing: 12) {
                // Monthly
                BillingPeriodButton(
                    period: .monthly,
                    isSelected: selectedBillingPeriod == .monthly
                ) {
                    selectedBillingPeriod = .monthly
                }
                
                // Annual
                BillingPeriodButton(
                    period: .yearly,
                    isSelected: selectedBillingPeriod == .yearly,
                    savings: "Save 50%"
                ) {
                    selectedBillingPeriod = .yearly
                }
            }
        }
    }
    
    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            BenefitRow(icon: "infinity", title: "Unlimited AI Chat", description: "No daily message limits")
            BenefitRow(icon: "sparkles", title: "Priority Responses", description: "Faster AI response times")
            BenefitRow(icon: "chart.line.uptrend.xyaxis", title: "Advanced Analytics", description: "Detailed mood insights")
            BenefitRow(icon: "bell.badge.fill", title: "Smart Reminders", description: "Personalized nudges")
        }
    }
    
    private var subscribeButton: some View {
        Button {
            if selectedPlanType == .enterprise {
                showEnterpriseInquiry = true
            } else {
                purchase()
            }
        } label: {
            if isPurchasing {
                ProgressView()
                    .tint(.white)
            } else if selectedPlanType == .enterprise {
                Text("Contact Sales")
                    .fontWeight(.semibold)
            } else {
                Text("Subscribe to \(selectedPlan.displayPrice)/\(selectedBillingPeriod == .monthly ? "month" : "year")")
                    .fontWeight(.semibold)
            }
        }
        .font(.headline)
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.accentColor)
        .foregroundStyle(.white)
        .cornerRadius(12)
        .disabled(isPurchasing && selectedPlanType != .enterprise)
    }
    
    private var restoreButton: some View {
        Button("Restore Purchases") {
            restorePurchases()
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    
    private var termsSection: some View {
        VStack(spacing: 12) {
            Text("Subscription automatically renews unless cancelled at least 24 hours before the end of the current period. Manage subscriptions in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Link("Terms of Use (EULA)", destination: URL(string: "https://getmindfriend.app/terms")!)
                Text("•").foregroundStyle(.secondary)
                Link("Privacy Policy", destination: URL(string: "https://getmindfriend.app/privacy")!)
            }
            .font(.caption)
        }
    }
    
    // MARK: - Helpers

    private func priceForPlanType(_ planType: PlanType) -> String? {
        // Enterprise and Gift don't show prices
        if planType == .enterprise || planType == .gift {
            return nil
        }

        // Try StoreKit product first
        if let product = billingService.product(for: planType, billingPeriod: selectedBillingPeriod) {
            return product.displayPrice
        }

        // Fall back to static plan prices (for simulator/development)
        let plan: SubscriptionPlan? = selectedBillingPeriod == .monthly
            ? SubscriptionPlan.monthlyPlan(for: planType)
            : SubscriptionPlan.annualPlan(for: planType)

        return plan?.displayPrice
    }
    
    private func purchase() {
        isPurchasing = true
        Task {
            do {
                // In real implementation, load actual StoreKit product
                // For now, using mock plan
                guard let storeProduct = await loadStoreKitProduct(for: selectedPlan) else {
                    throw BillingError.productNotFound
                }
                
                try await container.billingService.purchase(storeProduct, promoCode: nil)
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
    
    private func loadStoreKitProduct(for plan: SubscriptionPlan) async -> Product? {
        guard let productId = plan.appStoreProductId else { return nil }
        // Load actual StoreKit product
        // This is a placeholder - in real implementation, use StoreKit 2
        return container.billingService.products.first { $0.id == productId }
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

// MARK: - Supporting Views

struct PaywallPlanCard: View {
    let planType: PlanType
    let isSelected: Bool
    var price: String?
    var billingPeriod: BillingPeriod = .monthly
    var showBestValue: Bool = false
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: iconForPlanType(planType))
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 36)

                // Plan info
                VStack(alignment: .leading, spacing: 2) {
                    Text(planType.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(planType.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Price display (not for enterprise/gift)
                if let price = price {
                    VStack(alignment: .trailing, spacing: 2) {
                        if showBestValue {
                            Text("Best Value")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .foregroundStyle(.white)
                                .cornerRadius(4)
                        }
                        Text(price)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.primary)
                        Text(billingPeriod == .monthly ? "/month" : "/year")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .font(.title3)
            }
            .padding()
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.1)
                    : Color(.secondarySystemBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
    
    private func iconForPlanType(_ type: PlanType) -> String {
        switch type {
        case .individual: return "person.fill"
        case .couples: return "heart.fill"
        case .family: return "figure.2.and.child.holdinghands"
        case .enterprise: return "building.2.fill"
        case .gift: return "gift.fill"
        }
    }
}

struct BillingPeriodButton: View {
    let period: BillingPeriod
    let isSelected: Bool
    var savings: String?
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 4) {
                Text(period.displayName)
                    .font(.headline)
                    .foregroundStyle(isSelected ? .primary : .secondary)

                if let savings = savings {
                    Text(savings)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 16)
            .padding(.horizontal)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.1)
                    : Color(.secondarySystemBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
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

#Preview {
    PaywallView()
        .environmentObject(AppState())
        .environmentObject(DependencyContainer())
}
