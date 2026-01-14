# 08 - Monetization Improvements

## Overview

Premium feels like "more" not "unlock what we hid." This spec covers enhanced monetization strategies that increase perceived value, encourage longer commitments, and create social subscription mechanics—all while maintaining the generous free tier that builds trust.

**Priority:** P8 (Revenue Optimization)
**Impact:** Revenue ↑↑↑, Retention ↑↑ (annual plans lock in users)
**Complexity:** Medium

---

## User Stories

### Family/Couples Plans

- As a **couple using MindFriend**, I want a shared plan so that we can support each other's mental wellness journey together
- As a **parent**, I want a family plan so that my family can all benefit from premium features at a reasonable price
- As a **family plan admin**, I want to see my family members' wellness (with consent) so that I can support them

### Annual Discount

- As a **committed user**, I want an annual option so that I can save money on my subscription
- As a **budget-conscious user**, I want to see the savings clearly so that I understand the value

### Premium Perks

- As a **premium user**, I want exclusive badges so that my commitment is recognized
- As a **premium user**, I want faster AI responses so that my experience feels prioritized

---

## Product Requirements

### Must Have (MVP)

1. **Plan Types**
   - Individual Monthly ($9.99/month)
   - Individual Annual ($59.99/year = $5/month, 50% savings)
   - Couples Plan ($14.99/month for 2 people)
   - Family Plan ($19.99/month for up to 6 people)

2. **Annual Discount Presentation**
   - Show monthly equivalent price
   - Display total savings prominently
   - "Most Popular" badge on annual plan
   - Free trial applies to annual too

3. **Family/Couples Management**
   - Plan owner (admin) invites members via email
   - Each member has independent account + data
   - Shared "Family Circle" auto-created
   - Admin can remove members
   - Members keep data if removed (just lose premium)

4. **Premium Badge**
   - "Premium Supporter" badge for all premium users
   - Badge displays on profile and in circles
   - Different tiers: Monthly, Annual, Family Admin

### Nice to Have (V2)

1. **Priority AI Queue**
   - Premium users get faster response times during peak hours
   - Show "Priority" indicator while waiting

2. **Gift Subscriptions**
   - Purchase premium for someone else
   - Gift card codes redeemable in app

3. **Referral Rewards**
   - Premium users get 1 free month per successful referral
   - Referred user gets extended trial (14 days vs 7)

4. **Couples Insights**
   - Shared mood correlation view (both must opt-in)
   - "Check-in together" feature
   - Relationship wellness tips

5. **Family Dashboard**
   - Admin sees family wellness overview (opted-in members only)
   - Family challenges and achievements
   - "Family streak" tracking

### Out of Scope

- B2B/enterprise plans
- Therapy session credits
- Pay-per-feature model
- Cryptocurrency payments
- Regional pricing (complex compliance)

---

## Technical Design

### Data Model Changes

#### Migration: `20250115000008_monetization_improvements.sql`

