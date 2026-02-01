//
//  RecoveryProgramView.swift
//  MindFriendApp
//
//  N006: Wellbeing Debt Calculator - Recovery Program Display
//  Shows 7-day recovery program with daily actions
//

import SwiftUI

struct RecoveryProgramView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss

    @State private var recoveryProgram: RecoveryProgram?
    @State private var isLoading = false
    @State private var isGenerating = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var needsMoreData = false
    @State private var selectedIntensity: Intensity = .moderate
    @State private var expandedDays: Set<Int> = []

    enum Intensity: String, CaseIterable {
        case gentle = "Gentle"
        case moderate = "Moderate"
        case aggressive = "Aggressive"

        var description: String {
            switch self {
            case .gentle: return "Easier pace, fewer daily actions"
            case .moderate: return "Balanced approach, recommended"
            case .aggressive: return "Faster recovery, more demanding"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if isLoading {
                        ProgressView("Loading...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.top, 100)
                    } else if isGenerating {
                        generatingView
                    } else if needsMoreData, let message = errorMessage {
                        needsMoreDataView(message)
                    } else if let error = errorMessage {
                        errorView(error)
                    } else if let program = recoveryProgram {
                        programView(program)
                    } else {
                        startView
                    }
                }
                .padding()
            }
            .navigationTitle("Recovery Program")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        Task {
                            await saveAndDismiss()
                        }
                    }
                    .disabled(isSaving)
                }

                if recoveryProgram != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Regenerate") {
                            Task {
                                await generateProgram()
                            }
                        }
                        .disabled(isSaving)
                    }
                }
            }
            .task {
                await loadExistingProgram()
            }
        }
    }

    // MARK: - Start View

    @ViewBuilder
    private var startView: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)

                Text("Start Recovery Program")
                    .font(.title2.bold())

                Text("Generate a personalized 7-day plan to reduce your wellbeing debt and prevent crashes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Intensity selector
            VStack(alignment: .leading, spacing: 12) {
                Text("Program Intensity")
                    .font(.headline)

                ForEach(Intensity.allCases, id: \.self) { intensity in
                    intensityOption(intensity)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Generate button
            Button {
                Task {
                    await generateProgram()
                }
            } label: {
                Label("Generate Program", systemImage: "sparkles")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isGenerating)
        }
    }

    @ViewBuilder
    private func intensityOption(_ intensity: Intensity) -> some View {
        Button {
            selectedIntensity = intensity
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(intensity.rawValue)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)

                    Text(intensity.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if selectedIntensity == intensity {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .padding()
            .background(selectedIntensity == intensity ? Color.blue.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Program View

    @ViewBuilder
    private func programView(_ program: RecoveryProgram) -> some View {
        VStack(spacing: 20) {
            // Program header
            programHeader(program)

            // Daily actions
            ForEach(program.dailyActions, id: \.day) { daily in
                dayCard(daily)
            }
        }
    }

    @ViewBuilder
    private func programHeader(_ program: RecoveryProgram) -> some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "flag.checkered.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 4) {
                    Text("7-Day Recovery Plan")
                        .font(.headline)

                    Text("Target: Reduce debt by \(Int(truncating: program.targetDebtReduction as NSDecimalNumber)) points")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Divider()

            Text("Follow these daily actions to replenish your wellbeing reserves and avoid crashes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func dayCard(_ daily: DailyActions) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Day header
            Button {
                withAnimation {
                    if expandedDays.contains(daily.day) {
                        expandedDays.remove(daily.day)
                    } else {
                        expandedDays.insert(daily.day)
                    }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Day \(daily.day)")
                            .font(.headline)

                        Text(daily.date)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("Focus: \(formatFocusArea(daily.focusArea))")
                            .font(.caption.bold())
                            .foregroundStyle(.blue)
                    }

                    Spacer()

                    Image(systemName: expandedDays.contains(daily.day) ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            // Actions list (expandable)
            if expandedDays.contains(daily.day) {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()

                    ForEach(Array(daily.actions.enumerated()), id: \.offset) { index, action in
                        actionRow(action, index: index)
                    }

                    // Day total
                    HStack {
                        Text("Daily Target")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("+\(daily.actions.reduce(0) { $0 + $1.targetPoints }) points")
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func actionRow(_ action: RecoveryAction, index: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Checkbox (non-functional, visual only)
            Image(systemName: "circle")
                .foregroundStyle(.blue)

            Text(action.action)
                .font(.subheadline)

            Spacer()

            Text("+\(action.targetPoints)")
                .font(.caption.bold())
                .foregroundStyle(.green)
        }
    }

    // MARK: - Generating View

    @ViewBuilder
    private var generatingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Generating your personalized recovery program...")
                .font(.headline)
                .multilineTextAlignment(.center)

            Text("Analyzing your patterns and selecting optimal actions")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 100)
    }

    // MARK: - Needs More Data View

    @ViewBuilder
    private func needsMoreDataView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("Track More Data First")
                .font(.title2.bold())

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Tips for generating data
            VStack(alignment: .leading, spacing: 12) {
                Text("Here's how to get started:")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                dataActionRow(icon: "face.smiling", text: "Log your mood daily")
                dataActionRow(icon: "moon.zzz", text: "Track your sleep patterns")
                dataActionRow(icon: "figure.mind.and.body", text: "Complete exercises")
                dataActionRow(icon: "checkmark.circle", text: "Finish your daily quests")
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Button("Close") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 40)
    }

    @ViewBuilder
    private func dataActionRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
        }
    }

    // MARK: - Error View

    @ViewBuilder
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundStyle(.red)

            Text("Generation Failed")
                .font(.title2.bold())

            Text(error)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Retry") {
                Task {
                    await generateProgram()
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 100)
    }

    // MARK: - Helper Methods

    private func generateProgram() async {
        isGenerating = true
        errorMessage = nil
        needsMoreData = false

        do {
            recoveryProgram = try await container.wellbeingDebtService.generateRecoveryProgram(
                intensity: selectedIntensity.rawValue.lowercased()
            )

            // Auto-expand day 1
            expandedDays = [1]

            isGenerating = false
        } catch let error as WellbeingDebtError {
            switch error {
            case .needsMoreData(let message):
                needsMoreData = true
                errorMessage = message
            default:
                errorMessage = error.localizedDescription
            }
            isGenerating = false
        } catch {
            errorMessage = error.localizedDescription
            isGenerating = false
        }
    }
    
    private func saveAndDismiss() async {
        // Only save if we have a generated program
        guard let program = recoveryProgram else {
            dismiss()
            return
        }
        
        isSaving = true
        
        do {
            _ = try await container.wellbeingDebtService.saveRecoveryProgram(program)
            isSaving = false
            dismiss()
        } catch {
            // If save fails, still dismiss but log error
            print("Failed to save recovery program: \(error)")
            isSaving = false
            dismiss()
        }
    }
    
    private func loadExistingProgram() async {
        isLoading = true
        
        do {
            if let existingProgram = try await container.wellbeingDebtService.fetchActiveRecoveryProgram() {
                recoveryProgram = existingProgram
                expandedDays = [1]
            }
        } catch {
            // No existing program or error - user can generate a new one
        }
        
        isLoading = false
    }

    private func formatFocusArea(_ area: String) -> String {
        area.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

#Preview {
    RecoveryProgramView()
        .environmentObject(DependencyContainer())
}
