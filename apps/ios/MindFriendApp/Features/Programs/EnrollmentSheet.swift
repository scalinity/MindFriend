import SwiftUI

// MARK: - Enrollment Sheet

struct EnrollmentSheet: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss

    let program: Program
    let onEnroll: (ProgramEnrollment) -> Void

    @State private var selectedTime = Date()
    @State private var isEnrolling = false

    var body: some View {
        NavigationStack {
            VStack(spacing: SupportTheme.Spacing.l) {
                // Program summary
                VStack(spacing: SupportTheme.Spacing.s) {
                    ZStack {
                        RoundedRectangle(cornerRadius: SupportTheme.cardRadius)
                            .fill(SupportTheme.accent)
                            .frame(width: 80, height: 80)

                        Image(systemName: program.category.icon)
                            .font(.system(.largeTitle))
                            .foregroundStyle(SupportTheme.textPrimary)
                    }

                    Text(program.title)
                        .font(.title3)
                        .fontWeight(.bold)

                    Text("\(program.durationDays) days • \(program.estimatedDailyMinutes) min/day")
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)
                }

                Divider()

                // Time picker
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                    Text("Daily Reminder Time")
                        .font(.headline)

                    Text("We'll remind you to complete your daily program content at this time.")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)

                    DatePicker(
                        "Reminder Time",
                        selection: $selectedTime,
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxHeight: 150)
                }

                Spacer()

                // Enroll button
                Button {
                    Task { await enroll() }
                } label: {
                    if isEnrolling {
                        ProgressView()
                            .tint(SupportTheme.accent)
                    } else {
                        Text("Start Program")
                    }
                }
                .buttonStyle(.supportPrimary)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(isEnrolling)

                // Premium warning
                if program.premiumOnly {
                    HStack {
                        Image(systemName: "crown.fill")
                            .foregroundStyle(SupportTheme.accent)
                        Text("This program requires a Premium subscription")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                }
            }
            .padding(SupportTheme.Spacing.m)
            .supportScreen()
            .navigationTitle("Start Program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func enroll() async {
        isEnrolling = true
        defer { isEnrolling = false }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timeString = formatter.string(from: selectedTime)

        do {
            let enrollment = try await container.supabaseDataService.enrollInProgram(
                programId: program.id,
                preferredTime: timeString
            )

            onEnroll(enrollment)
            dismiss()
        } catch {
            appState.showError(.apiError(error.localizedDescription))
        }
    }
}

// MARK: - Program Paused View

struct ProgramPausedView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss

    let enrollment: ProgramEnrollment

    @State private var isResuming = false
    @State private var isAbandoning = false
    @State private var showAbandonConfirm = false

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.l) {
            // Status icon
            ZStack {
                Circle()
                    .fill(SupportTheme.accent.opacity(0.2))
                    .frame(width: 80, height: 80)

                Image(systemName: "pause.circle.fill")
                    .font(.system(.largeTitle))
                    .foregroundStyle(SupportTheme.accent)
            }

            VStack(spacing: SupportTheme.Spacing.xs) {
                Text("Program Paused")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(enrollment.program?.title ?? "")
                    .font(.headline)
                    .foregroundStyle(SupportTheme.textSecondary)
            }

            // Progress info
            VStack(spacing: SupportTheme.Spacing.xxs) {
                Text("Day \(enrollment.currentDay) of \(enrollment.program?.durationDays ?? 0)")
                    .font(.subheadline)

                if let pausedAt = enrollment.pausedAt {
                    Text("Paused \(pausedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
            }

            Spacer()

            // Actions
            VStack(spacing: SupportTheme.Spacing.s) {
                Button {
                    Task { await resume() }
                } label: {
                    if isResuming {
                        ProgressView()
                            .tint(SupportTheme.accent)
                    } else {
                        Text("Resume Program")
                    }
                }
                .buttonStyle(.supportPrimary)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(isResuming || isAbandoning)

                Button(role: .destructive) {
                    showAbandonConfirm = true
                } label: {
                    Text("Leave Program")
                }
                .disabled(isResuming || isAbandoning)
            }
        }
        .padding(SupportTheme.Spacing.m)
        .alert("Leave Program?", isPresented: $showAbandonConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Leave", role: .destructive) {
                Task { await abandon() }
            }
        } message: {
            Text("You'll lose your progress in this program.")
        }
    }

    private func resume() async {
        isResuming = true
        defer { isResuming = false }

        do {
            try await container.supabaseDataService.resumeEnrollment(enrollment.id)
            dismiss()
        } catch {
            appState.showError(.apiError(error.localizedDescription))
        }
    }

    private func abandon() async {
        isAbandoning = true
        defer { isAbandoning = false }

        do {
            try await container.supabaseDataService.abandonEnrollment(enrollment.id)
            dismiss()
        } catch {
            appState.showError(.apiError(error.localizedDescription))
        }
    }
}

#Preview("Enrollment Sheet") {
    EnrollmentSheet(
        program: Program(
            id: "1",
            slug: "21-day-anxiety-reset",
            title: "21-Day Anxiety Reset",
            description: "A comprehensive program",
            durationDays: 21,
            category: .anxiety,
            difficulty: .beginner,
            premiumOnly: false,
            learningObjectives: [],
            tags: [],
            coverImageUrl: nil,
            estimatedDailyMinutes: 15,
            sortOrder: 1,
            methodology: nil,
            evidenceSummary: nil,
            evidenceUrl: nil,
            targetConditions: [],
            requiresBaselineAssessment: false,
            assessmentType: nil
        )
    ) { _ in }
        .environmentObject(AppState())
        .environmentObject(DependencyContainer())
}
