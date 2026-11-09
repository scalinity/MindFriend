import SwiftUI

// MARK: - Safety Plan Condensed View ("I Need Help Now")

struct SafetyPlanCondensedView: View {
    @Environment(\.dismiss) private var dismiss

    let payload: SafetyPlanPayload
    let settings: SafetyPlanSettings
    let isStale: Bool

    @State private var showingCrisisCall = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SupportTheme.Spacing.l) {
                    // Header
                    headerView

                    if isStale {
                        staleBanner
                    }

                    // Warning Signs Recognition
                    if !payload.warningSigns.isEmpty {
                        warningSignsSection
                    }

                    // Top Coping Actions
                    if !payload.coping.isEmpty {
                        copingSection
                    }

                    // Trusted Contacts
                    if !payload.contacts.isEmpty {
                        contactsSection
                    }

                    // Crisis Hotline
                    crisisHotlineSection
                }
                .padding()
            }
            .background(Color.red.opacity(0.05))
            .supportScreen()
            .foregroundStyle(SupportTheme.textPrimary)
            .navigationTitle("I Need Help Now")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingCrisisCall) {
                CrisisCallView()
            }
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        VStack(spacing: SupportTheme.Spacing.s) {
            Image(systemName: "heart.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            Text("It's okay to ask for help.")
                .font(.title2)
                .accessibilityAddTraits(.isHeader)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            Text("Take it one step at a time. Your safety plan is here to help.")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical)
    }

    private var staleBanner: some View {
        HStack(spacing: SupportTheme.Spacing.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(SupportTheme.accent)
            Text("This safety plan may be outdated. Connect to refresh.")
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
            Spacer()
        }
        .padding(SupportTheme.Spacing.s)
        .background(SupportTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
    }

    // MARK: - Warning Signs Section

    private var warningSignsSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            HStack {
                Image(systemName: "eye.fill")
                    .foregroundStyle(SupportTheme.accent)
                Text("Recognizing What's Happening")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
            }

            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                ForEach(payload.warningSigns.prefix(3)) { sign in
                    HStack(spacing: SupportTheme.Spacing.xs) {
                        Circle()
                            .fill(SupportTheme.accent.opacity(0.3))
                            .frame(width: 8, height: 8)
                        Text(sign.text)
                            .font(.subheadline)
                    }
                }

                if payload.warningSigns.count > 3 {
                    Text("+\(payload.warningSigns.count - 3) more signs")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SupportTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
    }

    // MARK: - Coping Section

    private var copingSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            HStack {
                Image(systemName: "leaf.fill")
                    .foregroundStyle(SupportTheme.accent)
                Text("Quick Actions You Can Take")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
            }

            // Top favorites first
            let favorites = payload.coping.filter { $0.isFavorite }
            let others = payload.coping.filter { !$0.isFavorite }
            let sortedCoping = favorites + others

            ForEach(sortedCoping.prefix(3)) { coping in
                CopingActionRow(coping: coping)
            }

            if payload.coping.count > 3 {
                Text("+\(payload.coping.count - 3) more strategies")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SupportTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
    }

    // MARK: - Contacts Section

    private var contactsSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            HStack {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(SupportTheme.accent)
                Text("People Who Can Help")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
            }

            // Primary contact first
            let primaryContact = payload.contacts.first { $0.isPrimary }
            let sortedContacts = [primaryContact].compactMap { $0 } + payload.contacts.filter { !$0.isPrimary }

            ForEach(sortedContacts.prefix(2)) { contact in
                ContactActionRow(contact: contact)
            }

            if payload.contacts.count > 2 {
                Text("+\(payload.contacts.count - 2) more contacts")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SupportTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
    }

    // MARK: - Crisis Hotline Section

    private var crisisHotlineSection: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            HStack {
                Image(systemName: "phone.fill")
                    .foregroundStyle(SupportTheme.textPrimary)
                Text("Crisis Hotline")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .foregroundStyle(SupportTheme.textPrimary)
            }

            Text("Professional support is available 24/7")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textPrimary.opacity(0.9))

            // Primary crisis number
            let crisisNumber = payload.resources.first { $0.type == .hotline || $0.type == .crisisLine }?.phone ?? "988"

            Button {
                showingCrisisCall = true
            } label: {
                HStack {
                    Image(systemName: "phone.fill")
                    Text(crisisNumber)
                        .font(.title2)
                        .accessibilityAddTraits(.isHeader)
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(SupportTheme.textPrimary)
                .foregroundStyle(.red)
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
            }

            Button {
                callNumber(crisisNumber)
            } label: {
                Text("Call \(crisisNumber)")
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textPrimary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.red)
        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
    }
}

