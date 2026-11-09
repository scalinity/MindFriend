// MoodEnergyPickerView.swift
// Inline picker for mood and energy when completing an experiment day

import SwiftUI

struct MoodEnergyPickerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var insightLabService: InsightLabService
    let experimentId: UUID
    let dayIndex: Int
    let onComplete: (Bool) -> Void

    @State private var selectedMood: Int = 3
    @State private var selectedEnergy: Int = 3
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: SupportTheme.Spacing.xl) {
                // Header
                VStack(spacing: SupportTheme.Spacing.xs) {
                    Text("Day \(dayIndex) Check-In")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Rate how you're feeling today")
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
                .padding(.top, SupportTheme.Spacing.m)

                // Mood picker
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
                    Text("How's your mood?")
                        .font(.headline)

                    MoodSlider(value: $selectedMood, label: "Mood")
                }
                .supportCard()

                // Energy picker
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
                    Text("How's your energy?")
                        .font(.headline)

                    EnergySlider(value: $selectedEnergy)
                }
                .supportCard()

                Spacer()

                // Action buttons
                VStack(spacing: SupportTheme.Spacing.s) {
                    // Submit button
                    Button {
                        Task {
                            await submitDay()
                        }
                    } label: {
                        HStack {
                            if isSubmitting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: SupportTheme.textPrimary))
                                    .scaleEffect(0.8)
                            }
                            Text(isSubmitting ? "Submitting..." : "Complete Day \(dayIndex)")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.supportPrimary)
                    .disabled(isSubmitting)

                    // Skip button
                    Button {
                        Task {
                            await submitDay(skipScores: true)
                        }
                    } label: {
                        Text("Skip Mood Rating")
                            .font(.subheadline)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                    .disabled(isSubmitting)
                }
            }
            .padding(SupportTheme.Spacing.m)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                        onComplete(false)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if errorMessage != nil {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                        if let error = errorMessage {
                            Text(error)
                        }

                        Button("OK") {
                            errorMessage = nil
                        }
                    }
                    .foregroundStyle(SupportTheme.textSecondary)
                    .buttonStyle(.supportSecondary)
                    .supportCard()
                    .padding(SupportTheme.Spacing.m)
                }
            }
        }
    }

    // MARK: - Actions

    private func submitDay(skipScores: Bool = false) async {
        isSubmitting = true
        errorMessage = nil

        do {
            let response = try await insightLabService.recordDay(
                experimentId: experimentId,
                dayIndex: dayIndex,
                moodScore: skipScores ? nil : selectedMood,
                energyScore: skipScores ? nil : selectedEnergy
            )

            dismiss()
            onComplete(response.success)
        } catch {
            errorMessage = "Failed to record day: \(error.localizedDescription)"
            isSubmitting = false
        }
    }
}

// MARK: - Mood Slider

struct MoodSlider: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var value: Int
    let label: String

    private let moods: [(emoji: String, label: String)] = [
        ("😔", "Very Low"),
        ("😕", "Low"),
        ("😐", "Okay"),
        ("🙂", "Good"),
        ("😄", "Great")
    ]

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.s) {
            // Emoji selector
            HStack(spacing: 0) {
                ForEach(1...5, id: \.self) { index in
                    Button {
                        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3)) {
                            value = index
                        }
                    } label: {
                        VStack(spacing: SupportTheme.Spacing.xxs) {
                            Text(moods[index - 1].emoji)
                                .font(.system(size: value == index ? 40 : 28))
                                .opacity(value == index ? 1 : 0.5)

                            if value == index {
                                Text(moods[index - 1].label)
                                    .font(.caption2)
                                    .foregroundStyle(SupportTheme.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(label), \(moods[index - 1].label)")
                    .accessibilityValue("\(index) of 5")
                    .accessibilityAddTraits(value == index ? .isSelected : [])
                }
            }

            // Selection indicator
            GeometryReader { geometry in
                let itemWidth = geometry.size.width / 5
                RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                    .fill(SupportTheme.accent)
                    .frame(width: itemWidth * 0.6, height: 3)
                    .offset(x: itemWidth * CGFloat(value - 1) + itemWidth * 0.2)
                    .animation(reduceMotion ? nil : .spring(response: 0.3), value: value)
            }
            .frame(height: 4)
        }
    }
}

// MARK: - Energy Slider

struct EnergySlider: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var value: Int

    private let levels: [(icon: String, label: String)] = [
        ("battery.0", "Exhausted"),
        ("battery.25", "Tired"),
        ("battery.50", "Moderate"),
        ("battery.75", "Good"),
        ("battery.100", "Energized")
    ]

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.s) {
            // Energy selector
            HStack(spacing: 0) {
                ForEach(1...5, id: \.self) { index in
                    Button {
                        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3)) {
                            value = index
                        }
                    } label: {
                        VStack(spacing: SupportTheme.Spacing.xxs) {
                            Image(systemName: levels[index - 1].icon)
                                .font(.system(size: value == index ? 28 : 22))
                                .foregroundStyle(energyColor(index))
                                .opacity(value == index ? 1 : 0.5)

                            if value == index {
                                Text(levels[index - 1].label)
                                    .font(.caption2)
                                    .foregroundStyle(SupportTheme.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Energy, \(levels[index - 1].label)")
                    .accessibilityValue("\(index) of 5")
                    .accessibilityAddTraits(value == index ? .isSelected : [])
                }
            }

            // Selection indicator
            GeometryReader { geometry in
                let itemWidth = geometry.size.width / 5
                RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                    .fill(energyColor(value))
                    .frame(width: itemWidth * 0.6, height: 3)
                    .offset(x: itemWidth * CGFloat(value - 1) + itemWidth * 0.2)
                    .animation(reduceMotion ? nil : .spring(response: 0.3), value: value)
            }
            .frame(height: 4)
        }
    }

    private func energyColor(_ level: Int) -> Color {
        switch level {
        case 1: return .red
        case 2: return SupportTheme.accent
        case 3: return SupportTheme.accent
        case 4: return SupportTheme.accent
        case 5: return SupportTheme.accent
        default: return SupportTheme.accent
        }
    }
}

#Preview {
    MoodEnergyPickerView(
        experimentId: UUID(),
        dayIndex: 1
    ) { _ in }
}
