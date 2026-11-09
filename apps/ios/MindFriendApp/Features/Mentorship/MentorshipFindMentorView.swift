import SwiftUI
import Supabase

/// View for finding and browsing compatible mentors
struct MentorshipFindMentorView: View {
    @StateObject private var service: MentorshipService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedAreas: Set<String> = []
    @State private var mentorMatches: [MentorMatchResult] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var selectedMentor: MentorMatchResult?
    @State private var showRequestSheet = false
    @State private var errorMessage: String?

    init(supabase: SupabaseClient) {
        _service = StateObject(wrappedValue: MentorshipService(supabase: supabase))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SupportTheme.Spacing.l) {
                    // Area Selection
                    areaSelectionSection

                    // Search Button
                    searchButton

                    // Results
                    if hasSearched {
                        resultsSection
                    }
                }
                .padding()
            }
            .foregroundStyle(SupportTheme.textPrimary)
            .supportScreen()
            .navigationTitle("Find a Mentor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showRequestSheet) {
                if let mentor = selectedMentor {
                    RequestMentorshipSheet(mentor: mentor, service: service) { success in
                        showRequestSheet = false
                        if success {
                            dismiss()
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let errorMessage {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                        Button("OK") { self.errorMessage = nil }
                            .buttonStyle(.supportSecondary)
                    }
                    .supportCard()
                    .padding(SupportTheme.Spacing.m)
                }
            }
            .task {
                // Load user's seeking areas from profile
                await loadProfile()
            }
        }
    }

    // MARK: - Sections

    private var areaSelectionSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("What areas would you like help with?")
                .font(.headline)

            FlowLayout(spacing: SupportTheme.Spacing.xs) {
                ForEach(MentorshipExpertiseArea.allCases) { area in
                    AreaChip(
                        title: area.displayName,
                        icon: area.icon,
                        isSelected: selectedAreas.contains(area.rawValue)
                    ) {
                        toggleArea(area.rawValue)
                    }
                }
            }
        }
    }

    private var searchButton: some View {
        Button {
            Task { await searchMentors() }
        } label: {
            HStack {
                if isSearching {
                    ProgressView()
                        .tint(SupportTheme.textPrimary)
                } else {
                    Image(systemName: "magnifyingglass")
                }
                Text(isSearching ? "Searching..." : "Find Mentors")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.supportPrimary)
        .controlSize(.large)
        .disabled(selectedAreas.isEmpty || isSearching)
    }

    @ViewBuilder
    private var resultsSection: some View {
        if mentorMatches.isEmpty {
            ContentUnavailableView(
                "No Mentors Found",
                systemImage: "person.2.slash",
                description: Text("Try selecting different areas or check back later.")
            )
        } else {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
                Text("Matched Mentors")
                    .font(.headline)

                ForEach(mentorMatches) { mentor in
                    MentorCard(mentor: mentor) {
                        selectedMentor = mentor
                        showRequestSheet = true
                    }
                }
            }
        }
    }

    // MARK: - Private Methods

    private func loadProfile() async {
        do {
            if let profile = try await service.fetchProfile() {
                selectedAreas = Set(profile.seekingAreas)
            }
        } catch {
            Log.social.error("Failed to load profile", error: error)
        }
    }

    private func toggleArea(_ area: String) {
        if selectedAreas.contains(area) {
            selectedAreas.remove(area)
        } else {
            selectedAreas.insert(area)
        }
    }

    private func searchMentors() async {
        guard !selectedAreas.isEmpty else { return }

        isSearching = true
        hasSearched = true
        defer { isSearching = false }

        do {
            mentorMatches = try await service.findMentorMatches(
                seekingAreas: Array(selectedAreas),
                limit: 5
            )
        } catch {
            errorMessage = "Unable to find mentors. Please try again."
            Log.social.error("Failed to find mentors", error: error)
        }
    }
}

// MARK: - Supporting Views