```sql
-- Enhance subscriptions table for plan types
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS plan_type TEXT DEFAULT 'individual';
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS billing_period TEXT DEFAULT 'monthly';
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS family_id UUID;
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS is_family_admin BOOLEAN DEFAULT FALSE;
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS seats_used INT DEFAULT 1;
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS seats_total INT DEFAULT 1;

-- Add constraint for valid plan types
ALTER TABLE subscriptions ADD CONSTRAINT valid_plan_type
  CHECK (plan_type IN ('individual', 'couples', 'family'));

-- Add constraint for valid billing periods
ALTER TABLE subscriptions ADD CONSTRAINT valid_billing_period
  CHECK (billing_period IN ('monthly', 'annual'));

-- Family groups table
CREATE TABLE family_groups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT DEFAULT 'My Family',
  admin_user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Family members table
CREATE TABLE family_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id UUID NOT NULL REFERENCES family_groups(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  invited_email TEXT,
  status TEXT DEFAULT 'pending', -- 'pending', 'active', 'removed'
  invited_at TIMESTAMPTZ DEFAULT NOW(),
  joined_at TIMESTAMPTZ,
  removed_at TIMESTAMPTZ,
  UNIQUE(family_id, user_id)
);

-- Family invitations (for users not yet signed up)
CREATE TABLE family_invitations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id UUID NOT NULL REFERENCES family_groups(id) ON DELETE CASCADE,
  email TEXT NOT NULL,
  invite_code TEXT NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ DEFAULT NOW() + INTERVAL '7 days',
  accepted_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Premium badges (earned by subscription)
INSERT INTO badges (id, name, description, icon_name, category, unlock_criteria, is_premium) VALUES
  (gen_random_uuid(), 'Premium Supporter', 'Thanks for supporting MindFriend!', 'star.fill', 'subscription', 'Subscribe to premium', true),
  (gen_random_uuid(), 'Annual Achiever', 'Committed to a year of growth', 'calendar.badge.checkmark', 'subscription', 'Subscribe to annual plan', true),
  (gen_random_uuid(), 'Family Champion', 'Leading your family''s wellness journey', 'person.3.fill', 'subscription', 'Admin of a family plan', true);

-- Gift subscriptions
CREATE TABLE gift_subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  purchaser_user_id UUID REFERENCES profiles(id),
  gift_code TEXT NOT NULL UNIQUE,
  plan_type TEXT NOT NULL DEFAULT 'individual',
  billing_period TEXT NOT NULL DEFAULT 'monthly',
  duration_months INT NOT NULL DEFAULT 1,
  redeemed_by_user_id UUID REFERENCES profiles(id),
  redeemed_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ DEFAULT NOW() + INTERVAL '1 year',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_family_members_family_id ON family_members(family_id);
CREATE INDEX idx_family_members_user_id ON family_members(user_id);
CREATE INDEX idx_family_invitations_code ON family_invitations(invite_code);
CREATE INDEX idx_family_invitations_email ON family_invitations(email);
CREATE INDEX idx_gift_subscriptions_code ON gift_subscriptions(gift_code);
CREATE INDEX idx_subscriptions_family_id ON subscriptions(family_id);

-- RLS Policies
ALTER TABLE family_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE family_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE family_invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE gift_subscriptions ENABLE ROW LEVEL SECURITY;

-- Family groups: admin can do everything
CREATE POLICY "Admin manages family group" ON family_groups
  FOR ALL USING (auth.uid() = admin_user_id);

-- Family members: admin can manage, members can view
CREATE POLICY "View family members" ON family_members
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM family_groups
      WHERE id = family_id
      AND (admin_user_id = auth.uid() OR EXISTS (
        SELECT 1 FROM family_members fm
        WHERE fm.family_id = family_groups.id
        AND fm.user_id = auth.uid()
        AND fm.status = 'active'
      ))
    )
  );

CREATE POLICY "Admin manages family members" ON family_members
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM family_groups
      WHERE id = family_id AND admin_user_id = auth.uid()
    )
  );

-- Invitations: admin can manage
CREATE POLICY "Admin manages invitations" ON family_invitations
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM family_groups
      WHERE id = family_id AND admin_user_id = auth.uid()
    )
  );

-- Gift subscriptions: purchaser and recipient can view
CREATE POLICY "View own gift subscriptions" ON gift_subscriptions
  FOR SELECT USING (
    purchaser_user_id = auth.uid() OR redeemed_by_user_id = auth.uid()
  );
```

### iOS Implementation

#### New Models

