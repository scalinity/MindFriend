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
                VStack(spacing: 24) {
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
        VStack(spacing: 12) {
            Image(systemName: "heart.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            Text("It's okay to ask for help.")
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            Text("Take it one step at a time. Your safety plan is here to help.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical)
    }

    private var staleBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("This safety plan may be outdated. Connect to refresh.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Warning Signs Section

    private var warningSignsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "eye.fill")
                    .foregroundStyle(.orange)
                Text("Recognizing What's Happening")
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(payload.warningSigns.prefix(3)) { sign in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.orange.opacity(0.3))
                            .frame(width: 8, height: 8)
                        Text(sign.text)
                            .font(.subheadline)
                    }
                }

                if payload.warningSigns.count > 3 {
                    Text("+\(payload.warningSigns.count - 3) more signs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Coping Section

    private var copingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "leaf.fill")
                    .foregroundStyle(.green)
                Text("Quick Actions You Can Take")
                    .font(.headline)
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
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Contacts Section

    private var contactsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(.blue)
                Text("People Who Can Help")
                    .font(.headline)
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
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Crisis Hotline Section

    private var crisisHotlineSection: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "phone.fill")
                    .foregroundStyle(.white)
                Text("Crisis Hotline")
                    .font(.headline)
                    .foregroundStyle(.white)
            }

            Text("Professional support is available 24/7")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))

            // Primary crisis number
            let crisisNumber = payload.resources.first { $0.type == .hotline || $0.type == .crisisLine }?.phone ?? "988"

            Button {
                showingCrisisCall = true
            } label: {
                HStack {
                    Image(systemName: "phone.fill")
                    Text(crisisNumber)
                        .font(.title2)
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.white)
                .foregroundStyle(.red)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button {
                callNumber(crisisNumber)
            } label: {
                Text("Call \(crisisNumber)")
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.red)
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
                    .foregroundStyle(.green)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(coping.label)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    if let duration = coping.duration {
                        Text("\(duration) min")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "play.circle.fill")
                    .foregroundStyle(.green)
            }
            .padding(.vertical, 8)
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
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(contact.relationship.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                if contact.preferredMethod == .call {
                    callContact()
                } else {
                    textContact()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: contact.preferredMethod.icon)
                    Text(contact.preferredMethod.displayName)
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
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
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "phone.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.red)

                Text("Calling 988")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Suicide & Crisis Lifeline")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text("You'll be connected to a trained counselor who can help.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        callNumber(crisisNumber)
                        dismiss()
                    } label: {
                        Label("Call Now", systemImage: "phone.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        dismiss()
                    } label: {
                        Text("Not ready to call")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
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
                SafetyPlanItem(text: "Racing thoughts")
            ],
            coping: [
                CopingStrategy(type: .exercise, label: "Box Breathing", duration: 2, category: .breathing, isFavorite: true),
                CopingStrategy(type: .custom, label: "Take a walk", category: .movement, isFavorite: false)
            ],
            contacts: [
                TrustedContact(name: "Mom", phone: "+1234567890", relationship: .family, preferredMethod: .call, isPrimary: true)
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