private struct AreaChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SupportTheme.Spacing.xxs) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.subheadline)
            }
            .padding(.horizontal, SupportTheme.Spacing.s)
            .padding(.vertical, SupportTheme.Spacing.xs)
            .background(isSelected ? SupportTheme.accent : SupportTheme.textSecondary.opacity(0.15))
            .foregroundStyle(isSelected ? SupportTheme.onAccent : SupportTheme.textPrimary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct MentorCard: View {
    let mentor: MentorMatchResult
    let onRequest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            // Header
            HStack {
                // Avatar placeholder
                Circle()
                    .fill(SupportTheme.accent.opacity(0.2))
                    .frame(width: 50, height: 50)
                    .overlay {
                        Image(systemName: "person.fill")
                            .foregroundStyle(SupportTheme.accent)
                    }

                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    HStack {
                        Text(mentor.styleEnum.displayName)
                            .font(.subheadline.bold())

                        Spacer()

                        // Compatibility Score
                        HStack(spacing: SupportTheme.Spacing.xxs) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(SupportTheme.Celebration.gold)
                            Text("\(mentor.compatibilityPercentage)%")
                                .font(.subheadline.bold())
                        }
                    }

                    HStack(spacing: SupportTheme.Spacing.xs) {
                        if let rating = mentor.avgRating {
                            Label(String(format: "%.1f", rating), systemImage: "star.fill")
                                .font(.caption)
                                .foregroundStyle(SupportTheme.textSecondary)
                        }

                        Text("\(mentor.totalMentorships) mentorships")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                }
            }

            // Match Reason
            Text(mentor.matchReason)
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)

            // Expertise Tags
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SupportTheme.Spacing.xs) {
                    ForEach(mentor.expertiseAreas.prefix(4), id: \.self) { area in
                        Text(formatAreaName(area))
                            .font(.caption2)
                            .padding(.horizontal, SupportTheme.Spacing.xs)
                            .padding(.vertical, SupportTheme.Spacing.xxs)
                            .background(SupportTheme.surface)
                            .foregroundStyle(SupportTheme.accent)
                            .clipShape(Capsule())
                    }
                }
            }

            // Bio
            if let bio = mentor.bio, !bio.isEmpty {
                Text(bio)
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .lineLimit(2)
            }

            // Request Button
            Button("Request Mentorship", action: onRequest)
                .buttonStyle(.supportPrimary)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
        }
        .padding()
        .background(SupportTheme.surface, in: RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
        .accessibilityElement(children: .contain)
    }

    private func formatAreaName(_ area: String) -> String {
        MentorshipExpertiseArea(rawValue: area)?.displayName ?? area.capitalized
    }
}

// MARK: - Request Sheet

private struct RequestMentorshipSheet: View {
    let mentor: MentorMatchResult
    let service: MentorshipService
    let onComplete: (Bool) -> Void

    @State private var introMessage = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Circle()
                            .fill(SupportTheme.accent.opacity(0.2))
                            .frame(width: 40, height: 40)
                            .overlay {
                                Image(systemName: "person.fill")
                                    .foregroundStyle(SupportTheme.accent)
                            }

                        VStack(alignment: .leading) {
                            Text(mentor.styleEnum.displayName)
                                .font(.subheadline.bold())
                            Text(mentor.matchReason)
                                .font(.caption)
                                .foregroundStyle(SupportTheme.textSecondary)
                        }
                    }
                } header: {
                    Text("Mentor")
                }
                .listRowBackground(SupportTheme.surface)

                Section {
                    TextEditor(text: $introMessage)
                        .scrollContentBackground(.hidden)
                        .supportField()
                        .frame(minHeight: 120)
                } header: {
                    Text("Introduction Message")
                } footer: {
                    Text("Write a brief message introducing yourself and what you're hoping to get from this mentorship. Minimum 20 characters.")
                }
                .listRowBackground(SupportTheme.surface)

                Section {
                    Button {
                        Task { await submitRequest() }
                    } label: {
                        HStack {
                            Spacer()
                            if isSubmitting {
                                ProgressView()
                            } else {
                                Text("Send Request")
                            }
                            Spacer()
                        }
                    }
                    .disabled(introMessage.count < 20 || isSubmitting)
                }
                .listRowBackground(SupportTheme.surface)
            }
            .foregroundStyle(SupportTheme.textPrimary)
            .supportScreen()
            .navigationTitle("Request Mentorship")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onComplete(false)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let errorMessage {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                        Button("OK") { self.errorMessage = nil }
                            .buttonStyle(.supportSecondary)
                    }
                    .supportCard()
                    .padding(SupportTheme.Spacing.m)
                }
            }
        }
    }

    private func submitRequest() async {
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let response = try await service.requestMentorship(
                mentorId: mentor.mentorUserId,
                introductionMessage: introMessage
            )

            if response.success {
                onComplete(true)
            } else {
                errorMessage = response.message
            }
        } catch {
            errorMessage = error.localizedDescription
            Log.social.error("Failed to request mentorship", error: error)
        }
    }
}

#Preview {
    MentorshipFindMentorView(supabase: DependencyContainer.preview.supabase)
}
