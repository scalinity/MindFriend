import SwiftUI
import StoreKit

struct SubscriptionView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss

    @State private var selectedPlanType: PlanType = .individual
    @State private var selectedBillingPeriod: BillingPeriod = .monthly
    @State private var isPurchasing = false
    @State private var error: Error?
    @State private var showError = false
    @State private var showFamilyManagement = false
    @State private var showInviteCode = false
    @State private var showEnterpriseInquiry = false
    @State private var showGiftSheet = false

    private var billingService: BillingService {
        container.billingService
    }

    private var selectedProduct: Product? {
        billingService.product(for: selectedPlanType, billingPeriod: selectedBillingPeriod)
    }

    /// Fallback plan when StoreKit products aren't available
    private var selectedFallbackPlan: SubscriptionPlan? {
        selectedBillingPeriod == .monthly
            ? SubscriptionPlan.monthlyPlan(for: selectedPlanType)
            : SubscriptionPlan.annualPlan(for: selectedPlanType)
    }

    /// Display price - from StoreKit or fallback
    private var selectedDisplayPrice: String? {
        if let product = selectedProduct {
            return product.displayPrice
        }
        return selectedFallbackPlan?.displayPrice
    }

    private var hasActiveSubscription: Bool {
        billingService.subscription?.status == .active
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection

                    // Active Subscription Info (if any)
                    if hasActiveSubscription {
                        activeSubscriptionSection
                    } else {
                        // Plan Selection
                        planSelectionSection

                        // Billing Period (hidden for enterprise)
                        if selectedPlanType != .enterprise && selectedPlanType != .gift {
                            billingPeriodSection
                        }

                        // Price Summary (hidden for enterprise and gift)
                        if selectedPlanType != .enterprise && selectedPlanType != .gift {
                            priceSummarySection
                        }

                        // Subscribe Button
                        subscribeButton

                        // Restore (hidden for enterprise and gift)
                        if selectedPlanType != .enterprise && selectedPlanType != .gift {
                            restoreButton
                        }
                    }

                    // Family Section (if applicable)
                    if hasActiveSubscription && billingService.subscription?.planType.isFamilyPlan == true {
                        familySection
                    }

                    // Features List
                    featuresSection

                    // Terms
                    termsSection
                }
                .padding()
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
            .task {
                await billingService.loadProducts()
                await loadSubscription()
            }
            .alert("Error", isPresented: $showError, presenting: error) { _ in
                Button("OK", role: .cancel) {}
            } message: { error in
                Text(error.localizedDescription)
            }
            .sheet(isPresented: $showFamilyManagement) {
                FamilyManagementView()
            }
            .sheet(isPresented: $showInviteCode) {
                EnterInviteCodeSheet()
            }
            .sheet(isPresented: $showEnterpriseInquiry) {
                EnterpriseInquirySheet()
            }
            .sheet(isPresented: $showGiftSheet) {
                GiftPurchaseSheet()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "crown.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.0))

            Text("MindFriend Premium")
                .font(.title)
                .fontWeight(.bold)

            if hasActiveSubscription {
                Label("Active", systemImage: "checkmark.seal.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: - Active Subscription

    private var activeSubscriptionSection: some View {
        VStack(spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    if let subscription = billingService.subscription {
                        HStack {
                            Text("Plan")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(subscription.planType.displayName)
                                .fontWeight(.medium)
                        }

                        HStack {
                            Text("Billing")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(subscription.billingPeriod.displayName)
                                .fontWeight(.medium)
                        }

                        if let expiresAt = subscription.expiresAt {
                            HStack {
                                Text("Renews")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(expiresAt, style: .date)
                                    .fontWeight(.medium)
                            }
                        }

                        if subscription.planType.isFamilyPlan {
                            Divider()
                            HStack {
                                Text("Seats Used")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(subscription.seatsUsed)/\(subscription.seatsTotal)")
                                    .fontWeight(.medium)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            } label: {
                Label("Your Subscription", systemImage: "creditcard.fill")
            }

            Button {
                if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Manage in App Store")
                    .font(.subheadline)
            }
        }
    }

    // MARK: - Plan Selection

    private var planSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose Your Plan")
                .font(.headline)

            VStack(spacing: 10) {
                ForEach(PlanType.allCases, id: \.self) { planType in
                    PlanTypeCard(
                        planType: planType,
                        isSelected: selectedPlanType == planType,
                        price: priceForPlanType(planType),
                        billingPeriod: selectedBillingPeriod,
                        onSelect: { selectedPlanType = planType }
                    )
                }
            }
        }
    }

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

    // MARK: - Billing Period

    private var billingPeriodSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Billing Period")
                .font(.headline)

            HStack(spacing: 12) {
                ForEach(BillingPeriod.allCases, id: \.self) { period in
                    BillingPeriodCard(
                        period: period,
                        isSelected: selectedBillingPeriod == period,
                        showSavings: period == .yearly,
                        onSelect: { selectedBillingPeriod = period }
                    )
                }
            }
        }
    }

    // MARK: - Price Summary

    private var priceSummarySection: some View {
        GroupBox {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedPlanType.displayName)
                            .font(.headline)
                        Text(selectedBillingPeriod.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let price = selectedDisplayPrice {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(price)
                                .font(.title2)
                                .fontWeight(.bold)

                            if selectedBillingPeriod == .yearly {
                                if let product = selectedProduct {
                                    Text(monthlyEquivalent(for: product))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else if let plan = selectedFallbackPlan {
                                    Text(plan.pricePerMonth ?? "")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if selectedBillingPeriod == .yearly {
                    HStack {
                        Image(systemName: "tag.fill")
                            .foregroundStyle(.green)
                        Text("Save 50% with annual billing")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                        Spacer()
                    }
                }

                if selectedPlanType.isFamilyPlan {
                    HStack {
                        Image(systemName: "person.2.fill")
                            .foregroundStyle(.blue)
                        Text("Includes \(selectedPlanType.maxSeats) members")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
        } label: {
            Label("Summary", systemImage: "receipt")
        }
    }

    // MARK: - Subscribe Button

    /// Whether we can attempt a purchase (have StoreKit product or fallback)
    private var canPurchase: Bool {
        selectedProduct != nil || selectedFallbackPlan != nil
    }

    private var subscribeButton: some View {
        Button {
            if selectedPlanType == .enterprise {
                showEnterpriseInquiry = true
            } else if selectedPlanType == .gift {
                showGiftSheet = true
            } else {
                purchase()
            }
        } label: {
            HStack {
                if isPurchasing && selectedPlanType != .enterprise && selectedPlanType != .gift {
                    ProgressView()
                        .tint(.white)
                } else if selectedPlanType == .enterprise {
                    Text("Contact Sales")
                        .fontWeight(.semibold)
                } else if selectedPlanType == .gift {
                    Text("Give as Gift")
                        .fontWeight(.semibold)
                } else {
                    Text("Subscribe Now")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isSpecialPlanType || canPurchase ? Color.accentColor : Color.secondary)
            .foregroundStyle(.white)
            .cornerRadius(12)
        }
        .disabled(!isSpecialPlanType && (!canPurchase || isPurchasing))
    }

    private var isSpecialPlanType: Bool {
        selectedPlanType == .enterprise || selectedPlanType == .gift
    }

    // MARK: - Restore Button

    private var restoreButton: some View {
        VStack(spacing: 8) {
            Button("Restore Purchases") {
                restorePurchases()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Button("Have an invite code?") {
                showInviteCode = true
            }
            .font(.subheadline)
            .foregroundStyle(Color.accentColor)
        }
    }

    // MARK: - Family Section

    private var familySection: some View {
        GroupBox {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Family Members")
                            .font(.headline)
                        if let sub = billingService.subscription {
                            Text("\(sub.seatsUsed) of \(sub.seatsTotal) seats used")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        showFamilyManagement = true
                    } label: {
                        Text("Manage")
                            .font(.subheadline)
                    }
                }

                // Quick member list
                if !billingService.familyMembers.isEmpty {
                    Divider()
                    ForEach(billingService.familyMembers.prefix(3)) { member in
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .foregroundStyle(.secondary)
                            Text(member.displayName ?? member.invitedEmail ?? "Member")
                                .font(.subheadline)
                            Spacer()
                            if member.status == .active {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                            } else {
                                Text("Pending")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }

                    if billingService.familyMembers.count > 3 {
                        Text("+\(billingService.familyMembers.count - 3) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } label: {
            Label("Family Plan", systemImage: "person.3.fill")
        }
    }

    // MARK: - Features

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Premium Features")
                .font(.headline)

            VStack(spacing: 10) {
                SubscriptionFeatureRow(icon: "infinity", title: "Unlimited AI Chat", included: true)
                SubscriptionFeatureRow(icon: "sparkles", title: "Priority Responses", included: true)
                SubscriptionFeatureRow(icon: "chart.line.uptrend.xyaxis", title: "Advanced Insights", included: true)
                SubscriptionFeatureRow(icon: "bell.badge.fill", title: "Smart Notifications", included: true)
                SubscriptionFeatureRow(icon: "star.fill", title: "Premium Exercises", included: true)
                if selectedPlanType.isFamilyPlan {
                    SubscriptionFeatureRow(icon: "person.3.fill", title: "Shared Family Circle", included: true)
                }
            }
        }
    }

    // MARK: - Terms

    private var termsSection: some View {
        Text("Subscription automatically renews unless cancelled at least 24 hours before the end of the current period. Manage subscriptions in Settings.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    // MARK: - Actions

    private func loadSubscription() async {
        do {
            try await billingService.refreshEntitlements()
        } catch {
            Log.billing.error("Failed to refresh entitlements", error: error)
        }
    }

    private func purchase() {
        guard let product = selectedProduct else {
            // StoreKit products not available - show error
            self.error = BillingError.productNotFound
            showError = true
            return
        }

        isPurchasing = true
        Task {
            do {
                try await billingService.purchase(product)
                await MainActor.run {
                    appState.updateEntitlements(.premium)
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
                try await billingService.restorePurchases()
                if billingService.entitlements.tier == .premium {
                    await MainActor.run {
                        appState.updateEntitlements(.premium)
                    }
                }
            } catch {
                self.error = error
                showError = true
            }
            isPurchasing = false
        }
    }

    private func monthlyEquivalent(for product: Product) -> String {
        let monthlyPrice = product.price / 12
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = product.priceFormatStyle.locale
        return "\(formatter.string(from: monthlyPrice as NSDecimalNumber) ?? "")/mo"
    }
}

// MARK: - Plan Type Card

struct PlanTypeCard: View {
    let planType: PlanType
    let isSelected: Bool
    var price: String?
    var billingPeriod: BillingPeriod = .monthly
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: planType.iconName)
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(planType.displayName)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if planType == .family {
                            Text("Best")
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .foregroundStyle(.white)
                                .cornerRadius(3)
                        }
                    }

                    Text(planType.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                // Price display (not for enterprise/gift)
                if let price = price {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(price)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(billingPeriod == .monthly ? "/month" : "/year")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .fixedSize()
                }

                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .font(.title3)
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
        // P3-R7: Accessibility labels
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(planType.displayName) plan, \(planType.subtitle)\(planType == .family ? ", Best Value" : "")")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Double tap to select this plan")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Billing Period Card

struct BillingPeriodCard: View {
    let period: BillingPeriod
    let isSelected: Bool
    let showSavings: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 4) {
                Text(period.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)

                if showSavings {
                    Text("Save 50%")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 16)
            .padding(.horizontal)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color(.secondarySystemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        // P3-R7: Accessibility labels
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(period.displayName) billing\(showSavings ? ", Save 50%" : "")")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Double tap to select this billing period")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Feature Row

private struct SubscriptionFeatureRow: View {
    let icon: String
    let title: String
    let included: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(included ? Color.accentColor : .secondary)
                .frame(width: 24)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(included ? .primary : .secondary)

            Spacer()

            Image(systemName: included ? "checkmark" : "xmark")
                .font(.caption)
                .foregroundStyle(included ? .green : .secondary)
        }
        // P3-R7: Accessibility labels
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(included ? "included" : "not included")")
    }
}

// MARK: - Enter Invite Code Sheet

struct EnterInviteCodeSheet: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss

    @State private var inviteCode = ""
    @State private var isLoading = false
    @State private var error: String?
    @State private var success = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "ticket.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(Color.accentColor)

                Text("Enter Invite Code")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("If someone shared their family or couples plan with you, enter the invite code below.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                TextField("XXXXXXXX", text: $inviteCode)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3.monospaced())
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .frame(maxWidth: 200)
                    .onChange(of: inviteCode) { _, newValue in
                        inviteCode = String(newValue.uppercased().prefix(8))
                    }

                if let error = error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if success {
                    Label("Welcome to the family plan!", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                Button {
                    acceptInvite()
                } label: {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Join Plan")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(inviteCode.count == 8 ? Color.accentColor : Color.secondary)
                .foregroundStyle(.white)
                .cornerRadius(12)
                .disabled(inviteCode.count != 8 || isLoading || success)
                .padding(.horizontal)

                Spacer()
            }
            .padding()
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
        }
    }

    private func acceptInvite() {
        isLoading = true
        error = nil

        Task {
            do {
                _ = try await container.billingService.acceptFamilyInvitation(code: inviteCode)
                await MainActor.run {
                    success = true
                    appState.updateEntitlements(.premium)
                }

                // Dismiss after short delay
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                }
            }
            isLoading = false
        }
    }
}

// MARK: - Extensions

extension PlanType {
    var iconName: String {
        switch self {
        case .individual: return "person.fill"
        case .couples: return "heart.fill"
        case .family: return "person.3.fill"
        case .enterprise: return "building.2.fill"
        case .gift: return "gift.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .individual: return "For personal use"
        case .couples: return "For 2 people"
        case .family: return "Up to 6 people"
        case .enterprise: return "For organizations"
        case .gift: return "Gift a subscription"
        }
    }
}

#Preview {
    SubscriptionView()
        .environmentObject(AppState())
        .environmentObject(DependencyContainer())
}