```swift
// Models.swift additions

enum PlanType: String, Codable, CaseIterable {
    case individual
    case couples
    case family

    var displayName: String {
        switch self {
        case .individual: return "Individual"
        case .couples: return "Couples"
        case .family: return "Family"
        }
    }

    var maxSeats: Int {
        switch self {
        case .individual: return 1
        case .couples: return 2
        case .family: return 6
        }
    }
}

enum BillingPeriod: String, Codable, CaseIterable {
    case monthly
    case annual

    var displayName: String {
        switch self {
        case .monthly: return "Monthly"
        case .annual: return "Annual"
        }
    }
}

struct FamilyGroup: Identifiable, Codable {
    let id: UUID
    var name: String
    let adminUserId: UUID
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name
        case adminUserId = "admin_user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct FamilyMember: Identifiable, Codable {
    let id: UUID
    let familyId: UUID
    let userId: UUID
    let invitedEmail: String?
    var status: MemberStatus
    let invitedAt: Date
    var joinedAt: Date?
    var removedAt: Date?

    // Joined profile data
    var profile: Profile?

    enum MemberStatus: String, Codable {
        case pending
        case active
        case removed
    }

    enum CodingKeys: String, CodingKey {
        case id
        case familyId = "family_id"
        case userId = "user_id"
        case invitedEmail = "invited_email"
        case status
        case invitedAt = "invited_at"
        case joinedAt = "joined_at"
        case removedAt = "removed_at"
        case profile
    }
}

struct FamilyInvitation: Identifiable, Codable {
    let id: UUID
    let familyId: UUID
    let email: String
    let inviteCode: String
    let expiresAt: Date
    var acceptedAt: Date?
    let createdAt: Date

    var isExpired: Bool {
        Date() > expiresAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case familyId = "family_id"
        case email
        case inviteCode = "invite_code"
        case expiresAt = "expires_at"
        case acceptedAt = "accepted_at"
        case createdAt = "created_at"
    }
}

// Extend existing Subscription model
extension Subscription {
    var planType: PlanType {
        PlanType(rawValue: planTypeRaw ?? "individual") ?? .individual
    }

    var billingPeriod: BillingPeriod {
        BillingPeriod(rawValue: billingPeriodRaw ?? "monthly") ?? .monthly
    }

    var isFamily: Bool {
        planType == .family || planType == .couples
    }

    var availableSeats: Int {
        seatsTotal - seatsUsed
    }
}
```

#### New Service Methods

```swift
// BillingService.swift additions

extension BillingService {

    // MARK: - Family Management

    func createFamilyGroup(name: String) async throws -> FamilyGroup {
        let userId = try await supabase.auth.session.user.id

        let group = FamilyGroup(
            id: UUID(),
            name: name,
            adminUserId: userId,
            createdAt: Date(),
            updatedAt: Date()
        )

        return try await supabase
            .from("family_groups")
            .insert(group)
            .select()
            .single()
            .execute()
            .value
    }

    func getFamilyGroup() async throws -> FamilyGroup? {
        let userId = try await supabase.auth.session.user.id

        // Check if user is admin
        let adminGroup: [FamilyGroup] = try await supabase
            .from("family_groups")
            .select()
            .eq("admin_user_id", value: userId)
            .execute()
            .value

        if let group = adminGroup.first {
            return group
        }

        // Check if user is member
        let membership: [FamilyMember] = try await supabase
            .from("family_members")
            .select("*, family_groups(*)")
            .eq("user_id", value: userId)
            .eq("status", value: "active")
            .execute()
            .value

        // Return first active family
        return nil // Would need joined query
    }

    func inviteFamilyMember(email: String) async throws -> FamilyInvitation {
        guard let familyGroup = try await getFamilyGroup() else {
            throw BillingError.noFamilyGroup
        }

        // Check seat availability
        let subscription = try await getSubscription()
        guard subscription?.availableSeats ?? 0 > 0 else {
            throw BillingError.noSeatsAvailable
        }

        let invitation = FamilyInvitation(
            id: UUID(),
            familyId: familyGroup.id,
            email: email,
            inviteCode: generateInviteCode(),
            expiresAt: Date().addingTimeInterval(7 * 24 * 60 * 60),
            acceptedAt: nil,
            createdAt: Date()
        )

        return try await supabase
            .from("family_invitations")
            .insert(invitation)
            .select()
            .single()
            .execute()
            .value
    }

    func acceptFamilyInvitation(code: String) async throws {
        try await supabase.functions.invoke(
            "accept-family-invite",
            options: .init(body: ["invite_code": code])
        )
    }

    func removeFamilyMember(memberId: UUID) async throws {
        try await supabase
            .from("family_members")
            .update(["status": "removed", "removed_at": ISO8601DateFormatter().string(from: Date())])
            .eq("id", value: memberId)
            .execute()
    }

    func getFamilyMembers() async throws -> [FamilyMember] {
        guard let familyGroup = try await getFamilyGroup() else {
            return []
        }

        return try await supabase
            .from("family_members")
            .select("*, profiles(*)")
            .eq("family_id", value: familyGroup.id)
            .neq("status", value: "removed")
            .execute()
            .value
    }

    // MARK: - Helper

    private func generateInviteCode() -> String {
        let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<8).map { _ in chars.randomElement()! })
    }
}

enum BillingError: LocalizedError {
    case noFamilyGroup
    case noSeatsAvailable
    case invalidInviteCode
    case inviteExpired

    var errorDescription: String? {
        switch self {
        case .noFamilyGroup: return "No family group found"
        case .noSeatsAvailable: return "No seats available in your plan"
        case .invalidInviteCode: return "Invalid invitation code"
        case .inviteExpired: return "This invitation has expired"
        }
    }
}
```

