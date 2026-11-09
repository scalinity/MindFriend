import SwiftUI

/// View for finding and requesting mentorship
struct FindMentorView: View {
    @Binding var navigationPath: [MentorshipNavigationDestination]
    @ObservedObject var matchingService: MentorshipMatchingService
    @State private var showingRequestSheet = false
    @State private var selectedMentor: FindMentorMatchesResponse.MentorMatch?
    @State private var introductionText = ""
    @State private var filterExpertise: String?
    @State private var sortBy: SortOption = .compatibility

    enum SortOption {
        case compatibility
        case availability
        case recent
    }

    var body: some View {
        ZStack {
            SupportTheme.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                // Search/Filter bar
                HStack(spacing: SupportTheme.Spacing.s) {
                    Menu {
                        Picker("Sort by", selection: $sortBy) {
                            Text("Best Match").tag(SortOption.compatibility)
                            Text("Most Available").tag(SortOption.availability)
                            Text("Recently Active").tag(SortOption.recent)
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                            .font(.subheadline)
                    }

                    Spacer()

                    Text("\(matchingService.mentorMatchCount) mentors")
                        .font(.subheadline)
                        .foregroundColor(SupportTheme.textSecondary)
                }
                .padding()
                .background(SupportTheme.surface)

                // Mentor list
                if matchingService.isLoading {
                    VStack(spacing: SupportTheme.Spacing.m) {
                        ProgressView()
                        Text("Finding mentors...")
                            .foregroundColor(SupportTheme.textSecondary)
                    }
                    .frame(maxHeight: .infinity)
                } else if matchingService.mentorMatches.isEmpty {
                    VStack(spacing: SupportTheme.Spacing.m) {
                        Image(systemName: "person.slash")
                            .font(.system(size: 48))
                            .foregroundColor(SupportTheme.textSecondary)

                        Text("No Mentors Found")
                            .font(.headline)

                        Text("Try adjusting your search criteria or check back later")
                            .font(.subheadline)
                            .foregroundColor(SupportTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxHeight: .infinity)
                    .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: SupportTheme.Spacing.s) {
                            ForEach(getSortedMentors()) { mentor in
                                MentorCard(
                                    mentor: mentor,
                                    action: {
                                        selectedMentor = mentor
                                        showingRequestSheet = true
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
        }
        .foregroundStyle(SupportTheme.textPrimary)
        .supportScreen()
        .navigationTitle("Find a Mentor")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let error = matchingService.error {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                    .supportCard()
                    .padding(SupportTheme.Spacing.m)
            }
        }
        .sheet(isPresented: $showingRequestSheet) {
            if let mentor = selectedMentor {
                RequestMentorshipSheet(
                    mentor: mentor,
                    introductionText: $introductionText,
                    isPresented: $showingRequestSheet,
                    onRequest: { message in
                        let matchId = try await matchingService.requestMentorship(
                            mentorId: mentor.mentorId,
                            introductionMessage: message
                        )
                        introductionText = ""
                        navigationPath.append(.matchDetails(matchId: matchId))
                    }
                )
            }
        }
        .onAppear {
            Task {
                await matchingService.findMentors()
            }
        }
    }

    private func getSortedMentors() -> [FindMentorMatchesResponse.MentorMatch] {
        switch sortBy {
        case .compatibility:
            return matchingService.sortedByCompatibility()
        case .availability:
            return matchingService.mentorMatches.sorted {
                $0.availabilityHoursWeek > $1.availabilityHoursWeek
            }
        case .recent:
            return matchingService.mentorMatches
        }
    }
}

// MARK: - Mentor Card

struct MentorCard: View {
    let mentor: FindMentorMatchesResponse.MentorMatch
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            // Header with name and score
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text(mentor.mentorName)
                        .font(.headline)

                    HStack(spacing: SupportTheme.Spacing.xxs) {
                        if mentor.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(SupportTheme.accent)
                                .font(.caption)
                        }

                        Text(mentor.timezone)
                            .font(.caption)
                            .foregroundColor(SupportTheme.textSecondary)
                    }
                }

                Spacer()

                // Compatibility score badge
                ZStack {
                    Circle()
                        .fill(compatibilityColor)
                        .opacity(0.2)

                    Text("\(Int(mentor.compatibilityScore * 100))%")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(compatibilityColor)
                }
                .frame(width: 50, height: 50)
            }

            // Expertise areas
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                Text("Expertise")
                    .font(.caption)
                    .foregroundColor(SupportTheme.textSecondary)

                FlowLayoutView(items: mentor.expertiseAreas) { expertise in
                    TagView(text: expertise, color: SupportTheme.accent)
                }
            }

            // Availability
            HStack(spacing: SupportTheme.Spacing.m) {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text("Available")
                        .font(.caption)
                        .foregroundColor(SupportTheme.textSecondary)
                    Text("\(mentor.availabilityHoursWeek)h/week")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }

                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text("Languages")
                        .font(.caption)
                        .foregroundColor(SupportTheme.textSecondary)
                    Text(mentor.languages.prefix(2).joined(separator: ", "))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }

