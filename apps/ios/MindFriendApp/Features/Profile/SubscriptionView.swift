import StoreKit
import SwiftUI

struct SubscriptionView: View {
    @EnvironmentObject var container: DependencyContainer

    var body: some View {
        SubscriptionContent(billingService: container.billingService)
    }
}

struct SubscriptionContent: View {
    @ObservedObject var billingService: BillingService
    @EnvironmentObject var appState: AppState
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
    @State private var purchaseMessage: String?

    private var selectedProduct: Product? {
        billingService.product(for: selectedPlanType, billingPeriod: selectedBillingPeriod)
    }

    private var selectedDisplayPrice: String? {
        selectedProduct?.displayPrice
    }

    private var hasActiveSubscription: Bool {
        billingService.subscription?.status == .active
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SupportTheme.Spacing.l) {
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

                        if let purchaseMessage {
                            Text(purchaseMessage).font(.subheadline)
                        }
                        if !isSpecialPlanType {
                            if billingService.isLoadingProducts {
                                ProgressView("Loading App Store plans…")
                            } else if selectedProduct == nil {
                                Text(
                                    billingService.productLoadError
                                        ?? "This plan is currently unavailable from the App Store."
                                )
                                .font(.subheadline)
                                .accessibilityIdentifier("subscription.catalogError")
                                Button("Reload Plans") {
                                    Task { await billingService.refreshProducts() }
                                }
                                .accessibilityIdentifier("subscription.reload")
                            }
                        }

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
            .supportSheet()
            .navigationTitle("Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                    .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                    .accessibilityLabel("Close")
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
        VStack(spacing: SupportTheme.Spacing.s) {
            CelebrationEmblem(.symbol("sparkles"), tint: SupportTheme.accent, diameter: 80)

            Text("MindFriend Premium")
                .font(.title)
                .accessibilityAddTraits(.isHeader)
                .fontWeight(.bold)

            if hasActiveSubscription {
                Label("Active", systemImage: "checkmark.seal.fill")
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.accent)
            }
        }
    }

    // MARK: - Active Subscription

