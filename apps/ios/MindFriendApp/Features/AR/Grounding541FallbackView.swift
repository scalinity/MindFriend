import SwiftUI

/// Non-AR 5-4-3-2-1 Grounding exercise fallback view
/// Text-based step-by-step guide for devices without AR support
public struct Grounding541FallbackView: View {

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var exerciseService: ARExerciseService

    // MARK: - Properties

    let exercise: ARExercise

    // MARK: - State

    @State private var currentStep: GroundingStep = .see
    @State private var itemsIdentified: Int = 0
    @State private var totalItemsIdentified: Int = 0
    @State private var identifiedItems: [String] = []
    @State private var currentInput: String = ""
    @State private var showCompletion: Bool = false
    @State private var showExitConfirmation: Bool = false
    @State private var effectivenessRating: Int = 0
    @State private var sessionId: UUID?
    @State private var isExerciseEnded: Bool = false

    // MARK: - Initialization

    public init(exercise: ARExercise) {
        self.exercise = exercise
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress bar
                progressBar
                    .padding()

                ScrollView {
                    VStack(spacing: 32) {
                        // Current step card
                        stepCard

                        // Items identified
                        if !identifiedItems.isEmpty {
                            identifiedItemsList
                        }

                        // Input field
                        if itemsIdentified < currentStep.count {
                            inputSection
                        } else {
                            // Next step button
                            nextStepButton
                        }
                    }
                    .padding()
                }

                Spacer()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("5-4-3-2-1 Grounding")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        showExitConfirmation = true
                    } label: {
                        Image(systemName: "xmark")
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if exerciseService.isSpeaking {
                            exerciseService.stopGuidance()
                        } else {
                            exerciseService.speakGuidance(currentStep.instruction)
                        }
                    } label: {
                        Image(systemName: exerciseService.isSpeaking ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    }
                }
            }
            .onAppear {
                startExercise()
            }
            .onDisappear {
                stopExercise()
            }
            .onChange(of: scenePhase) { _, newPhase in
                handleScenePhaseChange(newPhase)
            }
            .alert("End Exercise?", isPresented: $showExitConfirmation) {
                Button("Continue", role: .cancel) {}
                Button("End", role: .destructive) {
                    endExercise(completed: false)
                }
            }
            .sheet(isPresented: $showCompletion) {
                completionView
            }
        }
    }

    // MARK: - Subviews

    private var progressBar: some View {
        HStack(spacing: 8) {
            ForEach(GroundingStep.allCases, id: \.rawValue) { step in
                VStack(spacing: 4) {
                    Circle()
                        .fill(stepColor(for: step))
                        .frame(width: 24, height: 24)
                        .overlay {
                            Text("\(step.count)")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                        }

                    Text(step.displayName)
                        .font(.caption2)
                        .foregroundStyle(step == currentStep ? .primary : .secondary)
                }

                if step != .taste {
                    Rectangle()
                        .fill(step.rawValue > currentStep.rawValue ? Color.gray.opacity(0.3) : stepColor(for: step))
                        .frame(height: 2)
                }
            }
        }
    }

    private func stepColor(for step: GroundingStep) -> Color {
        let colors = exercise.sceneConfig.markerColors ?? MarkerColors()
        let hex = colors[keyPath: step.colorKey]
        if step.rawValue > currentStep.rawValue {
            return .gray.opacity(0.3)
        }
        return Color(UIColor(hex: hex) ?? .blue)
    }

    private var stepCard: some View {
        VStack(spacing: 16) {
            // Icon
            Image(systemName: stepIcon)
                .font(.system(size: 48))
                .foregroundStyle(stepColor(for: currentStep))
                .accessibilityHidden(true)

            // Instruction
            Text(currentStep.instruction)
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            // Progress
            Text("\(itemsIdentified)/\(currentStep.count)")
                .font(.headline)
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(itemsIdentified) of \(currentStep.count) items identified")

            // Hint
            Text(stepHint)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(currentStep.displayName) step. \(currentStep.instruction). \(itemsIdentified) of \(currentStep.count) items identified.")
    }

    private var stepIcon: String {
        switch currentStep {
        case .see: return "eye.fill"
        case .touch: return "hand.point.up.fill"
        case .hear: return "ear.fill"
        case .smell: return "nose.fill"
        case .taste: return "mouth.fill"
        }
    }

    private var stepHint: String {
        switch currentStep {
        case .see: return "Look around and notice \(currentStep.count) distinct things"
        case .touch: return "Think of \(currentStep.count) things you could reach out and touch"
        case .hear: return "Listen carefully for \(currentStep.count) sounds around you"
        case .smell: return "Notice \(currentStep.count) scents in your environment"
        case .taste: return "Notice \(currentStep.count) taste in your mouth"
        }
    }

    private var identifiedItemsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Items identified:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(identifiedItems.indices, id: \.self) { index in
                HStack {
                    Circle()
                        .fill(stepColor(for: currentStep))
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)

                    Text(identifiedItems[index])
                        .font(.body)

                    Spacer()

                    Button {
                        removeItem(at: index)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Remove \(identifiedItems[index])")
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var inputSection: some View {
        VStack(spacing: 12) {
            TextField("What do you \(currentStep.displayName.lowercased())?", text: $currentInput)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .onSubmit {
                    addItem()
                }
                .accessibilityLabel("Enter something you \(currentStep.displayName.lowercased())")

            Button {
                addItem()
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(currentInput.isEmpty ? .gray : .blue)
                .cornerRadius(12)
            }
            .disabled(currentInput.isEmpty)
            .accessibilityLabel("Add item")
            .accessibilityHint(currentInput.isEmpty ? "Enter an item first" : "Add \(currentInput) to the list")
        }
    }

    private var nextStepButton: some View {
        Button {
            advanceToNextStep()
        } label: {
            HStack {
                if let next = currentStep.next {
                    Text("Continue to: \(next.instruction)")
                } else {
                    Text("Complete Exercise")
                }
                Image(systemName: "arrow.right")
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(.green)
            .cornerRadius(12)
        }
        .accessibilityLabel(currentStep.next != nil ? "Continue to next step" : "Complete exercise")
        .accessibilityHint(currentStep.next != nil ? "Proceed to \(currentStep.next?.displayName ?? "") step" : "Finish the grounding exercise")
    }

    private var completionView: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue)

                Text("You're grounded!")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("You identified \(totalItemsIdentified) things in your environment")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 12) {
                    Text("How effective was this exercise?")
                        .font(.subheadline)

                    HStack(spacing: 8) {
                        ForEach(1...5, id: \.self) { rating in
                            Button {
                                effectivenessRating = rating
                            } label: {
                                Image(systemName: rating <= effectivenessRating ? "star.fill" : "star")
                                    .font(.title)
                                    .foregroundStyle(rating <= effectivenessRating ? .yellow : .gray)
                            }
                            .accessibilityLabel("\(rating) star\(rating != 1 ? "s" : "")")
                            .accessibilityAddTraits(rating <= effectivenessRating ? .isSelected : [])
                        }
                    }
                }

                Spacer()

                Button {
                    saveAndDismiss()
                } label: {
                    Text("Done")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue)
                        .cornerRadius(12)
                }
            }
            .padding()
            .navigationTitle("Session Complete")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Actions

    private func startExercise() {
        Task {
            do {
                let newSessionId = try await exerciseService.startSession(exercise: exercise)
                sessionId = newSessionId
                exerciseService.speakGuidance(currentStep.instruction)
            } catch {
                // Log error without PHI exposure
                #if DEBUG
                print("AR session start failed")
                #endif
            }
        }
    }

    private func stopExercise() {
        exerciseService.stopGuidance()
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .background, .inactive:
            // Record interruption when app goes to background
            if !isExerciseEnded {
                exerciseService.recordInterruption()
            }
        case .active:
            break
        @unknown default:
            break
        }
    }

    private func addItem() {
        // Validate input - sanitize and limit length
        let trimmedInput = currentInput.trimmingCharacters(in: .whitespaces)
        guard !trimmedInput.isEmpty else { return }
        
        // Limit input length for safety
        let sanitizedInput = String(trimmedInput.prefix(100))

        identifiedItems.append(sanitizedInput)
        itemsIdentified += 1
        totalItemsIdentified += 1
        currentInput = ""

        if itemsIdentified >= currentStep.count {
            exerciseService.speakGuidance("Step complete!")
        }
    }

    private func removeItem(at index: Int) {
        guard index >= 0 && index < identifiedItems.count else { return }
        identifiedItems.remove(at: index)
        itemsIdentified -= 1
        totalItemsIdentified -= 1
    }

    private func advanceToNextStep() {
        if let next = currentStep.next {
            currentStep = next
            itemsIdentified = 0
            identifiedItems = []
            exerciseService.speakGuidance(currentStep.instruction)
        } else {
            endExercise(completed: true)
        }
    }

    private func endExercise(completed: Bool) {
        // Guard against race conditions - only end once
        guard !isExerciseEnded else { return }
        isExerciseEnded = true
        
        exerciseService.stopGuidance()

        if completed {
            showCompletion = true
        } else {
            Task {
                await exerciseService.abandonSession()
            }
            dismiss()
        }
    }

    private func saveAndDismiss() {
        // Validate rating (1-5 range)
        let validatedRating: Int? = (1...5).contains(effectivenessRating) ? effectivenessRating : nil
        
        Task {
            // Use actual session ID, not exercise ID
            if let currentSessionId = sessionId {
                try? await exerciseService.completeSession(
                    sessionId: currentSessionId,
                    completedSteps: totalItemsIdentified,
                    rating: validatedRating
                )
            }
        }
        showCompletion = false
        dismiss()
    }
}
