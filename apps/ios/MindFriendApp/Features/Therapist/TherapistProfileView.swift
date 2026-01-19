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
            VStack(spacing: 24) {
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

                Spacer(minLength: 100)
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            bookingButton
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 16) {
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
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 120, height: 120)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.1), radius: 8, y: 4)

            // Name and Credentials
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    Text(therapist.displayName)
                        .font(.title2.bold())

                    if therapist.verified {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.blue)
                            .accessibilityLabel("Verified")
                    }
                }

                Text(therapist.displayCredentials)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let location = therapist.displayLocation {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle.fill")
                        Text(location)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            // Stats Row
            HStack(spacing: 32) {
                statItem(
                    value: therapist.displayRating,
                    label: "Rating",
                    icon: "star.fill",
                    iconColor: .yellow
                )

                statItem(
                    value: "\(therapist.ratingCount)",
                    label: "Reviews",
                    icon: "text.bubble.fill",
                    iconColor: .blue
                )

                statItem(
                    value: "\(therapist.sessionsCompleted)",
                    label: "Sessions",
                    icon: "video.fill",
                    iconColor: .green
                )
            }
            .padding(.top, 8)
        }
    }

    private func statItem(value: String, label: String, icon: String, iconColor: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                Text(value)
                    .fontWeight(.semibold)
            }
            .font(.headline)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About")
                .font(.headline)

            Text(therapist.bio)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(nil)

            // Languages
            if !therapist.languages.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .foregroundStyle(.secondary)
                    Text("Speaks: \(therapist.languages.joined(separator: ", "))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Specialties Section

    private var specialtiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Specialties")
                .font(.headline)

            FlowLayout(spacing: 8) {
                ForEach(therapist.displaySpecialties, id: \.self) { specialty in
                    HStack(spacing: 6) {
                        Image(systemName: specialty.icon)
                            .font(.caption)
                        Text(specialty.displayName)
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.1))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Approaches Section

    private func approachesSection(_ approaches: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Therapeutic Approaches")
                .font(.headline)

            FlowLayout(spacing: 8) {
                ForEach(approaches, id: \.self) { approach in
                    Text(approach)
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Rates Section

    private var ratesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session Rates")
                .font(.headline)

            VStack(spacing: 8) {
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
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rateRow(duration: String, rate: Decimal) -> some View {
        HStack {
            Text(duration)
                .foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Reviews")
                    .font(.headline)

                Spacer()

                if therapist.ratingCount > 0 {
                    Text("See all \(therapist.ratingCount)")
                        .font(.subheadline)
                        .foregroundStyle(.accentColor)
                }
            }

            if therapist.ratingCount == 0 {
                Text("No reviews yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                // Placeholder for reviews - would fetch from therapy_sessions
                Text("Reviews will appear here once the booking system is implemented.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Booking Button

    private var bookingButton: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 16) {
                VStack(alignment: .leading) {
                    Text(therapist.displayRate)
                        .font(.headline)
                    Text("per session")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    // TODO: Implement booking flow in Phase 2
                } label: {
                    Text("Book Session")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                }
            }
            .padding()
            .background(.ultraThinMaterial)
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

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    struct CacheData {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
    }

    func makeCache(subviews: Subviews) -> CacheData {
        CacheData()
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout CacheData) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        cache.size = result.size
        cache.positions = result.positions
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout CacheData) {
        // Use cached positions if available, otherwise recalculate
        let positions = cache.positions.isEmpty
            ? layout(proposal: proposal, subviews: subviews).positions
            : cache.positions

        for (index, position) in positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalHeight = max(totalHeight, currentY + lineHeight)
        }

        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}

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
