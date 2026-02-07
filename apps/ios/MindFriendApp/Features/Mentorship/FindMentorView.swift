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
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                // Search/Filter bar
                HStack(spacing: 12) {
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
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemBackground))

                // Mentor list
                if matchingService.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Finding mentors...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                } else if matchingService.mentorMatches.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)

                        Text("No Mentors Found")
                            .font(.headline)

                        Text("Try adjusting your search criteria or check back later")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxHeight: .infinity)
                    .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
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
        .navigationTitle("Find a Mentor")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingRequestSheet) {
            if let mentor = selectedMentor {
                RequestMentorshipSheet(
                    mentor: mentor,
                    introductionText: $introductionText,
                    isPresented: $showingRequestSheet,
                    onRequest: { message in
                        Task {
                            await matchingService.requestMentorship(
                                mentorId: mentor.id,
                                introductionMessage: message
                            )
                            showingRequestSheet = false
                            introductionText = ""
                            
                            // Navigate to the newly created match after a brief delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                if let newMatch = matchingService.pendingRequests.first {
                                    navigationPath.append(.chat(matchId: newMatch.id))
                                }
                            }
                        }
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
        VStack(alignment: .leading, spacing: 12) {
            // Header with name and score
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(mentor.mentorName)
                        .font(.headline)

                    HStack(spacing: 4) {
                        if mentor.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        }

                        Text(mentor.timezone)
                            .font(.caption)
                            .foregroundColor(.secondary)
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
            VStack(alignment: .leading, spacing: 6) {
                Text("Expertise")
                    .font(.caption)
                    .foregroundColor(.secondary)

                FlowLayoutView(items: mentor.expertiseAreas) { expertise in
                    TagView(text: expertise, color: .blue)
                }
            }

            // Availability
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(mentor.availabilityHoursWeek)h/week")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Languages")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var compatibilityColor: Color {
        let score = mentor.compatibilityScore
        if score >= 0.8 { return .green }
        if score >= 0.6 { return .blue }
        if score >= 0.4 { return .orange }
        return .red
    }
}

// MARK: - Request Mentorship Sheet

struct RequestMentorshipSheet: View {
    let mentor: FindMentorMatchesResponse.MentorMatch
    @Binding var introductionText: String
    @Binding var isPresented: Bool
    let onRequest: (String) -> Void
    @State private var isSending = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Mentor info
                HStack(spacing: 12) {
                    VStack(alignment: .leading) {
                        Text(mentor.mentorName)
                            .font(.headline)

                        Text(mentor.timezone)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if mentor.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)

                // Introduction text
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tell them about yourself")
                        .font(.headline)

                    TextEditor(text: $introductionText)
                        .frame(minHeight: 120)
                        .padding(8)
                        .background(Color(.tertiarySystemBackground))
                        .cornerRadius(8)

                    Text("\(introductionText.count)/500")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)

                    Text("Share what you're hoping to learn and why you think they'd be a good fit")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Action buttons
                VStack(spacing: 12) {
                    Button(action: {
                        isSending = true
                        onRequest(introductionText)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            isPresented = false
                        }
                    }) {
                        if isSending {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        } else {
                            Text("Send Request")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                    .disabled(introductionText.count < 10 || introductionText.count > 500 || isSending)

                    Button(action: { isPresented = false }) {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(.quaternarySystemFill))
                            .cornerRadius(8)
                    }
                }
            }
            .padding()
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
        VStack(alignment: .leading, spacing: 6) {

            ForEach(items.indices, id: \.self) { index in
                let item = items[index]

                HStack(spacing: 6) {
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
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(6)
    }
}