#### New Views

**File:** `apps/ios/MindFriendApp/Features/Profile/SubscriptionView.swift`

```swift
import SwiftUI

struct SubscriptionView: View {
    @EnvironmentObject private var container: DependencyContainer
    @State private var selectedPlan: PlanType = .individual
    @State private var selectedPeriod: BillingPeriod = .annual
    @State private var isLoading = false
    @State private var showFamilyManagement = false

    private let prices: [PlanType: [BillingPeriod: (price: Decimal, monthly: Decimal)]] = [
        .individual: [
            .monthly: (9.99, 9.99),
            .annual: (59.99, 5.00)
        ],
        .couples: [
            .monthly: (14.99, 14.99),
            .annual: (89.99, 7.50)
        ],
        .family: [
            .monthly: (19.99, 19.99),
            .annual: (119.99, 10.00)
        ]
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection

                // Plan Type Selection
                planTypeSection

                // Billing Period Selection
                billingPeriodSection

                // Price Summary
                priceSummarySection

                // Subscribe Button
                subscribeButton

                // Features List
                featuresSection

                // Family Management (if applicable)
                if selectedPlan != .individual {
                    familySection
                }
            }
            .padding()
        }
        .navigationTitle("Premium")
        .sheet(isPresented: $showFamilyManagement) {
            FamilyManagementView()
        }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.yellow)

            Text("Unlock Your Full Potential")
                .font(.title2.bold())

            Text("Premium gives you unlimited access to everything MindFriend has to offer")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var planTypeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose Your Plan")
                .font(.headline)

            ForEach(PlanType.allCases, id: \.self) { plan in
                PlanTypeCard(
                    plan: plan,
                    isSelected: selectedPlan == plan,
                    monthlyPrice: prices[plan]?[selectedPeriod]?.monthly ?? 0
                ) {
                    withAnimation { selectedPlan = plan }
                }
            }
        }
    }

    private var billingPeriodSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Billing Period")
                .font(.headline)

            HStack(spacing: 12) {
                BillingPeriodCard(
                    period: .annual,
                    isSelected: selectedPeriod == .annual,
                    savingsPercent: 50
                ) {
                    withAnimation { selectedPeriod = .annual }
                }

                BillingPeriodCard(
                    period: .monthly,
                    isSelected: selectedPeriod == .monthly,
                    savingsPercent: nil
                ) {
                    withAnimation { selectedPeriod = .monthly }
                }
            }
        }
    }

    private var priceSummarySection: some View {
        VStack(spacing: 8) {
            if let pricing = prices[selectedPlan]?[selectedPeriod] {
                HStack {
                    Text("Total")
                        .font(.headline)
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("$\(pricing.price, specifier: "%.2f")")
                            .font(.title2.bold())
                        if selectedPeriod == .annual {
                            Text("$\(pricing.monthly, specifier: "%.2f")/month")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if selectedPeriod == .annual, let monthlyPrice = prices[selectedPlan]?[.monthly]?.price {
                    let savings = (monthlyPrice * 12) - pricing.price
                    Text("You save $\(savings, specifier: "%.2f") per year!")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var subscribeButton: some View {
        Button {
            Task { await subscribe() }
        } label: {
            if isLoading {
                ProgressView()
                    .tint(.white)
            } else {
                Text("Start Free Trial")
                    .font(.headline)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.accentColor)
        .foregroundStyle(.white)
        .cornerRadius(12)
        .disabled(isLoading)
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What's Included")
                .font(.headline)

            FeatureRow(icon: "infinity", title: "Unlimited AI Conversations", description: "No daily limits on chatting with your AI companion")
            FeatureRow(icon: "book.fill", title: "All Premium Exercises", description: "Access to 14 additional guided exercises")
            FeatureRow(icon: "chart.line.uptrend.xyaxis", title: "Advanced Insights", description: "Deeper mood analysis and pattern detection")
            FeatureRow(icon: "star.fill", title: "Premium Badge", description: "Show your support in your profile")

            if selectedPlan != .individual {
                FeatureRow(icon: "person.2.fill", title: "Shared Family Circle", description: "Auto-created circle for your \(selectedPlan.displayName.lowercased()) plan")
            }
        }
    }

    private var familySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(selectedPlan == .couples ? "Your Partner" : "Family Members")
                    .font(.headline)
                Spacer()
                Text("0/\(selectedPlan.maxSeats)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                showFamilyManagement = true
            } label: {
                Label("Manage Members", systemImage: "person.badge.plus")
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func subscribe() async {
        isLoading = true
        defer { isLoading = false }

        // StoreKit purchase flow would go here
    }
}

struct PlanTypeCard: View {
    let plan: PlanType
    let isSelected: Bool
    let monthlyPrice: Decimal
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.displayName)
                        .font(.headline)
                    Text(planDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("$\(monthlyPrice, specifier: "%.2f")/mo")
                    .font(.subheadline.bold())

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .accentColor : .secondary)
            }
            .padding()
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color(.systemGray6))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var planDescription: String {
        switch plan {
        case .individual: return "Just for you"
        case .couples: return "For 2 people"
        case .family: return "Up to 6 people"
        }
    }
}

struct BillingPeriodCard: View {
    let period: BillingPeriod
    let isSelected: Bool
    let savingsPercent: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(period.displayName)
                    .font(.headline)

                if let savings = savingsPercent {
                    Text("Save \(savings)%")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color(.systemGray6))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
```