                Spacer()
            }

            // Request button
            Button(action: action) {
                Text("Request Mentorship")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.supportPrimary)
        }
        .supportCard()
    }

    private var compatibilityColor: Color {
        let score = mentor.compatibilityScore
        if score >= 0.8 { return SupportTheme.accent }
        if score >= 0.6 { return SupportTheme.accent }
        if score >= 0.4 { return SupportTheme.accent }
        return .red
    }
}

// MARK: - Request Mentorship Sheet

struct RequestMentorshipSheet: View {
    let mentor: FindMentorMatchesResponse.MentorMatch
    @Binding var introductionText: String
    @Binding var isPresented: Bool
    let onRequest: (String) async throws -> Void
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: SupportTheme.Spacing.m) {
                // Mentor info
                HStack(spacing: SupportTheme.Spacing.s) {
                    VStack(alignment: .leading) {
                        Text(mentor.mentorName)
                            .font(.headline)

                        Text(mentor.timezone)
                            .font(.caption)
                            .foregroundColor(SupportTheme.textSecondary)
                    }

                    Spacer()

                    if mentor.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(SupportTheme.accent)
                    }
                }
                .supportCard()

                // Introduction text
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                    Text("Tell them about yourself")
                        .font(.headline)

                    TextEditor(text: $introductionText)
                        .scrollContentBackground(.hidden)
                        .supportField()
                        .frame(minHeight: 120)
                        .padding(SupportTheme.Spacing.xs)
                        .background(SupportTheme.surface)
                        .cornerRadius(SupportTheme.controlRadius)

                    Text("\(introductionText.count)/1000")
                        .font(.caption2)
                        .foregroundColor(SupportTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)

                    Text("Share what you're hoping to learn and why you think they'd be a good fit")
                        .font(.caption)
                        .foregroundColor(SupportTheme.textSecondary)
                }

                Spacer()

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.callout)
                }
                // Action buttons
                VStack(spacing: SupportTheme.Spacing.s) {
                    Button(action: {
                        isSending = true
                        errorMessage = nil
                        Task {
                            defer { isSending = false }
                            do {
                                try await onRequest(introductionText)
                                isPresented = false
                            } catch {
                                errorMessage = "Your request could not be confirmed. Please try again."
                            }
                        }
                    }) {
                        if isSending {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Send Request")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.supportPrimary)
                    .disabled(introductionText.trimmingCharacters(in: .whitespacesAndNewlines).count < 20 || introductionText.count > 1000 || isSending)

                    Button(action: { isPresented = false }) {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, SupportTheme.Spacing.s)
                            .background(SupportTheme.field)
                            .cornerRadius(SupportTheme.controlRadius)
                    }
                }
            }
            .padding()
            .interactiveDismissDisabled(isSending)
            .foregroundStyle(SupportTheme.textPrimary)
            .supportScreen()
            .navigationTitle("Request Mentorship")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Supporting Components

struct FlowLayoutView<Item, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {

            ForEach(items.indices, id: \.self) { index in
                let item = items[index]

                HStack(spacing: SupportTheme.Spacing.xs) {
                    content(item)
                }
            }
        }
    }
}

struct TagView: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, SupportTheme.Spacing.xs)
            .padding(.vertical, SupportTheme.Spacing.xxs)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(SupportTheme.controlRadius)
    }
}