// MARK: - Coping Action Row

struct CopingActionRow: View {
    let coping: CopingStrategy

    var body: some View {
        Button {
            launchExercise()
        } label: {
            HStack {
                Image(systemName: coping.category.icon)
                    .foregroundStyle(SupportTheme.accent)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text(coping.label)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(SupportTheme.textPrimary)

                    if let duration = coping.duration {
                        Text("\(duration) min")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                }

                Spacer()

                Image(systemName: "play.circle.fill")
                    .foregroundStyle(SupportTheme.accent)
            }
            .padding(.vertical, SupportTheme.Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func launchExercise() {
        guard let exerciseId = coping.exerciseId else { return }
        // In a full implementation, this would launch the exercise player
        print("Would launch exercise: \(exerciseId)")
    }
}

// MARK: - Contact Action Row

struct ContactActionRow: View {
    let contact: TrustedContact

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(contact.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(contact.relationship.displayName)
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }

            Spacer()

            Button {
                if contact.preferredMethod == .call {
                    callContact()
                } else {
                    textContact()
                }
            } label: {
                HStack(spacing: SupportTheme.Spacing.xxs) {
                    Image(systemName: contact.preferredMethod.icon)
                    Text(contact.preferredMethod.displayName)
                }
                .font(.caption)
                .padding(.horizontal, SupportTheme.Spacing.s)
                .padding(.vertical, SupportTheme.Spacing.xs)
                .background(SupportTheme.accent)
                .foregroundStyle(SupportTheme.onAccent)
                .clipShape(Capsule())
            }
        }
        .padding(.vertical, SupportTheme.Spacing.xxs)
    }

    private func callContact() {
        let cleanPhone = contact.phone.replacingOccurrences(of: "+", with: "")
        if let url = URL(string: "tel://\(cleanPhone)") {
            UIApplication.shared.open(url)
        }
    }

    private func textContact() {
        let cleanPhone = contact.phone.replacingOccurrences(of: "+", with: "")
        if let url = URL(string: "sms:\(cleanPhone)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Crisis Call View

struct CrisisCallView: View {
    @Environment(\.dismiss) private var dismiss

    let crisisNumber = "988"

    var body: some View {
        NavigationStack {
            VStack(spacing: SupportTheme.Spacing.l) {
                Spacer()

                Image(systemName: "phone.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.red)

                Text("Calling 988")
                    .font(.title)
                    .accessibilityAddTraits(.isHeader)
                    .fontWeight(.bold)

                Text("Suicide & Crisis Lifeline")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .foregroundStyle(SupportTheme.textSecondary)

                Text("You'll be connected to a trained counselor who can help.")
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()

                VStack(spacing: SupportTheme.Spacing.s) {
                    Button {
                        callNumber(crisisNumber)
                        dismiss()
                    } label: {
                        Label("Call Now", systemImage: "phone.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .foregroundStyle(SupportTheme.textPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
                    }

                    Button {
                        dismiss()
                    } label: {
                        Text("Not ready to call")
                            .font(.subheadline)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                }
                .padding(.horizontal, SupportTheme.Spacing.l)
                .padding(.bottom, SupportTheme.Spacing.xl)
            }
            .navigationBarHidden(true)
        }
    }

    private func callNumber(_ number: String) {
        let cleanNumber = number.replacingOccurrences(of: "+", with: "")
        if let url = URL(string: "tel://\(cleanNumber)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Helper Functions

private func callNumber(_ number: String) {
    let cleanNumber = number.replacingOccurrences(of: "+", with: "")
    if let url = URL(string: "tel://\(cleanNumber)") {
        UIApplication.shared.open(url)
    }
}

// MARK: - Preview

#if DEBUG
    #Preview {
        SafetyPlanCondensedView(
            payload: SafetyPlanPayload(
                warningSigns: [
                    SafetyPlanItem(text: "Withdrawing from others"),
                    SafetyPlanItem(text: "Sleep quality decreases"),
                    SafetyPlanItem(text: "Racing thoughts"),
                ],
                coping: [
                    CopingStrategy(
                        type: .exercise, label: "Box Breathing", duration: 2, category: .breathing, isFavorite: true),
                    CopingStrategy(type: .custom, label: "Take a walk", category: .movement, isFavorite: false),
                ],
                contacts: [
                    TrustedContact(
                        name: "Mom", phone: "+1234567890", relationship: .family, preferredMethod: .call,
                        isPrimary: true)
                ],
                resources: [
                    ProfessionalResource(type: .hotline, name: "988", phone: "988", country: "US")
                ]
            ),
            settings: SafetyPlanSettings(),
            isStale: false
        )
    }
#endif
