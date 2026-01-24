import SwiftUI
import Supabase

/// View for managing mentorship profile settings
struct MentorshipProfileView: View {
    @StateObject private var service: MentorshipService
    @Environment(\.dismiss) private var dismiss

    @State private var isMentorAvailable = false
    @State private var selectedExpertise: Set<String> = []
    @State private var selectedSeeking: Set<String> = []
    @State private var bio = ""
    @State private var availabilityHours = 2
    @State private var selectedStyle: DBMentorshipProfile.MentorshipStyle = .supportive
    @State private var isSaving = false
    @State private var showSuccess = false
    @State private var errorMessage: String?

    init(supabase: SupabaseClient) {
        _service = StateObject(wrappedValue: MentorshipService(supabase: supabase))
    }

    var body: some View {
        NavigationStack {
            Form {
                // Mentor Toggle Section
                Section {
                    Toggle("Available as Mentor", isOn: $isMentorAvailable)
                        .tint(.green)
                } header: {
                    Text("Mentor Status")
                } footer: {
                    Text("When enabled, others can find and request you as a mentor.")
                }

                // Expertise Section (for mentors)
                if isMentorAvailable {
                    Section {
                        ForEach(MentorshipExpertiseArea.allCases) { area in
                            MultiSelectRow(
                                title: area.displayName,
                                icon: area.icon,
                                isSelected: selectedExpertise.contains(area.rawValue)
                            ) {
                                toggleExpertise(area.rawValue)
                            }
                        }
                    } header: {
                        Text("Your Expertise")
                    } footer: {
                        Text("Select areas where you have experience and can offer guidance.")
                    }
                }

                // Seeking Section (for mentees)
                Section {
                    ForEach(MentorshipExpertiseArea.allCases) { area in
                        MultiSelectRow(
                            title: area.displayName,
                            icon: area.icon,
                            isSelected: selectedSeeking.contains(area.rawValue)
                        ) {
                            toggleSeeking(area.rawValue)
                        }
                    }
                } header: {
                    Text("Areas You're Seeking Help")
                } footer: {
                    Text("Select areas where you'd like mentor support.")
                }

                // Bio Section
                Section {
                    TextEditor(text: $bio)
                        .frame(minHeight: 100)
                } header: {
                    Text("Bio")
                } footer: {
                    Text("Share a bit about yourself and your journey. This helps potential mentees or mentors connect with you.")
                }

                // Mentor Settings (only shown if mentor)
                if isMentorAvailable {
                    Section {
                        Stepper(
                            "Hours per week: \(availabilityHours)",
                            value: $availabilityHours,
                            in: 1...20
                        )

                        Picker("Mentorship Style", selection: $selectedStyle) {
                            ForEach(DBMentorshipProfile.MentorshipStyle.allCases, id: \.self) { style in
                                Text(style.displayName).tag(style)
                            }
                        }
                    } header: {
                        Text("Mentor Preferences")
                    } footer: {
                        Text("Your style preference helps match you with compatible mentees.")
                    }
                }

                // Save Button
                Section {
                    Button {
                        Task { await saveProfile() }
                    } label: {
                        HStack {
                            Spacer()
                            if isSaving {
                                ProgressView()
                            } else {
                                Text("Save Profile")
                            }
                            Spacer()
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .navigationTitle("Mentorship Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Profile Saved", isPresented: $showSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("Your mentorship profile has been updated.")
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
            .task {
                await loadProfile()
            }
        }
    }

    // MARK: - Private Methods

    private func loadProfile() async {
        do {
            if let profile = try await service.fetchProfile() {
                isMentorAvailable = profile.isMentorAvailable
                selectedExpertise = Set(profile.expertiseAreas)
                selectedSeeking = Set(profile.seekingAreas)
                bio = profile.bio ?? ""
                availabilityHours = profile.availabilityHoursWeek
                selectedStyle = profile.mentorshipStyle
            }
        } catch {
            Log.social.error("Failed to load mentorship profile", error: error)
        }
    }

    private func saveProfile() async {
        isSaving = true
        defer { isSaving = false }

        do {
            _ = try await service.upsertProfile(
                isMentorAvailable: isMentorAvailable,
                expertiseAreas: Array(selectedExpertise),
                seekingAreas: Array(selectedSeeking),
                bio: bio.isEmpty ? nil : bio,
                availabilityHoursWeek: availabilityHours,
                mentorshipStyle: selectedStyle
            )
            showSuccess = true
        } catch {
            errorMessage = error.localizedDescription
            Log.social.error("Failed to save mentorship profile", error: error)
        }
    }

    private func toggleExpertise(_ area: String) {
        if selectedExpertise.contains(area) {
            selectedExpertise.remove(area)
        } else {
            selectedExpertise.insert(area)
        }
    }

    private func toggleSeeking(_ area: String) {
        if selectedSeeking.contains(area) {
            selectedSeeking.remove(area)
        } else {
            selectedSeeking.insert(area)
        }
    }
}

// MARK: - Supporting Views

private struct MultiSelectRow: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                Text(title)
                    .foregroundStyle(.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(isSelected ? "selected" : "not selected")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    MentorshipProfileView(supabase: DependencyContainer.preview.supabase)
}
