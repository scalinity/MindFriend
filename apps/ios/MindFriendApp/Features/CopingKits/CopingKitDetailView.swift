import SwiftUI

// MARK: - Coping Kit Detail View

struct CopingKitDetailView: View {
    @ObservedObject var viewModel: CopingKitsViewModel
    let kit: CopingKit

    @Environment(\.dismiss) private var dismiss
    @State private var showingCompletion = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress bar
                progressBar

                // Step content
                if let step = viewModel.currentStep {
                    ScrollView {
                        CopingKitStepView(
                            step: step,
                            stepNumber: viewModel.currentStepIndex + 1,
                            totalSteps: kit.stepsCount
                        )
                    }
                } else if viewModel.isKitComplete {
                    // Kit complete - show completion view
                    CopingKitCompletionView(viewModel: viewModel, kit: kit)
                } else {
                    // No step - show kit overview
                    kitOverviewContent
                }

                // Bottom action bar
                actionBar
            }
            .navigationTitle(kit.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task {
                            await viewModel.goBack()
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if let userState = kit.userState {
                        Button {
                            Task {
                                await viewModel.togglePin(kit)
                            }
                        } label: {
                            Image(systemName: userState.pinned ? "pin.fill" : "pin")
                                .foregroundStyle(userState.pinned ? .pink : .secondary)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingCompletion) {
                CopingKitCompletionView(viewModel: viewModel, kit: kit)
            }
            .overlay {
                if viewModel.isCompleting {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.2))
                }
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK") {
                    viewModel.dismissError()
                }
            } message: {
                Text(viewModel.error?.localizedDescription ?? "An error occurred")
            }
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(height: 4)

                Rectangle()
                    .fill(Color.pink)
                    .frame(width: geometry.size.width * viewModel.progressPercentage, height: 4)
            }
        }
        .frame(height: 4)
    }

    // MARK: - Kit Overview Content

    private var kitOverviewContent: some View {
        VStack(spacing: 24) {
            Spacer()

            // Kit icon
            ZStack {
                Circle()
                    .fill(Color.pink.opacity(0.15))
                    .frame(width: 80, height: 80)

                Image(systemName: kit.contextIcon)
                    .font(.system(size: 36))
                    .foregroundStyle(.pink)
            }

            // Kit info
            VStack(spacing: 8) {
                Text(kit.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 16) {
                    Label(kit.formattedDuration, systemImage: "clock")
                    Label("\(kit.stepsCount) steps", systemImage: "list.bullet")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)

            // Steps preview
            VStack(alignment: .leading, spacing: 12) {
                Text("What's included")
                    .font(.headline)
                    .padding(.horizontal)

                ForEach(Array(kit.steps.enumerated()), id: \.offset) { index, step in
                    HStack {
                        Text("\(index + 1)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .frame(width: 24, height: 24)
                            .background(Color.pink.opacity(0.15))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.typeDescription)
                                .font(.subheadline)
                                .fontWeight(.medium)

                            if let instructions = step.instructions {
                                Text(instructions)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }

                        Spacer()

                        if let duration = step.durationSeconds {
                            Text("\(duration)s")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
                }
            }

            Spacer()
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        VStack(spacing: 8) {
            // Step counter
            Text("Step \(viewModel.currentStepIndex + 1) of \(kit.stepsCount)")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Action button
            Button {
                Task {
                    if viewModel.currentStepIndex == 0 && !viewModel.hasActiveSession {
                        await viewModel.startKit()
                    } else if viewModel.isKitComplete {
                        showingCompletion = true
                    } else {
                        await viewModel.nextStep()
                    }
                }
            } label: {
                Text(buttonTitle)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.pink)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(viewModel.isCompleting)
        }
        .padding()
        .background(Color(.systemBackground))
    }

    private var buttonTitle: String {
        if viewModel.isCompleting {
            return "Loading..."
        } else if viewModel.isKitComplete {
            return "Complete"
        } else if viewModel.currentStepIndex == 0 && !viewModel.hasActiveSession {
            return "Start Kit"
        } else {
            return "Continue"
        }
    }
}

// MARK: - Coping Kit Step Extension

extension CopingKitStep {
    var typeDescription: String {
        switch type {
        case .exercise:
            return exerciseType.map { $0.capitalized } ?? "Exercise"
        case .grounding:
            return "Grounding"
        case .chatCheckin:
            return "Reflection"
        case .breathing:
            return breathingPattern?.displayName ?? "Breathing"
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let viewModel = CopingKitsViewModel.preview()
    let kit = viewModel.availableKits[0]
    return CopingKitDetailView(viewModel: viewModel, kit: kit)
}
#endif
