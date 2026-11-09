// ScheduleSuggestionsView.swift
// Smart Personalization: Display and manage schedule suggestions

import SwiftUI

struct ScheduleSuggestionsView: View {
    @EnvironmentObject private var container: DependencyContainer

    private var personalizationService: PersonalizationService {
        container.personalizationService
    }

    var body: some View {
        List {
            if personalizationService.scheduleSuggestions.isEmpty {
                Section {
                    VStack(spacing: SupportTheme.Spacing.m) {
                        Image(systemName: "clock.badge.questionmark")
                            .font(.system(.largeTitle))
                            .foregroundStyle(SupportTheme.textSecondary)

                        Text("No Schedule Suggestions")
                            .font(.headline)

                        Text("Keep using the app and we'll learn your patterns to suggest optimal times for activities.")
                            .font(.subheadline)
                            .foregroundStyle(SupportTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SupportTheme.Spacing.xl)
                }
            } else {
                Section {
                    ForEach(personalizationService.scheduleSuggestions) { suggestion in
                        ScheduleSuggestionRow(suggestion: suggestion)
                            .environmentObject(container)
                    }
                } footer: {
                    Text("These suggestions are based on \(totalSessions) sessions you've completed.")
                }
            }
        }
        .supportScreen()
        .navigationTitle("Schedule Suggestions")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await personalizationService.loadScheduleSuggestions()
        }
    }

    private var totalSessions: Int {
        personalizationService.scheduleSuggestions.reduce(0) { $0 + $1.basedOnSessions }
    }
}

// MARK: - Schedule Suggestion Row

struct ScheduleSuggestionRow: View {
    let suggestion: DBScheduleSuggestion
    @EnvironmentObject private var container: DependencyContainer
    @State private var isProcessing = false

    private var personalizationService: PersonalizationService {
        container.personalizationService
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            HStack {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text(suggestion.suggestedTime)
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(suggestion.formattedDays)
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: SupportTheme.Spacing.xxs) {
                    Text("\(Int(suggestion.confidenceScore * 100))%")
                        .font(.headline)
                        .foregroundStyle(confidenceColor)

                    Text("confidence")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
            }

            Text(suggestion.reasoning)
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)

            HStack(spacing: SupportTheme.Spacing.s) {
                Button {
                    acceptSuggestion()
                } label: {
                    if isProcessing {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Accept")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.supportPrimary)
                .disabled(isProcessing)

                Button {
                    rejectSuggestion()
                } label: {
                    Text("Dismiss")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.supportSecondary)
                .disabled(isProcessing)
            }
        }
        .padding(.vertical, SupportTheme.Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Suggestion: \(suggestion.activityType) at \(suggestion.suggestedTime) on \(suggestion.formattedDays). \(suggestion.reasoning)")
    }

    private var confidenceColor: Color {
        if suggestion.confidenceScore >= 0.8 { return SupportTheme.accent }
        if suggestion.confidenceScore >= 0.5 { return SupportTheme.accent }
        return SupportTheme.accent
    }

    private func acceptSuggestion() {
        isProcessing = true
        Task {
            try? await personalizationService.acceptScheduleSuggestion(suggestion)
            isProcessing = false
        }
    }

    private func rejectSuggestion() {
        isProcessing = true
        Task {
            try? await personalizationService.rejectScheduleSuggestion(suggestion)
            isProcessing = false
        }
    }
}

#Preview {
    NavigationStack {
        ScheduleSuggestionsView()
            .environmentObject(DependencyContainer())
    }
}
