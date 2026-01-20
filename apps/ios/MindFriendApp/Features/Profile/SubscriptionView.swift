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

    private var billingService: BillingService {
        container.billingService
    }

    private var selectedProduct: Product? {
        billingService.product(for: selectedPlanType, billingPeriod: selectedBillingPeriod)
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

                        // Billing Period
                        billingPeriodSection

                        // Price Summary
                        priceSummarySection

                        // Subscribe Button
                        subscribeButton

                        // Restore
                        restoreButton
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
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.yellow)

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
                        onSelect: { selectedPlanType = planType }
                    )
                }
            }
        }
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

                    if let product = selectedProduct {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(product.displayPrice)
                                .font(.title2)
                                .fontWeight(.bold)

                            if selectedBillingPeriod == .yearly {
                                Text(monthlyEquivalent(for: product))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if selectedBillingPeriod == .yearly {
                    HStack {
                        Image(systemName: "tag.fill")
                            .foregroundStyle(.green)
                        Text("Save 20% with annual billing")
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

    private var subscribeButton: some View {
        Button {
            purchase()
        } label: {
            HStack {
                if isPurchasing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Subscribe Now")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(selectedProduct != nil ? Color.accentColor : Color.secondary)
            .foregroundStyle(.white)
            .cornerRadius(12)
        }
        .disabled(selectedProduct == nil || isPurchasing)
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
        guard let product = selectedProduct else { return }

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
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: planType.iconName)
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(planType.displayName)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if planType == .family {
                            Text("Best Value")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .foregroundStyle(.white)
                                .cornerRadius(4)
                        }
                    }

                    Text(planType.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
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
            VStack(spacing: 8) {
                Text(period.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)

                // Always render text to maintain consistent height
                Text(showSavings ? "Save 20%" : " ")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(showSavings ? .green : .clear)
            }
            .frame(maxWidth: .infinity)
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
        .accessibilityLabel("\(period.displayName) billing\(showSavings ? ", Save 20%" : "")")
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
                let response = try await container.billingService.acceptFamilyInvitation(code: inviteCode)
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
        case .family: return "For up to 6 people"
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
