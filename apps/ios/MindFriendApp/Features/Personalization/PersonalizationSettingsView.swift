// PersonalizationSettingsView.swift
// Smart Personalization: User preference settings

import SwiftUI

struct PersonalizationSettingsView: View {
    @EnvironmentObject private var container: DependencyContainer

    private var personalizationService: PersonalizationService {
        container.personalizationService
    }

    var body: some View {
        List {
            Section {
                preferencesSection
            } header: {
                Text("Your Preferences")
            } footer: {
                Text("These help us suggest content you'll love.")
            }

            Section {
                schedulingSection
            } header: {
                Text("Scheduling")
            }

            Section {
                featureTogglesSection
            } header: {
                Text("Smart Features")
            } footer: {
                Text("Turn these off if you prefer a more manual experience.")
            }

            if !personalizationService.learnedPreferences.isEmpty {
                Section {
                    learnedPreferencesSection
                } header: {
                    Text("What We've Learned")
                } footer: {
                    Text("Based on your usage patterns. Updates automatically.")
                }
            }
        }
        .navigationTitle("Personalization")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await personalizationService.loadData()
        }
    }

    // MARK: - Preferences Section

    @ViewBuilder
    private var preferencesSection: some View {
        if let profile = personalizationService.preferenceProfile {
            // Session Length
            Picker("Session Length", selection: sessionLengthBinding(profile)) {
                ForEach(SessionLength.allCases, id: \.self) { length in
                    Text(length.displayName).tag(length)
                }
            }
            .accessibilityHint("Choose your preferred session duration")

            // Content Types
            NavigationLink {
                ContentTypePickerView(
                    selectedTypes: contentTypesBinding(profile)
                )
            } label: {
                HStack {
                    Text("Content Types")
                    Spacer()
                    Text(profile.preferredContentTypes.map { $0.displayName }.joined(separator: ", "))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            // Categories
            NavigationLink {
                CategoryPickerView(
                    selectedCategories: categoriesBinding(profile)
                )
            } label: {
                HStack {
                    Text("Favorite Categories")
                    Spacer()
                    if profile.preferredCategories.isEmpty {
                        Text("None selected")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(profile.preferredCategories.count) selected")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Voice Gender
            Picker("Voice Preference", selection: voiceGenderBinding(profile)) {
                ForEach(VoiceGender.allCases, id: \.self) { gender in
                    Text(gender.displayName).tag(gender)
                }
            }

            // Background Sound
            Picker("Background Sound", selection: backgroundSoundBinding(profile)) {
                ForEach(BackgroundSound.allCases, id: \.self) { sound in
                    Text(sound.displayName).tag(sound)
                }
            }

            // Difficulty
            Picker("Difficulty", selection: difficultyBinding(profile)) {
                ForEach(DifficultyPreference.allCases, id: \.self) { diff in
                    Text(diff.displayName).tag(diff)
                }
            }
        } else {
            ProgressView()
        }
    }

    // MARK: - Scheduling Section

    @ViewBuilder
    private var schedulingSection: some View {
        if let profile = personalizationService.preferenceProfile {
            Picker("Reminders", selection: reminderFrequencyBinding(profile)) {
                ForEach(ReminderFrequency.allCases, id: \.self) { freq in
                    Text(freq.displayName).tag(freq)
                }
            }

            NavigationLink {
                SmartQuietHoursView()
                    .environmentObject(container)
            } label: {
                HStack {
                    Text("Quiet Hours")
                    Spacer()
                    Text("\(profile.quietHoursStart) - \(profile.quietHoursEnd)")
                        .foregroundStyle(.secondary)
                }
            }

            if !personalizationService.scheduleSuggestions.isEmpty {
                NavigationLink {
                    ScheduleSuggestionsView()
                        .environmentObject(container)
                } label: {
                    HStack {
                        Text("Schedule Suggestions")
                        Spacer()
                        CountBadge(count: personalizationService.scheduleSuggestions.count)
                    }
                }
            }
        }
    }

    // MARK: - Feature Toggles Section

    @ViewBuilder
    private var featureTogglesSection: some View {
        if let profile = personalizationService.preferenceProfile {
            Toggle("Mood-Based Recommendations", isOn: moodBasedBinding(profile))
                .accessibilityHint("When enabled, recommendations will adapt to your current mood")

            Toggle("Personalized Insights", isOn: insightsBinding(profile))
                .accessibilityHint("When enabled, you'll receive insights about your patterns")

            Toggle("Smart Scheduling", isOn: schedulingToggleBinding(profile))
                .accessibilityHint("When enabled, we'll suggest optimal times for activities")

            Toggle("Adaptive Difficulty", isOn: difficultyToggleBinding(profile))
                .accessibilityHint("When enabled, difficulty adjusts based on your progress")
        }
    }

    // MARK: - Learned Preferences Section

    @ViewBuilder
    private var learnedPreferencesSection: some View {
        ForEach(personalizationService.learnedPreferences.prefix(5)) { pref in
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pref.displayName)
                        .font(.subheadline)
                    Text(pref.preferenceType.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    ConfidenceIndicator(confidence: pref.confidenceScore)
                    Text("\(Int(pref.preferenceScore * 100))% match")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Bindings

    private func sessionLengthBinding(_ profile: UserPreferenceProfile) -> Binding<SessionLength> {
        Binding(
            get: { profile.preferredSessionLength },
            set: { newValue in
                Task {
                    try? await personalizationService.updateSessionLengthPreference(newValue)
                }
            }
        )
    }

    private func contentTypesBinding(_ profile: UserPreferenceProfile) -> Binding<Set<PersonalizationContentType>> {
        Binding(
            get: { Set(profile.preferredContentTypes) },
            set: { newTypes in
                Task {
                    try? await personalizationService.updateContentTypePreferences(Array(newTypes))
                }
            }
        )
    }

    private func categoriesBinding(_ profile: UserPreferenceProfile) -> Binding<Set<String>> {
        Binding(
            get: { Set(profile.preferredCategories) },
            set: { newCategories in
                Task {
                    try? await personalizationService.updateCategoryPreferences(Array(newCategories))
                }
            }
        )
    }

    private func voiceGenderBinding(_ profile: UserPreferenceProfile) -> Binding<VoiceGender> {
        Binding(
            get: { profile.preferredVoiceGender ?? .noPreference },
            set: { newValue in
                Task {
                    var updated = profile
                    updated.preferredVoiceGender = newValue
                    try? await personalizationService.updatePreferenceProfile(updated)
                }
            }
        )
    }

    private func backgroundSoundBinding(_ profile: UserPreferenceProfile) -> Binding<BackgroundSound> {
        Binding(
            get: { profile.backgroundSoundPreference },
            set: { newValue in
                Task {
                    var updated = profile
                    updated.backgroundSoundPreference = newValue
                    try? await personalizationService.updatePreferenceProfile(updated)
                }
            }
        )
    }

    private func difficultyBinding(_ profile: UserPreferenceProfile) -> Binding<DifficultyPreference> {
        Binding(
            get: { profile.difficultyPreference },
            set: { newValue in
                Task {
                    var updated = profile
                    updated.difficultyPreference = newValue
                    try? await personalizationService.updatePreferenceProfile(updated)
                }
            }
        )
    }

    private func reminderFrequencyBinding(_ profile: UserPreferenceProfile) -> Binding<ReminderFrequency> {
        Binding(
            get: { profile.reminderFrequency },
            set: { newValue in
                Task {
                    var updated = profile
                    updated.reminderFrequency = newValue
                    try? await personalizationService.updatePreferenceProfile(updated)
                }
            }
        )
    }

    private func moodBasedBinding(_ profile: UserPreferenceProfile) -> Binding<Bool> {
        Binding(
            get: { profile.moodBasedRecommendations },
            set: { newValue in
                Task {
                    try? await personalizationService.updateFeatureToggle(moodBased: newValue)
                }
            }
        )
    }

    private func insightsBinding(_ profile: UserPreferenceProfile) -> Binding<Bool> {
        Binding(
            get: { profile.personalizedInsights },
            set: { newValue in
                Task {
                    try? await personalizationService.updateFeatureToggle(insights: newValue)
                }
            }
        )
    }

    private func schedulingToggleBinding(_ profile: UserPreferenceProfile) -> Binding<Bool> {
        Binding(
            get: { profile.smartScheduling },
            set: { newValue in
                Task {
                    try? await personalizationService.updateFeatureToggle(scheduling: newValue)
                }
            }
        )
    }

    private func difficultyToggleBinding(_ profile: UserPreferenceProfile) -> Binding<Bool> {
        Binding(
            get: { profile.adaptiveDifficulty },
            set: { newValue in
                Task {
                    try? await personalizationService.updateFeatureToggle(difficulty: newValue)
                }
            }
        )
    }
}

// MARK: - Count Badge

struct CountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.red)
            .clipShape(Capsule())
    }
}

#Preview {
    NavigationStack {
        PersonalizationSettingsView()
            .environmentObject(DependencyContainer())
    }
}
