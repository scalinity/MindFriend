//
//  NeedsAssessmentView.swift
//  MindFriendApp
//
//  4-step guided needs assessment wizard
//

import SwiftUI

struct NeedsAssessmentView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: NeedsAssessmentViewModel

    init(service: BoundaryPlannerService) {
        _viewModel = StateObject(wrappedValue: NeedsAssessmentViewModel(service: service))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Step content
                Group {
                    switch viewModel.currentStep {
                    case 1:
                        Step1DrainTriggersView(viewModel: viewModel)
                    case 2:
                        Step2ImportanceRatingsView(viewModel: viewModel)
                    case 3:
                        Step3CurrentlyMetView(viewModel: viewModel)
                    case 4:
                        Step4PriorityNeedsView(viewModel: viewModel)
                    default:
                        EmptyView()
                    }
                }

                // Loading overlay
                if viewModel.isSubmitting {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("assessment.analyzing")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    .padding(32)
                    .background(Color.gray.opacity(0.9))
                    .cornerRadius(16)
                }
            }
            .navigationTitle("assessment.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .bottomBar) {
                    stepIndicator
                }
            }
            .alert("assessment.error_title", isPresented: $viewModel.showError) {
                Button("common.ok") {
                    viewModel.showError = false
                }
            } message: {
                if let error = viewModel.error {
                    Text(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 12) {
            ForEach(1...4, id: \.self) { step in
                Circle()
                    .fill(step == viewModel.currentStep ? Color.accentColor : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }
}

// MARK: - Step 1: Drain Triggers

struct Step1DrainTriggersView: View {
    @ObservedObject var viewModel: NeedsAssessmentViewModel

    private let drainTriggers = [
        ("assessment.drain_work_stress", "briefcase.fill"),
        ("assessment.drain_relationship_conflict", "person.2.fill"),
        ("assessment.drain_overcommitment", "calendar.badge.exclamationmark"),
        ("assessment.drain_lack_rest", "bed.double.fill"),
        ("assessment.drain_financial_worry", "dollarsign.circle.fill"),
        ("assessment.drain_health_concern", "heart.text.square.fill")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("assessment.step1_prompt")
                .font(.title3)
                .fontWeight(.semibold)

            Text("assessment.step1_description")
                .font(.body)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(drainTriggers, id: \.0) { trigger in
                        DrainTriggerCard(
                            title: trigger.0,
                            icon: trigger.1,
                            isSelected: viewModel.step1DrainTriggers.contains(trigger.0)
                        ) {
                            viewModel.toggleDrainTrigger(trigger.0)
                        }
                    }
                }
                .padding(.vertical)
            }

            Spacer()

            Button {
                viewModel.nextStep()
            } label: {
                Text("common.next")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.step1DrainTriggers.isEmpty ? Color.gray : Color.accentColor)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .disabled(viewModel.step1DrainTriggers.isEmpty)
        }
        .padding()
    }
}

struct DrainTriggerCard: View {
    let title: LocalizedStringKey
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(isSelected ? .white : .accentColor)
                    .frame(width: 44, height: 44)
                    .background(isSelected ? Color.accentColor : Color.accentColor.opacity(0.1))
                    .cornerRadius(12)

                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.accentColor)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 2: Importance Ratings

struct Step2ImportanceRatingsView: View {
    @ObservedObject var viewModel: NeedsAssessmentViewModel

    private let needs = [
        "assessment.need_autonomy",
        "assessment.need_rest",
        "assessment.need_connection",
        "assessment.need_achievement",
        "assessment.need_safety",
        "assessment.need_creativity"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("assessment.step2_prompt")
                .font(.title3)
                .fontWeight(.semibold)

            Text("assessment.step2_description")
                .font(.body)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 20) {
                    ForEach(needs, id: \.self) { need in
                        NeedRatingCard(
                            title: need,
                            rating: viewModel.step2ImportanceRatings[need] ?? .medium
                        ) { newRating in
                            viewModel.setImportanceRating(need, rating: newRating)
                        }
                    }
                }
                .padding(.vertical)
            }

            Spacer()

            HStack {
                Button {
                    viewModel.previousStep()
                } label: {
                    Text("common.back")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .foregroundStyle(.primary)
                        .cornerRadius(12)
                }

                Button {
                    viewModel.nextStep()
                } label: {
                    Text("common.next")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(viewModel.step2ImportanceRatings.count == needs.count ? Color.accentColor : Color.gray)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }
                .disabled(viewModel.step2ImportanceRatings.count < needs.count)
            }
        }
        .padding()
    }
}

