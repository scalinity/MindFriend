// ExperimentProgressView.swift
// Shows daily check-in for active experiment

import SwiftUI

struct ExperimentProgressView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var insightLabService: InsightLabService
    @State private var showingMoodPicker = false
    @State private var showingCancelConfirmation = false
    @State private var showingReport = false
    @State private var selectedDayIndex: Int?
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let experiment = insightLabService.activeExperiment {
                let _ = print("[ExperimentProgressView] Rendering with experiment: \(experiment.title), days: \(experiment.days.count)")
                ScrollView {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.l) {
                        // Progress header
                        progressHeader(experiment)

                        // Today's action card
                        if experiment.status == .active {
                            todayActionCard(experiment)
                        }

                        // Day progress grid
                        dayProgressGrid(experiment)

                        // Cancel button
                        if experiment.status == .active {
                            cancelButton
                        }
                    }
                    .padding(SupportTheme.Spacing.m)
                }
                .supportScreen()
                .navigationTitle(experiment.title)
                .navigationBarTitleDisplayMode(.inline)
            } else {
                let _ = print("[ExperimentProgressView] ERROR: No active experiment available!")
                ContentUnavailableView(
                    "No Active Experiment",
                    systemImage: "flask",
                    description: Text("Start an experiment from the catalog to begin tracking.")
                )
            }
        }
        .sheet(isPresented: $showingMoodPicker) {
            if let dayIndex = selectedDayIndex,
               let experiment = insightLabService.activeExperiment {
                MoodEnergyPickerView(
                    experimentId: experiment.id,
                    dayIndex: dayIndex
                ) { success in
                    showingMoodPicker = false
                    selectedDayIndex = nil
                    if success && dayIndex == 7 {
                        // Show report after completing day 7
                        showingReport = true
                    }
                }
            }
        }
        .sheet(isPresented: $showingReport) {
            if let experiment = insightLabService.activeExperiment {
                NavigationStack {
                    ExperimentReportView(experimentId: experiment.id)
                }
            }
        }
        .alert(
            "Cancel Experiment",
            isPresented: $showingCancelConfirmation
        ) {
            Button("Keep Going", role: .cancel) {}
            Button("Cancel Experiment", role: .destructive) {
                Task {
                    await cancelExperiment()
                }
            }
        } message: {
            Text("Are you sure? Your progress will be lost and no report will be generated.")
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

    // MARK: - Progress Header

    private func progressHeader(_ experiment: InsightExperiment) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
            // Icon and status
            HStack(spacing: SupportTheme.Spacing.m) {
                if let actionType = experiment.actionTypeEnum {
                    Image(systemName: actionType.icon)
                        .font(.largeTitle)
                        .foregroundStyle(SupportTheme.onHero)
                        .frame(width: 70, height: 70)
                        .background(SupportTheme.Area.insights.palette.heroGradient)
                        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
                }

                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text("Day \(experiment.currentDay) of 7")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("\(experiment.completedDays) days completed")
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)

                    if experiment.hasBaseline {
                        Label("Baseline data available", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.Status.positive)
                    }
                }
            }

            // Progress bar
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                ProgressView(value: Double(experiment.completedDays), total: 7)
                    .tint(SupportTheme.Status.positive)
                    .scaleEffect(x: 1, y: 2, anchor: .center)

                HStack {
                    Text("\(experiment.daysRemaining) days remaining")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                    Spacer()
                    Text("\(Int((Double(experiment.completedDays) / 7) * 100))%")
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
        }
        .supportCard()
    }

    // MARK: - Today's Action Card

    private func todayActionCard(_ experiment: InsightExperiment) -> some View {
        let currentDay = experiment.currentDay
        let todayCompleted = experiment.days.first(where: { $0.dayIndex == currentDay })?.completed ?? false

        return VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
            Text("Today's Action")
                .font(.headline)

            Text(experiment.description)
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)

            if todayCompleted {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(SupportTheme.Status.positive)
                    Text("Completed for today!")
                        .fontWeight(.medium)
                }
                .padding(SupportTheme.Spacing.m)
                .frame(maxWidth: .infinity)
                .background(SupportTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
            } else {
                Button {
                    selectedDayIndex = currentDay
                    showingMoodPicker = true
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle")
                        Text("Mark Today Complete")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.supportPrimary)
            }
        }
        .supportCard()
    }

    // MARK: - Day Progress Grid

    private func dayProgressGrid(_ experiment: InsightExperiment) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Progress")
                .font(.headline)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: SupportTheme.Spacing.s), count: 7), spacing: SupportTheme.Spacing.s) {
                ForEach(1...7, id: \.self) { dayIndex in
                    let day = experiment.days.first(where: { $0.dayIndex == dayIndex })
                    let isToday = dayIndex == experiment.currentDay
                    let isCompleted = day?.completed ?? false

                    DayBubble(
                        dayNumber: dayIndex,
                        isCompleted: isCompleted,
                        isToday: isToday,
                        moodScore: day?.moodScore
                    )
                }
            }

            // Legend
            HStack(spacing: SupportTheme.Spacing.m) {
                LegendItem(color: SupportTheme.Status.positive, label: "Completed")
                LegendItem(color: SupportTheme.accent, label: "Today")
                LegendItem(color: SupportTheme.separator, label: "Upcoming")
            }
            .font(.caption)
            .padding(.top, SupportTheme.Spacing.xs)
        }
        .supportCard()
    }

    // MARK: - Cancel Button

    private var cancelButton: some View {
        Button(role: .destructive) {
            showingCancelConfirmation = true
        } label: {
            Text("Cancel Experiment")
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, SupportTheme.Spacing.m)
    }

    // MARK: - Actions

    private func cancelExperiment() async {
        guard let experiment = insightLabService.activeExperiment else { return }

        do {
            try await insightLabService.cancelExperiment(experimentId: experiment.id)
            dismiss()
        } catch {
            errorMessage = "Failed to cancel: \(error.localizedDescription)"
        }
    }
}

// MARK: - Day Bubble

struct DayBubble: View {
    let dayNumber: Int
    let isCompleted: Bool
    let isToday: Bool
    let moodScore: Int?

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.xxs) {
            ZStack {
                Circle()
                    .fill(bubbleColor)
                    .frame(width: 40, height: 40)

                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.headline)
                        .foregroundStyle(SupportTheme.onAccent)
                } else {
                    Text("\(dayNumber)")
                        .font(.headline)
                        .foregroundStyle(isToday ? SupportTheme.onAccent : SupportTheme.textSecondary)
                }
            }

            if let mood = moodScore {
                Text(moodEmoji(mood))
                    .font(.caption)
            } else {
                Text(" ")
                    .font(.caption)
            }
        }
    }

    private var bubbleColor: Color {
        if isCompleted {
            return SupportTheme.Status.positive
        } else if isToday {
            return SupportTheme.accent
        } else {
            return SupportTheme.separator
        }
    }

    private func moodEmoji(_ score: Int) -> String {
        switch score {
        case 1: return "😔"
        case 2: return "😕"
        case 3: return "😐"
        case 4: return "🙂"
        case 5: return "😄"
        default: return ""
        }
    }
}

// MARK: - Legend Item

struct LegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.xxs) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .foregroundStyle(SupportTheme.textSecondary)
        }
    }
}

#Preview {
    NavigationStack {
        ExperimentProgressView()
    }
}