    private var activeSubscriptionSection: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {

                Label("Your Subscription", systemImage: "creditcard.fill")

                VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                    if let subscription = billingService.subscription {
                        HStack {
                            Text("Plan")
                                .foregroundStyle(SupportTheme.textSecondary)
                            Spacer()
                            Text(subscription.planType.displayName)
                                .fontWeight(.medium)
                        }

                        HStack {
                            Text("Billing")
                                .foregroundStyle(SupportTheme.textSecondary)
                            Spacer()
                            Text(subscription.billingPeriod.displayName)
                                .fontWeight(.medium)
                        }

                        if let expiresAt = subscription.expiresAt {
                            HStack {
                                Text("Renews")
                                    .foregroundStyle(SupportTheme.textSecondary)
                                Spacer()
                                Text(expiresAt, style: .date)
                                    .fontWeight(.medium)
                            }
                        }

                        if subscription.planType.isFamilyPlan {
                            Divider()
                            HStack {
                                Text("Seats Used")
                                    .foregroundStyle(SupportTheme.textSecondary)
                                Spacer()
                                Text("\(subscription.seatsUsed)/\(subscription.seatsTotal)")
                                    .fontWeight(.medium)
                            }
                        }
                    }
                }
                .padding(.vertical, SupportTheme.Spacing.xxs)

            }
            .supportCard()

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
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Choose Your Plan")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: SupportTheme.Spacing.s) {
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

        return billingService.product(for: planType, billingPeriod: selectedBillingPeriod)?.displayPrice
    }

    // MARK: - Billing Period

    private var billingPeriodSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Billing Period")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: SupportTheme.Spacing.s) {
                ForEach(BillingPeriod.allCases, id: \.self) { period in
                    BillingPeriodCard(
                        period: period,
                        isSelected: selectedBillingPeriod == period,
                        showSavings: period == .yearly
                            && billingService.product(for: selectedPlanType, billingPeriod: .yearly) != nil,
                        onSelect: { selectedBillingPeriod = period }
                    )
                }
            }
        }
    }

    // MARK: - Price Summary

    private var priceSummarySection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {

            Label("Summary", systemImage: "receipt")

            VStack(spacing: SupportTheme.Spacing.s) {
                HStack {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                        Text(selectedPlanType.displayName)
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Text(selectedBillingPeriod.displayName)
                            .font(.subheadline)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }

                    Spacer()

                    if let price = selectedDisplayPrice {
                        VStack(alignment: .trailing, spacing: SupportTheme.Spacing.xxs) {
                            Text(price)
                                .font(.title2)
                                .accessibilityAddTraits(.isHeader)
                                .fontWeight(.bold)

                            if selectedBillingPeriod == .yearly {
                                if let product = selectedProduct {
                                    Text(monthlyEquivalent(for: product))
                                        .font(.caption)
                                        .foregroundStyle(SupportTheme.textSecondary)
                                }
                            }
                        }
                    } else {
                        Text(billingService.isLoadingProducts ? "Loading…" : "Unavailable")
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                }

                if selectedBillingPeriod == .yearly && selectedProduct != nil {
                    HStack {
                        Image(systemName: "tag.fill")
                            .foregroundStyle(SupportTheme.accent)
                        Text("Save 50% with annual billing")
                            .font(.subheadline)
                            .foregroundStyle(SupportTheme.accent)
                        Spacer()
                    }
                }

                if selectedPlanType.isFamilyPlan {
                    HStack {
                        Image(systemName: "person.2.fill")
                            .foregroundStyle(SupportTheme.accent)
                        Text("Includes \(selectedPlanType.maxSeats) members")
                            .font(.subheadline)
                            .foregroundStyle(SupportTheme.textSecondary)
                        Spacer()
                    }
                }
            }

        }
        .supportCard()
    }

    // MARK: - Subscribe Button

    private var canPurchase: Bool {
        selectedProduct != nil
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
                        .tint(SupportTheme.onAccent)
                } else if selectedPlanType == .enterprise {
                    Text("Contact Sales")
                        .fontWeight(.semibold)
                } else if selectedPlanType == .gift {
                    Text("Give as Gift")
                        .fontWeight(.semibold)
                } else {
                    Text(
                        billingService.isLoadingProducts
                            ? "Loading Plans…" : canPurchase ? "Subscribe Now" : "Plan Unavailable"
                    )
                    .fontWeight(.semibold)
                }
            }
        }
        .buttonStyle(.supportPrimary)
        .disabled(
            !isSpecialPlanType
                && (!canPurchase || billingService.isLoadingProducts || isPurchasing || billingService.isPurchasing)
        )
        .accessibilityIdentifier("subscription.subscribe")
    }

    private var isSpecialPlanType: Bool {
        selectedPlanType == .enterprise || selectedPlanType == .gift
    }

    // MARK: - Restore Button

    private var restoreButton: some View {
        VStack(spacing: SupportTheme.Spacing.xs) {
            Button("Restore Purchases") {
                restorePurchases()
            }
            .buttonStyle(.supportSecondary)
            .disabled(isPurchasing || billingService.isPurchasing)

            Button("Have an invite code?") {
                showInviteCode = true
            }
            .font(.subheadline)
            .foregroundStyle(SupportTheme.accent)
        }
    }

    // MARK: - Family Section

    private var familySection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {

            Label("Family Plan", systemImage: "person.3.fill")

            VStack(spacing: SupportTheme.Spacing.s) {
                HStack {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                        Text("Family Members")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        if let sub = billingService.subscription {
                            Text("\(sub.seatsUsed) of \(sub.seatsTotal) seats used")
                                .font(.caption)
                                .foregroundStyle(SupportTheme.textSecondary)
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
                                .foregroundStyle(SupportTheme.textSecondary)
                            Text(member.displayName ?? member.invitedEmail ?? "Member")
                                .font(.subheadline)
                            Spacer()
                            if member.status == .active {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(SupportTheme.accent)
                                    .font(.caption)
                            } else {
                                Text("Pending")
                                    .font(.caption)
                                    .foregroundStyle(SupportTheme.accent)
                            }
                        }
                    }

                    if billingService.familyMembers.count > 3 {
                        Text("+\(billingService.familyMembers.count - 3) more")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                }
            }

        }
        .supportCard()
    }

    // MARK: - Features

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Premium Features")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: SupportTheme.Spacing.s) {
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
        VStack(spacing: SupportTheme.Spacing.s) {
            Text(
                "Subscription automatically renews unless cancelled at least 24 hours before the end of the current period. Manage subscriptions in Settings."
            )
            .font(.caption)
            .foregroundStyle(SupportTheme.textSecondary)
            .multilineTextAlignment(.center)

            HStack(spacing: SupportTheme.Spacing.m) {
                Link("Terms of Use (EULA)", destination: AppURLs.termsOfUse)
                Text("•").foregroundStyle(SupportTheme.textSecondary)
                Link("Privacy Policy", destination: AppURLs.privacyPolicy)
            }
            .font(.caption)
        }
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
        guard !isPurchasing, !billingService.isPurchasing, let product = selectedProduct else { return }

        isPurchasing = true
        purchaseMessage = nil
        Task {
            defer { isPurchasing = false }
            do {
                switch try await billingService.purchase(product) {
                case .completed:
                    appState.updateEntitlements(billingService.entitlements)
                case .pending:
                    purchaseMessage =
                        "Awaiting App Store approval. Your access will update after the purchase is approved."
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
        }
    }

    private func restorePurchases() {
        isPurchasing = true
        Task {
            do {
                try await billingService.restorePurchases()
                if billingService.entitlements.tier == .premium {
                    await MainActor.run {
                        appState.updateEntitlements(billingService.entitlements)
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
    @Environment(\.dynamicTypeSize) private var typeSize
    let planType: PlanType
    let isSelected: Bool
    var price: String?
    var billingPeriod: BillingPeriod = .monthly
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            (typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: SupportTheme.Spacing.s))
                : AnyLayout(HStackLayout(spacing: SupportTheme.Spacing.s))) {
                    Image(systemName: planType.iconName)
                        .font(.title2)
                        .foregroundStyle(isSelected ? SupportTheme.accent : SupportTheme.textSecondary)
                        .frame(width: 40)

                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                        HStack(spacing: SupportTheme.Spacing.xxs) {
                            Text(planType.displayName)
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                                .foregroundStyle(SupportTheme.textPrimary)

                            if planType == .family {
                                Text("Best")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, SupportTheme.Spacing.xxs)
                                    .padding(.vertical, SupportTheme.Spacing.xxs)
                                    .background(SupportTheme.field)
                                    .foregroundStyle(SupportTheme.accent)
                                    .cornerRadius(SupportTheme.controlRadius)
                            }
                        }

                        Text(planType.subtitle)
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: SupportTheme.Spacing.xxs)

                    // Price display (not for enterprise/gift)
                    if let price = price {
                        VStack(alignment: .trailing, spacing: SupportTheme.Spacing.xxs) {
                            Text(price)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(SupportTheme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(billingPeriod == .monthly ? "/month" : "/year")
                                .font(.caption)
                                .foregroundStyle(SupportTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    // Selection indicator
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? SupportTheme.accent : SupportTheme.textSecondary)
                        .font(.title3)
                        .accessibilityAddTraits(.isHeader)
                }
                .padding()
                .background(isSelected ? SupportTheme.elevated : SupportTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: SupportTheme.cardRadius)
                        .stroke(isSelected ? SupportTheme.accent : Color.clear, lineWidth: 2)
                )
                .cornerRadius(SupportTheme.controlRadius)
        }
        .buttonStyle(.plain)
        // P3-R7: Accessibility labels
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(planType.displayName) plan, \(planType.subtitle)\(planType == .family ? ", Best Value" : "")"
        )
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
            VStack(spacing: SupportTheme.Spacing.xxs) {
                Text(period.displayName)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .foregroundStyle(SupportTheme.textPrimary)

                if showSavings {
                    Text("Save 50%")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(SupportTheme.accent)
                }
            }
            .frame(maxWidth: .infinity, minHeight: SupportTheme.minimumTarget)
            .padding(.vertical, SupportTheme.Spacing.m)
            .padding(.horizontal)
            .background(isSelected ? SupportTheme.elevated : SupportTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: SupportTheme.cardRadius)
                    .stroke(isSelected ? SupportTheme.accent : Color.clear, lineWidth: 2)
            )
            .cornerRadius(SupportTheme.controlRadius)
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
        HStack(spacing: SupportTheme.Spacing.s) {
            Image(systemName: icon)
                .foregroundStyle(included ? SupportTheme.accent : SupportTheme.textSecondary)
                .frame(minWidth: 24)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(included ? SupportTheme.textPrimary : SupportTheme.textSecondary)

            Spacer()

            Image(systemName: included ? "checkmark" : "xmark")
                .font(.caption)
                .foregroundStyle(included ? SupportTheme.accent : SupportTheme.textSecondary)
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
            VStack(spacing: SupportTheme.Spacing.l) {
                Image(systemName: "ticket.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(SupportTheme.accent)

                Text("Enter Invite Code")
                    .font(.title2)
                    .accessibilityAddTraits(.isHeader)
                    .fontWeight(.semibold)

                Text("If someone shared their family or couples plan with you, enter the invite code below.")
                    .font(.body)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                TextField("XXXXXXXX", text: $inviteCode)
                    .supportField()
                    .font(.title3.monospaced())
                    .accessibilityAddTraits(.isHeader)
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
                        .foregroundStyle(SupportTheme.accent)
                }

                Button {
                    acceptInvite()
                } label: {
                    if isLoading {
                        ProgressView()
                            .tint(SupportTheme.onAccent)
                    } else {
                        Text("Join Plan")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(inviteCode.count == 8 ? SupportTheme.accent : SupportTheme.textSecondary)
                .foregroundStyle(SupportTheme.onAccent)
                .cornerRadius(SupportTheme.controlRadius)
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
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                    .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                    .accessibilityLabel("Close")
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

#if DEBUG
    /// Local StoreKit catalog fixture. This route skips normal app startup and never purchases.
    struct SubscriptionCatalogUITestView: View {
        @StateObject private var billingService: BillingService

        init() {
            let loader = SubscriptionCatalogUITestLoader()
            _billingService = StateObject(
                wrappedValue: BillingService(
                    authService: SupabaseAuthService(),
                    productLoader: { try await loader.load($0) },
                    observeTransactions: false))
        }

        var body: some View {
            SubscriptionContent(billingService: billingService)
        }
    }

    private actor SubscriptionCatalogUITestLoader {
        private var calls = 0

        func load(_ ids: [String]) async throws -> [Product] {
            calls += 1
            if calls == 1 { return [] }
            if calls == 2 { throw URLError(.notConnectedToInternet) }
            let products = try await Product.products(for: ids)
            guard products.count == ids.count,
                products.allSatisfy({ $0.description == "Synthetic StoreKit UI test" })
            else {
                throw URLError(.badServerResponse)
            }
            return products
        }
    }
#endif
