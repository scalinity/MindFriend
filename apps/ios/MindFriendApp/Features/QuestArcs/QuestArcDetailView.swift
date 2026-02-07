//
//  QuestArcDetailView.swift
//  MindFriendApp
//
//  Detail view for a quest arc with enrollment and progress tracking
//

import SwiftUI

struct QuestArcDetailView: View {
    @EnvironmentObject private var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss

    let arc: QuestArc
    let activeArc: UserQuestArc?
    let onUpdate: () async -> Void

    @State private var isEnrolling = false
    @State private var isPausing = false
    @State private var isExiting = false
    @State private var showExitConfirmation = false
    @State private var errorMessage: String?
    @State private var showMilestonePreview = false

    // Interactive features
    @State private var todayQuest: Quest?
    @State private var isLoadingQuest = false
    @State private var arcSteps: [QuestArcStep] = []
    @State private var navigateToQuest = false

    private var isEnrolled: Bool {
        activeArc?.arcId == arc.id
    }

    private var hasOtherActiveArc: Bool {
        guard let active = activeArc else { return false }
        return active.arcId != arc.id
    }

    private var currentDay: Int {
        activeArc?.currentDay ?? 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    headerSection

                    // Today's Quest (if enrolled and active)
                    if isEnrolled, activeArc?.status == .active {
                        todaysQuestSection
                    }

                    // Progress (if enrolled)
                    if isEnrolled, let userArc = activeArc {
                        progressSection(userArc)
                    }

                    // Curriculum Preview
                    if !arcSteps.isEmpty {
                        curriculumPreviewSection
                    }

                    // Description
                    descriptionSection

                    // Milestones
                    milestonesSection

                    // What You'll Learn
                    benefitsSection

                    // Error message
                    if let error = errorMessage {
                        errorBanner(error)
                    }

                    // Action Button
                    actionSection
                }
                .padding()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $navigateToQuest) {
                if let quest = todayQuest {
                    QuestDetailView(quest: quest)
                }
            }
            .task {
                await loadArcSteps()
                if isEnrolled && activeArc?.status == .active {
                    await loadTodayQuest()
                }
            }
        }
        .confirmationDialog(
            "Exit Journey?",
            isPresented: $showExitConfirmation,
            titleVisibility: .visible
        ) {
            Button("Exit Journey", role: .destructive) {
                Task { await exitArc() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your progress will be lost. You can start this journey again later.")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                categoryIcon
                Spacer()
                if arc.isPremium {
                    premiumBadge
                }
            }

            Text(arc.title)
                .font(.title.weight(.bold))

            HStack(spacing: 16) {
                Label("\(arc.durationDays) days", systemImage: "calendar")
                Label("\(arc.milestoneDays.count) milestones", systemImage: "flag.fill")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private var categoryIcon: some View {
        Image(systemName: QuestArcCategory.iconName(for: arc.category))
            .font(.title)
            .foregroundStyle(QuestArcCategory.color(for: arc.category))
            .frame(width: 56, height: 56)
            .background(QuestArcCategory.color(for: arc.category).opacity(0.15))
            .clipShape(Circle())
    }

    private var premiumBadge: some View {
        Label("Premium", systemImage: "star.fill")
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.15))
            .foregroundStyle(.orange)
            .clipShape(Capsule())
    }

    // MARK: - Progress Section

    private func progressSection(_ userArc: UserQuestArc) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your Progress")
                    .font(.headline)
                Spacer()
                Text("Day \(userArc.currentDay) of \(userArc.snapshotDurationDays)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: userArc.progressPercentage)
                .tint(QuestArcCategory.color(for: arc.category))

            if userArc.status == .paused {
                HStack {
                    Image(systemName: "pause.circle.fill")
                        .foregroundStyle(.orange)
                    Text("Paused")
                        .font(.subheadline.weight(.medium))
                    if let _ = userArc.pausedAt {
                        Text("- Resume within 30 days")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Next milestone
            if let nextMilestone = userArc.nextMilestoneDay {
                HStack {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(.orange)
                    Text("Next milestone in \(nextMilestone - userArc.currentDay) days")
                        .font(.subheadline)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Description

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About This Journey")
                .font(.headline)

            Text(arc.description)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Milestones

    private var milestonesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Milestones")
                    .font(.headline)
                Spacer()
                Button {
                    showMilestonePreview = true
                } label: {
                    Text("Preview")
                        .font(.subheadline)
                }
            }

            ForEach(Array(arc.milestoneDays.enumerated()), id: \.offset) { index, day in
                milestoneRow(index: index + 1, day: day)
            }
        }
        .sheet(isPresented: $showMilestonePreview) {
            MilestonePreviewSheet(arc: arc)
        }
    }

    private func milestoneRow(index: Int, day: Int) -> some View {
        HStack(spacing: 12) {
            let isCompleted = isEnrolled && (activeArc?.currentDay ?? 0) >= day

            ZStack {
                Circle()
                    .fill(isCompleted ? QuestArcCategory.color(for: arc.category) : Color(.systemGray4))
                    .frame(width: 32, height: 32)

                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(index)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Milestone \(index)")
                    .font(.subheadline.weight(.medium))
                Text("Day \(day)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isCompleted {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Benefits

    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What You'll Experience")
                .font(.headline)

            ForEach(QuestArcCategory.benefits(for: arc.category), id: \.self) { benefit in
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(QuestArcCategory.color(for: arc.category))
                    Text(benefit)
                        .font(.subheadline)
                }
            }
        }
    }


    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.subheadline)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Action Section

    private var actionSection: some View {
        VStack(spacing: 12) {
            if isEnrolled {
                enrolledActions
            } else if hasOtherActiveArc {
                otherArcActiveMessage
            } else {
                startButton
            }
        }
        .padding(.top)
    }

    private var enrolledActions: some View {
        VStack(spacing: 12) {
            if activeArc?.status == .paused {
                Button {
                    Task { await resumeArc() }
                } label: {
                    HStack {
                        if isPausing {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "play.fill")
                        }
                        Text("Resume Journey")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(QuestArcCategory.color(for: arc.category))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isPausing)
            } else {
                Button {
                    Task { await pauseArc() }
                } label: {
                    HStack {
                        if isPausing {
                            ProgressView()
                        } else {
                            Image(systemName: "pause.fill")
                        }
                        Text("Pause Journey")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isPausing)
            }

            Button {
                showExitConfirmation = true
            } label: {
                HStack {
                    if isExiting {
                        ProgressView()
                    } else {
                        Image(systemName: "xmark.circle")
                    }
                    Text("Exit Journey")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundStyle(.red)
            }
            .disabled(isExiting)
        }
    }

    private var otherArcActiveMessage: some View {
        VStack(spacing: 12) {
            VStack(spacing: 8) {
                Text("You have an active journey")
                    .font(.subheadline.weight(.medium))
                if let currentTitle = activeArc?.arc?.title ?? activeArc?.questArc?.title {
                    Text("Currently enrolled in \"\(currentTitle)\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Complete or exit your current journey to start this one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Button {
                showExitConfirmation = true
            } label: {
                HStack {
                    if isExiting {
                        ProgressView()
                    } else {
                        Image(systemName: "xmark.circle")
                    }
                    Text("Exit Current Journey")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundStyle(.red)
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isExiting)
        }
    }

    private var startButton: some View {
        Button {
            Task { await startArc() }
        } label: {
            HStack {
                if isEnrolling {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "play.fill")
                }
                Text("Start Journey")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(QuestArcCategory.color(for: arc.category))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isEnrolling)
    }

    // MARK: - Actions

    private func startArc() async {
        isEnrolling = true
        errorMessage = nil

        do {
            _ = try await container.questArcsService.startQuestArc(arcId: arc.id)
            await onUpdate()
            // Notify HomeView to refresh quest data
            NotificationCenter.default.post(name: .questArcDidChange, object: nil)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isEnrolling = false
    }

    private func pauseArc() async {
        isPausing = true
        errorMessage = nil

        do {
            _ = try await container.questArcsService.pauseQuestArc(userArcId: activeArc?.id)
            await onUpdate()
            // Notify HomeView to refresh quest data
            NotificationCenter.default.post(name: .questArcDidChange, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }

        isPausing = false
    }

    private func resumeArc() async {
        isPausing = true
        errorMessage = nil

        do {
            guard let userArcId = activeArc?.id else { return }
            _ = try await container.questArcsService.resumeQuestArc(userArcId: userArcId)
            await onUpdate()
            // Notify HomeView to refresh quest data
            NotificationCenter.default.post(name: .questArcDidChange, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }

        isPausing = false
    }

    private func exitArc() async {
        isExiting = true
        errorMessage = nil

        do {
            _ = try await container.questArcsService.exitQuestArc(userArcId: activeArc?.id)
            await onUpdate()
            // Notify HomeView to refresh quest data
            NotificationCenter.default.post(name: .questArcDidChange, object: nil)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isExiting = false
    }

    // MARK: - Today's Quest Section

    private var todaysQuestSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.orange)
                Text("Today's Quest")
                    .font(.headline)
            }

            if isLoadingQuest {
                HStack {
                    ProgressView()
                    Text("Loading today's quest...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if let quest = todayQuest {
                VStack(alignment: .leading, spacing: 12) {
                    // Quest info
                    Text(quest.template.title)
                        .font(.title3.weight(.semibold))

                    Text(quest.template.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    // Coaching message
                    if let coaching = quest.arcContext?.coachingMessage {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                                .foregroundStyle(.yellow)
                                .font(.subheadline)
                            Text(coaching)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .italic()
                        }
                        .padding(12)
                        .background(Color.yellow.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Estimated time
                    HStack {
                        Image(systemName: "clock")
                            .foregroundStyle(.secondary)
                        Text("~\(quest.template.estimatedMinutes) min")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Milestone indicator
                    if quest.arcContext?.isMilestoneDay == true {
                        HStack {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                            Text("Milestone Day!")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.orange)
                        }
                    }

                    // Start Quest button
                    Button {
                        navigateToQuest = true
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Start Today's Quest")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(QuestArcCategory.color(for: arc.category))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Text("No quest available for today")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Curriculum Preview Section

    private var curriculumPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Journey")
                .font(.headline)

            // Show current day context + next few days
            let stepsToShow = getRelevantSteps()

            ForEach(stepsToShow) { step in
                curriculumStepRow(step: step)
            }

            if arcSteps.count > stepsToShow.count {
                Text("+ \(arcSteps.count - stepsToShow.count) more days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 44)
            }
        }
    }

    private func curriculumStepRow(step: QuestArcStep) -> some View {
        let isCompleted = isEnrolled && currentDay >= step.dayNumber
        let isCurrent = isEnrolled && (currentDay + 1) == step.dayNumber
        let isLocked = !isEnrolled || currentDay < step.dayNumber - 1

        return HStack(spacing: 12) {
            // Day indicator
            ZStack {
                Circle()
                    .fill(isCompleted ? QuestArcCategory.color(for: arc.category) :
                          isCurrent ? QuestArcCategory.color(for: arc.category).opacity(0.3) :
                          Color(.systemGray5))
                    .frame(width: 32, height: 32)

                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(step.dayNumber)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(isCurrent ? QuestArcCategory.color(for: arc.category) : .secondary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(step.customTitle ?? "Day \(step.dayNumber)")
                        .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                        .foregroundStyle(isLocked && !isCurrent ? .secondary : .primary)

                    if step.isMilestone {
                        Image(systemName: "flag.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }

                    if isCurrent {
                        Text("Today")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(QuestArcCategory.color(for: arc.category))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }

                if let description = step.customDescription {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .opacity(isLocked && !isCurrent ? 0.6 : 1.0)
    }

    /// Get steps to show: completed + current + next 3 upcoming
    private func getRelevantSteps() -> [QuestArcStep] {
        guard !arcSteps.isEmpty else { return [] }

        if isEnrolled {
            // Show from current day - 1 (yesterday) to current day + 3 (3 days ahead)
            let startDay = max(1, currentDay) // yesterday or day 1
            let endDay = min(arc.durationDays, currentDay + 4) // 3 days ahead

            return arcSteps.filter { $0.dayNumber >= startDay && $0.dayNumber <= endDay }
        } else {
            // Not enrolled: show first 4 days as preview
            return Array(arcSteps.prefix(4))
        }
    }

    // MARK: - Data Loading

    private func loadTodayQuest() async {
        await MainActor.run { isLoadingQuest = true }

        do {
            let quest = try await container.supabaseDataService.getTodayQuest()
            await MainActor.run {
                // Only show quest if it belongs to this arc
                if quest?.arcContext?.arcId == arc.id.uuidString {
                    self.todayQuest = quest
                }
                isLoadingQuest = false
            }
        } catch {
            await MainActor.run { isLoadingQuest = false }
        }
    }

    private func loadArcSteps() async {
        do {
            let steps = try await container.questArcsService.getArcSteps(arcId: arc.id)
            await MainActor.run { arcSteps = steps }
        } catch {
            // Silently fail - steps are optional enhancement
        }
    }
}

// MARK: - Milestone Preview Sheet

private struct MilestonePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let arc: QuestArc

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("When you reach a milestone, you'll see a celebration and can share your achievement with your circles.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    // Preview of milestone celebration
                    QuestArcMilestoneView(
                        arcTitle: arc.title,
                        milestoneNumber: 1,
                        totalMilestones: arc.milestoneDays.count,
                        dayNumber: arc.milestoneDays.first ?? 7,
                        onDismiss: { dismiss() },
                        onShare: { dismiss() }
                    )
                }
                .padding()
            }
            .navigationTitle("Milestone Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    QuestArcDetailView(
        arc: QuestArc(
            id: UUID(),
            title: "Stress Relief Journey",
            description: "A 14-day program to help you manage stress through proven techniques.",
            category: "stress",
            durationDays: 14,
            difficultyLevel: "intermediate",
            isPremium: false,
            milestoneDays: [3, 7, 14],
            iconName: "brain.head.profile",
            stepCount: 5,
            userEnrolled: false,
            userCompleted: false,
            userProgress: nil
        ),
        activeArc: nil,
        onUpdate: {}
    )
    .environmentObject(DependencyContainer())
}