**File:** `apps/ios/MindFriendApp/Features/Profile/FamilyManagementView.swift`

```swift
import SwiftUI

struct FamilyManagementView: View {
    @EnvironmentObject private var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss
    @State private var members: [FamilyMember] = []
    @State private var inviteEmail = ""
    @State private var isLoading = false
    @State private var showInviteSheet = false
    @State private var pendingInvitation: FamilyInvitation?

    var body: some View {
        NavigationStack {
            List {
                // Current Members Section
                Section("Members") {
                    ForEach(members) { member in
                        MemberRow(member: member) {
                            Task { await removeMember(member) }
                        }
                    }

                    if members.isEmpty {
                        Text("No members yet")
                            .foregroundStyle(.secondary)
                    }
                }

                // Invite Section
                Section {
                    Button {
                        showInviteSheet = true
                    } label: {
                        Label("Invite Member", systemImage: "person.badge.plus")
                    }
                } footer: {
                    Text("Invited members will receive an email with instructions to join your plan.")
                }
            }
            .navigationTitle("Family Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showInviteSheet) {
                InviteMemberSheet(
                    email: $inviteEmail,
                    isLoading: $isLoading,
                    invitation: $pendingInvitation
                ) {
                    await inviteMember()
                }
            }
            .task {
                await loadMembers()
            }
        }
    }

    private func loadMembers() async {
        do {
            members = try await container.billingService.getFamilyMembers()
        } catch {
            print("Failed to load members: \(error)")
        }
    }

    private func inviteMember() async {
        guard !inviteEmail.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            pendingInvitation = try await container.billingService.inviteFamilyMember(email: inviteEmail)
            inviteEmail = ""
        } catch {
            print("Failed to invite: \(error)")
        }
    }

    private func removeMember(_ member: FamilyMember) async {
        do {
            try await container.billingService.removeFamilyMember(memberId: member.id)
            await loadMembers()
        } catch {
            print("Failed to remove: \(error)")
        }
    }
}

struct MemberRow: View {
    let member: FamilyMember
    let onRemove: () -> Void

    var body: some View {
        HStack {
            // Avatar
            Circle()
                .fill(Color.accentColor.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay {
                    Text(member.profile?.displayName?.prefix(1).uppercased() ?? "?")
                        .font(.headline)
                        .foregroundStyle(.accentColor)
                }

            VStack(alignment: .leading) {
                Text(member.profile?.displayName ?? member.invitedEmail ?? "Unknown")
                    .font(.body)

                Text(member.status.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(member.status == .active ? .green : .orange)
            }

            Spacer()

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
    }
}

struct InviteMemberSheet: View {
    @Binding var email: String
    @Binding var isLoading: Bool
    @Binding var invitation: FamilyInvitation?
    let onInvite: () async -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let invitation = invitation {
                    // Success state
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.green)

                        Text("Invitation Sent!")
                            .font(.title2.bold())

                        Text("Share this code with your family member:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(invitation.inviteCode)
                            .font(.system(.title, design: .monospaced).bold())
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)

                        Button {
                            UIPasteboard.general.string = invitation.inviteCode
                        } label: {
                            Label("Copy Code", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)

                        Button("Done") {
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    // Input state
                    VStack(spacing: 16) {
                        Text("Invite Family Member")
                            .font(.title2.bold())

                        Text("Enter their email address to send an invitation")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        TextField("email@example.com", text: $email)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)

                        Button {
                            Task { await onInvite() }
                        } label: {
                            if isLoading {
                                ProgressView()
                            } else {
                                Text("Send Invitation")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(email.isEmpty || isLoading)
                    }
                }
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
```

