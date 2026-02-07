// MoodEnergyPickerView.swift
// Inline picker for mood and energy when completing an experiment day

import SwiftUI

struct MoodEnergyPickerView: View {
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
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 8) {
                    Text("Day \(dayIndex) Check-In")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Rate how you're feeling today")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top)

                // Mood picker
                VStack(alignment: .leading, spacing: 16) {
                    Text("How's your mood?")
                        .font(.headline)

                    MoodSlider(value: $selectedMood, label: "Mood")
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                // Energy picker
                VStack(alignment: .leading, spacing: 16) {
                    Text("How's your energy?")
                        .font(.headline)

                    EnergySlider(value: $selectedEnergy)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                Spacer()

                // Action buttons
                VStack(spacing: 12) {
                    // Submit button
                    Button {
                        Task {
                            await submitDay()
                        }
                    } label: {
                        HStack {
                            if isSubmitting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            Text(isSubmitting ? "Submitting..." : "Complete Day \(dayIndex)")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isSubmitting)

                    // Skip button
                    Button {
                        Task {
                            await submitDay(skipScores: true)
                        }
                    } label: {
                        Text("Skip Mood Rating")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .disabled(isSubmitting)
                }
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                        onComplete(false)
                    }
                }
            }
            .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                if let error = errorMessage {
                    Text(error)
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
        VStack(spacing: 12) {
            // Emoji selector
            HStack(spacing: 0) {
                ForEach(1...5, id: \.self) { index in
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            value = index
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text(moods[index - 1].emoji)
                                .font(.system(size: value == index ? 40 : 28))
                                .opacity(value == index ? 1 : 0.5)

                            if value == index {
                                Text(moods[index - 1].label)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Selection indicator
            GeometryReader { geometry in
                let itemWidth = geometry.size.width / 5
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: itemWidth * 0.6, height: 3)
                    .offset(x: itemWidth * CGFloat(value - 1) + itemWidth * 0.2)
                    .animation(.spring(response: 0.3), value: value)
            }
            .frame(height: 4)
        }
    }
}

// MARK: - Energy Slider

struct EnergySlider: View {
    @Binding var value: Int

    private let levels: [(icon: String, label: String)] = [
        ("battery.0", "Exhausted"),
        ("battery.25", "Tired"),
        ("battery.50", "Moderate"),
        ("battery.75", "Good"),
        ("battery.100", "Energized")
    ]

    var body: some View {
        VStack(spacing: 12) {
            // Energy selector
            HStack(spacing: 0) {
                ForEach(1...5, id: \.self) { index in
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            value = index
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: levels[index - 1].icon)
                                .font(.system(size: value == index ? 28 : 22))
                                .foregroundStyle(energyColor(index))
                                .opacity(value == index ? 1 : 0.5)

                            if value == index {
                                Text(levels[index - 1].label)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Selection indicator
            GeometryReader { geometry in
                let itemWidth = geometry.size.width / 5
                RoundedRectangle(cornerRadius: 2)
                    .fill(energyColor(value))
                    .frame(width: itemWidth * 0.6, height: 3)
                    .offset(x: itemWidth * CGFloat(value - 1) + itemWidth * 0.2)
                    .animation(.spring(response: 0.3), value: value)
            }
            .frame(height: 4)
        }
    }

    private func energyColor(_ level: Int) -> Color {
        switch level {
        case 1: return .red
        case 2: return .orange
        case 3: return .yellow
        case 4: return .green
        case 5: return .green
        default: return .gray
        }
    }
}

#Preview {
    MoodEnergyPickerView(
        experimentId: UUID(),
        dayIndex: 1
    ) { _ in }
}
