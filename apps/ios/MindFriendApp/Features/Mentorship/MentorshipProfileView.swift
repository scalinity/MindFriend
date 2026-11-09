import SwiftUI

/// View for editing user's mentorship profile
struct MentorshipProfileView: View {
    @EnvironmentObject var container: DependencyContainer

    @State private var isEditingProfile = false
    @State private var selectedExpertiseAreas: Set<String> = []
    @State private var selectedSeekingAreas: Set<String> = []
    @State private var bioText = ""
    @State private var availabilityHours = 5
    @State private var selectedLanguages: Set<String> = ["en"]

    private var profileService: MentorshipProfileService { container.mentorshipService.profileService }

    private let allTopics = [
        "anxiety",
        "depression",
        "stress",
        "sleep",
        "relationships",
        "work-life-balance",
        "self-esteem",
        "grief",
        "mindfulness",
        "coping-skills",
        "emotional-regulation",
        "career-guidance",
        "personal-growth",
        "trauma-recovery",
        "wellness",
    ]

    var body: some View {
        ZStack {
            SupportTheme.canvas.ignoresSafeArea()

            if let profile = profileService.profile {
                ScrollView {
                    VStack(spacing: SupportTheme.Spacing.l) {
                        // Header
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                            Text("Mentorship Profile")
                                .font(.title2)
                                .fontWeight(.bold)

                            Text(profile.isMentorAvailable ? "Available as mentor" : "Seeking mentor")
                                .font(.subheadline)
                                .foregroundColor(SupportTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                        // Mentor Toggle
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                            Label("Become a Mentor", systemImage: "person.badge.plus")
                                .font(.headline)

                            Toggle(
                                profile.isMentorAvailable ? "I'm available to mentor" : "Not available",
                                isOn: Binding(
                                    get: { profile.isMentorAvailable },
                                    set: { newValue in
                                        Task {
                                            await profileService.toggleMentorAvailability(newValue)
                                        }
                                    }
                                )
                            )
                            .tint(SupportTheme.accent)
                        }
                        .supportCard()
                        .padding(.horizontal)

                        if profile.isMentorAvailable {
                            // Mentor-specific sections
                            VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                                Label("Expertise Areas", systemImage: "star.fill")
                                    .font(.headline)
                                    .foregroundColor(SupportTheme.accent)

                                MentorshipFlowLayout(
                                    items: allTopics,
                                    selectedItems: $selectedExpertiseAreas
                                ) { topic, isSelected in
                                    TopicPill(
                                        text: topic,
                                        isSelected: isSelected,
                                        action: {
                                            if isSelected {
                                                selectedExpertiseAreas.remove(topic)
                                            } else {
                                                selectedExpertiseAreas.insert(topic)
                                            }
                                            Task {
                                                await profileService.updateExpertiseAreas(
                                                    Array(selectedExpertiseAreas)
                                                )
                                            }
                                        }
                                    )
                                }
                            }
                            .supportCard()
                            .padding(.horizontal)

                            VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                                Label("Availability", systemImage: "calendar")
                                    .font(.headline)

                                HStack {
                                    Slider(value: Binding(
                                        get: { Double(availabilityHours) },
                                        set: { availabilityHours = Int($0) }
                                    ), in: 1...168)

                                    Text("\(availabilityHours)h")
                                        .frame(minWidth: 40, alignment: .trailing)
                                        .fontWeight(.semibold)
                                }

                                Text("Hours per week you can mentor")
                                    .font(.caption)
                                    .foregroundColor(SupportTheme.textSecondary)
                            }
                            .supportCard()
                            .padding(.horizontal)
                            .onChange(of: availabilityHours) {
                                Task {
                                    await profileService.updateAvailabilityHours(availabilityHours)
                                }
                            }

                            VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                                Label("About You", systemImage: "text.alignleft")
                                    .font(.headline)

                                TextEditor(text: $bioText)
                                    .scrollContentBackground(.hidden)
                                    .supportField()
                                    .frame(height: 100)
                                    .padding(SupportTheme.Spacing.xs)
                                    .background(SupportTheme.surface)
                                    .cornerRadius(SupportTheme.controlRadius)
                                    .lineLimit(5)
                                    .onChange(of: bioText) {
                                        Task {
                                            await profileService.updateBio(bioText)
                                        }
                                    }

                                Text("\(bioText.count)/500")
                                    .font(.caption2)
                                    .foregroundColor(SupportTheme.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            .supportCard()
                            .padding(.horizontal)
                        }

                        // Seeking mentor section (always visible)
                        if !profile.isMentorAvailable || true {
                            VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                                Label("What You're Seeking", systemImage: "magnifyingglass")
                                    .font(.headline)
                                    .foregroundColor(SupportTheme.accent)

                                MentorshipFlowLayout(
                                    items: allTopics,
                                    selectedItems: $selectedSeekingAreas
                                ) { topic, isSelected in
                                    TopicPill(
                                        text: topic,
                                        isSelected: isSelected,
                                        isSecondary: true,
                                        action: {
                                            if isSelected {
                                                selectedSeekingAreas.remove(topic)
                                            } else {
                                                selectedSeekingAreas.insert(topic)
                                            }
                                            Task {
                                                await profileService.updateSeekingAreas(
                                                    Array(selectedSeekingAreas)
                                                )
                                            }
                                        }
                                    )
                                }
                            }
                            .supportCard()
                            .padding(.horizontal)
                        }

                        // Verification Badge
                        if profile.isVerified {
                            HStack(spacing: SupportTheme.Spacing.xs) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(SupportTheme.accent)

                                Text("Verified Mentor")
                                    .fontWeight(.semibold)

                                Spacer()
                            }
                            .supportCard()
                            .padding(.horizontal)
                        }

                        Spacer(minLength: 20)
                    }
                    .padding(.vertical)
                }
            } else {
                VStack(spacing: SupportTheme.Spacing.m) {
                    ProgressView()
                    Text("Loading profile...")
                        .foregroundColor(SupportTheme.textSecondary)
                }
            }
        }
        .foregroundStyle(SupportTheme.textPrimary)
        .supportScreen()
        .navigationTitle("Mentorship")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task {
                await profileService.loadProfile()
                if let profile = profileService.profile {
                    selectedExpertiseAreas = Set(profile.expertiseAreas)
                    selectedSeekingAreas = Set(profile.seekingAreas)
                    bioText = profile.bio ?? ""
                    availabilityHours = profile.availabilityHoursWeek
                    selectedLanguages = Set(profile.languages)
                }
            }
        }
    }
}

// MARK: - Topic Pill Component

struct TopicPill: View {
    let text: String
    let isSelected: Bool
    var isSecondary: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.callout)
                .background(
                    isSelected
                        ? (isSecondary ? SupportTheme.accent.opacity(0.2) : SupportTheme.accent.opacity(0.2))
                        : SupportTheme.field
                )
                .foregroundColor(
                    isSelected
                        ? (isSecondary ? SupportTheme.accent : SupportTheme.accent)
                        : SupportTheme.textPrimary
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                        .stroke(
                            isSelected ? (isSecondary ? SupportTheme.accent : SupportTheme.accent) : Color.clear,
                            lineWidth: 1.5
                        )
                )
        }
        .buttonStyle(.supportSecondary)
    }
}

// MARK: - Flow Layout

struct MentorshipFlowLayout<Item: Hashable, Content: View>: View {
    let items: [Item]
    @Binding var selectedItems: Set<Item>
    @ViewBuilder let content: (Item, Bool) -> Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: SupportTheme.Spacing.xs) {
            ForEach(items, id: \.self) { item in
                content(item, selectedItems.contains(item))
            }
        }
    }
}