### Backend Implementation

#### Edge Function: `accept-family-invite`

**File:** `supabase/functions/accept-family-invite/index.ts`

```typescript
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Get user from JWT
    const authHeader = req.headers.get("Authorization")!;
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { invite_code } = await req.json();

    // Find invitation
    const { data: invitation, error: inviteError } = await supabase
      .from("family_invitations")
      .select("*, family_groups(*)")
      .eq("invite_code", invite_code)
      .is("accepted_at", null)
      .single();

    if (inviteError || !invitation) {
      return new Response(
        JSON.stringify({ error: "Invalid or expired invitation code" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Check if expired
    if (new Date(invitation.expires_at) < new Date()) {
      return new Response(JSON.stringify({ error: "Invitation has expired" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Check seat availability
    const { data: subscription } = await supabase
      .from("subscriptions")
      .select("*")
      .eq("family_id", invitation.family_id)
      .eq("status", "active")
      .single();

    if (!subscription || subscription.seats_used >= subscription.seats_total) {
      return new Response(JSON.stringify({ error: "No seats available" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Add user to family
    const { error: memberError } = await supabase
      .from("family_members")
      .insert({
        family_id: invitation.family_id,
        user_id: user.id,
        invited_email: invitation.email,
        status: "active",
        joined_at: new Date().toISOString(),
      });

    if (memberError) {
      return new Response(JSON.stringify({ error: "Failed to join family" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Mark invitation as accepted
    await supabase
      .from("family_invitations")
      .update({ accepted_at: new Date().toISOString() })
      .eq("id", invitation.id);

    // Update seats used
    await supabase
      .from("subscriptions")
      .update({ seats_used: subscription.seats_used + 1 })
      .eq("id", subscription.id);

    // Grant premium to new member
    await supabase.from("subscriptions").upsert({
      user_id: user.id,
      status: "active",
      plan_type: subscription.plan_type,
      billing_period: subscription.billing_period,
      family_id: invitation.family_id,
      is_family_admin: false,
      current_period_end: subscription.current_period_end,
    });

    // Award premium badge
    const { data: badge } = await supabase
      .from("badges")
      .select("id")
      .eq("name", "Premium Supporter")
      .single();

    if (badge) {
      await supabase
        .from("user_badges")
        .upsert({ user_id: user.id, badge_id: badge.id });
    }

    return new Response(JSON.stringify({ success: true }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
```

