//
//  TherapistProfileView.swift
//  MindFriendApp
//
//  Therapist/Coach Marketplace - Profile Detail View
//

import SwiftUI

struct TherapistProfileView: View {
    let therapist: TherapistProfile

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: SupportTheme.Spacing.l) {
                // Header
                headerSection

                // About
                aboutSection

                // Specialties
                specialtiesSection

                // Approaches
                if let approaches = therapist.approaches, !approaches.isEmpty {
                    approachesSection(approaches)
                }

                // Rates
                ratesSection

                // Reviews placeholder
                reviewsSection

                Spacer(minLength: SupportTheme.Spacing.xl)
            }
            .padding(SupportTheme.Spacing.m)
        }
        .navigationBarTitleDisplayMode(.inline)
        // An inset, not an overlay: the scroll view reserves the footer's height at every text size.
        .safeAreaInset(edge: .bottom) {
            bookingButton
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            // Photo
            AsyncImage(url: URL(string: therapist.photoUrl ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                default:
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .foregroundStyle(SupportTheme.textSecondary)
                }
            }
            .frame(width: 120, height: 120)
            .clipShape(Circle())
            .shadow(color: SupportTheme.canvas.opacity(0.1), radius: 8, y: 4)

            // Name and Credentials
            VStack(spacing: SupportTheme.Spacing.xxs) {
                HStack(spacing: SupportTheme.Spacing.xs) {
                    Text(therapist.displayName)
                        .font(.title2.bold())

                    if therapist.verified {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(SupportTheme.accent)
                            .accessibilityLabel("Verified")
                    }
                }

                Text(therapist.displayCredentials)
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textSecondary)

                if let location = therapist.displayLocation {
                    HStack(spacing: SupportTheme.Spacing.xxs) {
                        Image(systemName: "mappin.circle.fill")
                        Text(location)
                    }
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
                }
            }

            // Stats Row
            HStack(spacing: SupportTheme.Spacing.xl) {
                statItem(
                    value: therapist.displayRating,
                    label: "Rating",
                    icon: "star.fill",
                    iconColor: SupportTheme.accent
                )

                statItem(
                    value: "\(therapist.ratingCount)",
                    label: "Reviews",
                    icon: "text.bubble.fill",
                    iconColor: SupportTheme.accent
                )

                statItem(
                    value: "\(therapist.sessionsCompleted)",
                    label: "Sessions",
                    icon: "video.fill",
                    iconColor: SupportTheme.accent
                )
            }
            .padding(.top, SupportTheme.Spacing.xs)
        }
    }

    private func statItem(value: String, label: String, icon: String, iconColor: Color) -> some View {
        VStack(spacing: SupportTheme.Spacing.xxs) {
            HStack(spacing: SupportTheme.Spacing.xxs) {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                Text(value)
                    .fontWeight(.semibold)
            }
            .font(.headline)

            Text(label)
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("About")
                .font(.headline)

            Text(therapist.bio)
                .font(.body)
                .foregroundStyle(SupportTheme.textSecondary)
                .lineLimit(nil)

            // Languages
            if !therapist.languages.isEmpty {
                HStack(spacing: SupportTheme.Spacing.xs) {
                    Image(systemName: "globe")
                        .foregroundStyle(SupportTheme.textSecondary)
                    Text("Speaks: \(therapist.languages.joined(separator: ", "))")
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
                .padding(.top, SupportTheme.Spacing.xxs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .supportCard()
    }

    // MARK: - Specialties Section

    private var specialtiesSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Specialties")
                .font(.headline)

            FlowLayout(spacing: SupportTheme.Spacing.xs) {
                ForEach(therapist.displaySpecialties, id: \.self) { specialty in
                    HStack(spacing: SupportTheme.Spacing.xxs) {
                        Image(systemName: specialty.icon)
                            .font(.caption)
                        Text(specialty.displayName)
                            .font(.subheadline)
                    }
                    .padding(.horizontal, SupportTheme.Spacing.s)
                    .padding(.vertical, SupportTheme.Spacing.xs)
                    .background(SupportTheme.surface)
                    .foregroundStyle(SupportTheme.accent)
                    .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Approaches Section

    private func approachesSection(_ approaches: [String]) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Therapeutic Approaches")
                .font(.headline)

            FlowLayout(spacing: SupportTheme.Spacing.xs) {
                ForEach(approaches, id: \.self) { approach in
                    Text(approach)
                        .font(.subheadline)
                        .padding(.horizontal, SupportTheme.Spacing.s)
                        .padding(.vertical, SupportTheme.Spacing.xs)
                        .background(SupportTheme.separator)
                        .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Rates Section

    private var ratesSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Session Rates")
                .font(.headline)

            VStack(spacing: SupportTheme.Spacing.xs) {
                if let rate30 = therapist.rate30Min {
                    rateRow(duration: "30 min", rate: rate30)
                }
                if let rate45 = therapist.rate45Min {
                    rateRow(duration: "45 min", rate: rate45)
                }
                if let rate60 = therapist.rate60Min {
                    rateRow(duration: "60 min", rate: rate60)
                }
            }
            .supportCard()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rateRow(duration: String, rate: Decimal) -> some View {
        HStack {
            Text(duration)
                .foregroundStyle(SupportTheme.textSecondary)
            Spacer()
            Text(formatRate(rate))
                .font(.headline)
        }
    }

    private func formatRate(_ rate: Decimal) -> String {
        let number = NSDecimalNumber(decimal: rate)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = rate.isWholeNumber ? 0 : 2
        return formatter.string(from: number) ?? "$\(number)"
    }

    // MARK: - Reviews Section

    private var reviewsSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            HStack {
                Text("Reviews")
                    .font(.headline)

                Spacer()

                if therapist.ratingCount > 0 {
                    Text("See all \(therapist.ratingCount)")
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.accent)
                }
            }

            if therapist.ratingCount == 0 {
                Text("No reviews yet")
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .supportCard()
            } else {
                // Placeholder for reviews - would fetch from therapy_sessions
                Text("Reviews will appear here once the booking system is implemented.")
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .supportCard()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Booking Button

    private var bookingButton: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: SupportTheme.Spacing.m) {
                VStack(alignment: .leading) {
                    Text(therapist.displayRate)
                        .font(.headline)
                    Text("per session")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }

                Spacer()

                Button {
                    // TODO: Implement booking flow in Phase 2
                } label: {
                    Text("Book Session")
                        .font(.headline)
                        .foregroundStyle(SupportTheme.onAccent)
                        .padding(.horizontal, SupportTheme.Spacing.l)
                        .padding(.vertical, SupportTheme.Spacing.s)
                        .background(SupportTheme.accent)
                        .clipShape(Capsule())
                }
            }
            .padding(SupportTheme.Spacing.m)
            .background(SupportTheme.elevated)
        }
    }
}

// MARK: - Decimal Extension

extension Decimal {
    var isWholeNumber: Bool {
        let rounded = NSDecimalNumber(decimal: self).rounding(accordingToBehavior: nil)
        return self == rounded.decimalValue && self.description.contains(".") == false
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        TherapistProfileView(
            therapist: TherapistProfile(
                id: UUID(),
                userId: UUID(),
                profileType: .therapist,
                displayName: "Dr. Sarah Johnson",
                bio: "I specialize in helping adults manage anxiety and build healthier relationships. With over 15 years of experience, I use evidence-based approaches to help my clients achieve their goals.",
                photoUrl: nil,
                credentials: ["LMFT", "LCSW"],
                specialties: ["anxiety", "depression", "relationships", "self_esteem"],
                approaches: ["CBT", "Mindfulness", "Attachment-Based"],
                languages: ["English", "Spanish"],
                licenseNumber: "MFT123456",
                licenseState: "CA",
                verified: true,
                verifiedAt: Date(),
                backgroundCheckPassed: true,
                applicationStatus: .approved,
                applicationSubmittedAt: Date(),
                rate30Min: 80,
                rate45Min: 100,
                rate60Min: 120,
                acceptsNewClients: true,
                ratingAverage: 4.9,
                ratingCount: 127,
                sessionsCompleted: 523,
                createdAt: Date(),
                updatedAt: Date()
            )
        )
    }
}