struct NeedRatingCard: View {
    let title: LocalizedStringKey
    let rating: ImportanceLevel
    let onRatingChange: (ImportanceLevel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.body)
                .fontWeight(.medium)

            HStack(spacing: 8) {
                ForEach([ImportanceLevel.low, .medium, .high], id: \.self) { level in
                    Button {
                        onRatingChange(level)
                    } label: {
                        VStack(spacing: 4) {
                            Circle()
                                .fill(rating == level ? level.color : Color.gray.opacity(0.2))
                                .frame(width: 40, height: 40)

                            Text(level.displayName)
                                .font(.caption)
                                .foregroundStyle(rating == level ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Step 3: Currently Met

struct Step3CurrentlyMetView: View {
    @ObservedObject var viewModel: NeedsAssessmentViewModel

    private let needs = [
        "assessment.need_autonomy",
        "assessment.need_rest",
        "assessment.need_connection",
        "assessment.need_achievement",
        "assessment.need_safety",
        "assessment.need_creativity"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("assessment.step3_prompt")
                .font(.title3)
                .fontWeight(.semibold)

            Text("assessment.step3_description")
                .font(.body)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 20) {
                    ForEach(needs, id: \.self) { need in
                        CurrentlyMetCard(
                            title: need,
                            status: viewModel.step3CurrentlyMet[need] ?? .sometimes
                        ) { newStatus in
                            viewModel.setCurrentlyMet(need, status: newStatus)
                        }
                    }
                }
                .padding(.vertical)
            }

            Spacer()

            HStack {
                Button {
                    viewModel.previousStep()
                } label: {
                    Text("common.back")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .foregroundStyle(.primary)
                        .cornerRadius(12)
                }

                Button {
                    viewModel.nextStep()
                } label: {
                    Text("common.next")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(viewModel.step3CurrentlyMet.count == needs.count ? Color.accentColor : Color.gray)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }
                .disabled(viewModel.step3CurrentlyMet.count < needs.count)
            }
        }
        .padding()
    }
}

struct CurrentlyMetCard: View {
    let title: LocalizedStringKey
    let status: MetLevel
    let onStatusChange: (MetLevel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.body)
                .fontWeight(.medium)

            HStack(spacing: 8) {
                ForEach([MetLevel.no, .sometimes, .yes], id: \.self) { statusOption in
                    Button {
                        onStatusChange(statusOption)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: statusOption.icon)
                                .font(.title2)
                                .foregroundStyle(status == statusOption ? .white : statusOption.color)
                                .frame(width: 40, height: 40)
                                .background(status == statusOption ? statusOption.color : Color.gray.opacity(0.2))
                                .cornerRadius(8)

                            Text(statusOption.displayName)
                                .font(.caption)
                                .foregroundStyle(status == statusOption ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Step 4: Priority Needs

struct Step4PriorityNeedsView: View {
    @ObservedObject var viewModel: NeedsAssessmentViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("assessment.step4_prompt")
                .font(.title3)
                .fontWeight(.semibold)

            Text("assessment.step4_description")
                .font(.body)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(viewModel.suggestedPriorityNeeds, id: \.self) { need in
                        PriorityNeedCard(
                            title: need,
                            isConfirmed: viewModel.step4PriorityNeeds.contains(need)
                        ) {
                            viewModel.togglePriorityNeed(need)
                        }
                    }
                }
                .padding(.vertical)
            }

            Spacer()

            HStack {
                Button {
                    viewModel.previousStep()
                } label: {
                    Text("common.back")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .foregroundStyle(.primary)
                        .cornerRadius(12)
                }

                Button {
                    Task {
                        await viewModel.submitAssessment()
                    }
                } label: {
                    Text("assessment.submit")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(viewModel.step4PriorityNeeds.isEmpty ? Color.gray : Color.accentColor)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }
                .disabled(viewModel.step4PriorityNeeds.isEmpty)
            }
        }
        .padding()
    }
}

struct PriorityNeedCard: View {
    let title: LocalizedStringKey
    let isConfirmed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isConfirmed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.accentColor)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isConfirmed ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - View Model

@MainActor
final class NeedsAssessmentViewModel: ObservableObject {
    let service: BoundaryPlannerService

    @Published var currentStep = 1
    @Published var selectedAssessmentType: BoundaryAssessmentType = .work
    @Published var step1DrainTriggers: [String] = []
    @Published var step2ImportanceRatings: [String: ImportanceLevel] = [:]
    @Published var step3CurrentlyMet: [String: MetLevel] = [:]
    @Published var step4PriorityNeeds: [String] = []

    @Published var isSubmitting = false
    @Published var error: Error?
    @Published var showError = false

    var suggestedPriorityNeeds: [String] {
        // Calculate gap scores and suggest top needs
        var gapScores: [(need: String, score: Int)] = []

        for (need, importance) in step2ImportanceRatings {
            guard let currentlyMet = step3CurrentlyMet[need] else { continue }

            let score = calculateGapScore(importance: importance, currentlyMet: currentlyMet)
            gapScores.append((need, score))
        }

        // Sort by gap score descending
        gapScores.sort { $0.score > $1.score }

        // Return top 3 or all with score >= 6
        let highPriority = gapScores.filter { $0.score >= 6 }
        if highPriority.count >= 3 {
            return highPriority.prefix(3).map { $0.need }
        }
        return highPriority.map { $0.need }
    }

    init(service: BoundaryPlannerService) {
        self.service = service
    }

    func toggleDrainTrigger(_ trigger: String) {
        if let index = step1DrainTriggers.firstIndex(of: trigger) {
            step1DrainTriggers.remove(at: index)
        } else {
            step1DrainTriggers.append(trigger)
        }
    }

    func setImportanceRating(_ need: String, rating: ImportanceLevel) {
        step2ImportanceRatings[need] = rating
    }

    func setCurrentlyMet(_ need: String, status: MetLevel) {
        step3CurrentlyMet[need] = status
    }

    func togglePriorityNeed(_ need: String) {
        if let index = step4PriorityNeeds.firstIndex(of: need) {
            step4PriorityNeeds.remove(at: index)
        } else {
            step4PriorityNeeds.append(need)
        }
    }

    func nextStep() {
        withAnimation {
            currentStep += 1
        }
    }

    func previousStep() {
        withAnimation {
            currentStep -= 1
        }
    }

    func submitAssessment() async {
        isSubmitting = true
        error = nil

        do {
            let responses = AssessmentResponses(
                step1DrainTriggers: step1DrainTriggers,
                step2ImportanceRatings: Dictionary(
                    uniqueKeysWithValues: step2ImportanceRatings.map { ($0.key, $0.value.rawValue) }
                ),
                step3CurrentlyMet: Dictionary(
                    uniqueKeysWithValues: step3CurrentlyMet.map { ($0.key, $0.value.rawValue) }
                ),
                step4PriorityNeeds: step4PriorityNeeds
            )

            let result = try await service.createAssessment(
                type: selectedAssessmentType,
                responses: responses
            )

            // Navigate to results (handled by parent view)
            print("Assessment created: \(result.assessment.id)")

        } catch {
            self.error = error
            self.showError = true
        }

        isSubmitting = false
    }

    private func calculateGapScore(importance: ImportanceLevel, currentlyMet: MetLevel) -> Int {
        // Gap score matrix matching Edge Function logic
        switch (importance, currentlyMet) {
        case (.high, .no): return 9
        case (.high, .sometimes): return 7
        case (.high, .yes): return 3
        case (.medium, .no): return 6
        case (.medium, .sometimes): return 4
        case (.medium, .yes): return 2
        case (.low, .no): return 3
        case (.low, .sometimes): return 2
        case (.low, .yes): return 1
        }
    }
}

// MARK: - Supporting Types

extension BoundaryAssessmentType {
    var displayName: LocalizedStringKey {
        switch self {
        case .work:
            return "assessment.type.work"
        case .relationships:
            return "assessment.type.relationships"
        case .family:
            return "assessment.type.family"
        case .friends:
            return "assessment.type.friends"
        }
    }
}

// MARK: - Previews

#Preview {
    NeedsAssessmentView(service: BoundaryPlannerService(supabase: .mock))
}