#### Update `verify-purchase` for Plan Types

Add to existing Edge Function:

```typescript
// In verify-purchase/index.ts, after validating transaction

// Determine plan type from product ID
const planMapping: Record<string, { planType: string; billingPeriod: string }> =
  {
    "com.mindfriend.premium.monthly": {
      planType: "individual",
      billingPeriod: "monthly",
    },
    "com.mindfriend.premium.annual": {
      planType: "individual",
      billingPeriod: "annual",
    },
    "com.mindfriend.couples.monthly": {
      planType: "couples",
      billingPeriod: "monthly",
    },
    "com.mindfriend.couples.annual": {
      planType: "couples",
      billingPeriod: "annual",
    },
    "com.mindfriend.family.monthly": {
      planType: "family",
      billingPeriod: "monthly",
    },
    "com.mindfriend.family.annual": {
      planType: "family",
      billingPeriod: "annual",
    },
  };

const plan = planMapping[productId] || {
  planType: "individual",
  billingPeriod: "monthly",
};

// Create family group if needed
let familyId = null;
if (plan.planType !== "individual") {
  const { data: familyGroup } = await supabase
    .from("family_groups")
    .insert({ admin_user_id: user.id })
    .select()
    .single();

  familyId = familyGroup?.id;

  // Add admin as first member
  await supabase.from("family_members").insert({
    family_id: familyId,
    user_id: user.id,
    status: "active",
    joined_at: new Date().toISOString(),
  });
}

// Update subscription with plan details
await supabase.from("subscriptions").upsert({
  user_id: user.id,
  status: "active",
  plan_type: plan.planType,
  billing_period: plan.billingPeriod,
  family_id: familyId,
  is_family_admin: familyId !== null,
  seats_total:
    plan.planType === "family" ? 6 : plan.planType === "couples" ? 2 : 1,
  seats_used: 1,
  // ... other fields
});
```

### StoreKit Product Configuration

```
Product IDs:
- com.mindfriend.premium.monthly ($9.99)
- com.mindfriend.premium.annual ($59.99)
- com.mindfriend.couples.monthly ($14.99)
- com.mindfriend.couples.annual ($89.99)
- com.mindfriend.family.monthly ($19.99)
- com.mindfriend.family.annual ($119.99)
```

---

## UI/UX

### Subscription Screen Flow

```
┌─────────────────────────────────────────┐
│            [Star Icon]                  │
│   Unlock Your Full Potential            │
│                                         │
│   ┌───────────────────────────────┐     │
│   │ ○ Individual    $5/mo         │     │
│   │   Just for you                │     │
│   └───────────────────────────────┘     │
│   ┌───────────────────────────────┐     │
│   │ ● Couples       $7.50/mo      │     │
│   │   For 2 people                │     │
│   └───────────────────────────────┘     │
│   ┌───────────────────────────────┐     │
│   │ ○ Family        $10/mo        │     │
│   │   Up to 6 people              │     │
│   └───────────────────────────────┘     │
│                                         │
│   ┌─────────────┐ ┌─────────────┐       │
│   │   Annual    │ │   Monthly   │       │
│   │  Save 50%   │ │             │       │
│   └─────────────┘ └─────────────┘       │
│                                         │
│   Total: $89.99                         │
│   ($7.50/month)                         │
│   You save $90 per year!                │
│                                         │
│   ┌─────────────────────────────┐       │
│   │     Start Free Trial        │       │
│   └─────────────────────────────┘       │
│                                         │
│   ✓ Unlimited AI Conversations          │
│   ✓ All Premium Exercises               │
│   ✓ Advanced Insights                   │
│   ✓ Shared Family Circle                │
│                                         │
│   ┌─────────────────────────────┐       │
│   │  Manage Members (0/2)   >   │       │
│   └─────────────────────────────┘       │
└─────────────────────────────────────────┘
```

### Key Interactions

1. **Plan Selection**
   - Tap to select plan type
   - Price updates automatically
   - Family/Couples shows member count

2. **Billing Period Toggle**
   - Default to Annual (highlighted)
   - Show savings prominently
   - Animate price change

3. **Family Invite Flow**
   - Enter email → Send invitation
   - Show 8-character code
   - Copy to clipboard option

4. **Premium Badge Display**
   - Star icon next to name in profile
   - Shows in circle member list
   - Different color for Annual vs Monthly

---

## Verification

### Test Scenarios

1. **Individual Monthly Purchase**
   - Complete StoreKit purchase
   - Verify subscription record created
   - Verify premium badge awarded
   - Verify quota limits removed

2. **Family Plan Purchase**
   - Complete family plan purchase
   - Verify family_group created
   - Verify admin is first member
   - Verify seats_total = 6

3. **Family Invitation Flow**
   - Admin sends invite
   - Member enters code
   - Verify member added with premium
   - Verify seats_used incremented

4. **Member Removal**
   - Admin removes member
   - Verify member loses premium
   - Verify seats_used decremented
   - Verify member keeps historical data

5. **Annual Savings Display**
   - Switch between Monthly/Annual
   - Verify correct math
   - Verify savings message accurate

---

## Dependencies

- **Requires:** StoreKit 2 integration (existing)
- **Requires:** Badge system (existing)
- **Requires:** Push notifications for invites (spec-04)

---

## Risks & Mitigations

| Risk                              | Impact | Mitigation                                 |
| --------------------------------- | ------ | ------------------------------------------ |
| Complex family billing edge cases | High   | Start with simple flows, iterate           |
| App Store rejection for pricing   | Medium | Follow guidelines, clear descriptions      |
| Invitation code guessing          | Low    | 8-char alphanumeric = 2.8T combinations    |
| Family member disputes            | Medium | Clear admin controls, data stays with user |

---

## Implementation Estimate

| Component              | Estimate     |
| ---------------------- | ------------ |
| Database migration     | 2 hours      |
| iOS models & service   | 4 hours      |
| Subscription view      | 6 hours      |
| Family management view | 4 hours      |
| Edge Functions         | 4 hours      |
| StoreKit products      | 2 hours      |
| Testing                | 4 hours      |
| **Total**              | **26 hours** |

---

## Success Metrics

| Metric                    | Target                 |
| ------------------------- | ---------------------- |
| Annual plan adoption      | 40% of new subscribers |
| Family plan adoption      | 15% of paid users      |
| Revenue per user increase | +25%                   |
| Churn reduction (annual)  | -50% vs monthly        |
