//
//  TutorialFlowContainer.swift
//  MindFriendApp
//
//  Generic container for tutorial flows
//  Provides progress bar, step transitions, and navigation
//

import SwiftUI

/// Protocol for tutorial step enums
protocol TutorialStepProtocol: RawRepresentable, CaseIterable, Hashable where RawValue == Int {
    var progress: Double { get }
}

extension TutorialStepProtocol {
    var progress: Double {
        Double(rawValue + 1) / Double(Self.allCases.count)
    }
}

/// Generic container view for multi-step tutorials
struct TutorialFlowContainer<Step: TutorialStepProtocol, Content: View>: View {
    let accentColor: Color
    let onComplete: () -> Void
    @ViewBuilder let content: (Binding<Step>, @escaping () -> Void, @escaping () -> Void) -> Content

    @State private var currentStep: Step

    init(
        initialStep: Step,
        accentColor: Color = .blue,
        onComplete: @escaping () -> Void,
        @ViewBuilder content: @escaping (Binding<Step>, @escaping () -> Void, @escaping () -> Void) -> Content
    ) {
        self._currentStep = State(initialValue: initialStep)
        self.accentColor = accentColor
        self.onComplete = onComplete
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            ProgressView(value: currentStep.progress)
                .progressViewStyle(.linear)
                .tint(accentColor)
                .padding(.horizontal)
                .padding(.top, 60)
                .accessibilityLabel("Tutorial progress: \(Int(currentStep.progress * 100)) percent")

            // Step content with transitions
            content($currentStep, advanceStep, skipTutorial)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
        }
        .background(Color(.systemBackground))
        .animation(.easeInOut(duration: 0.3), value: currentStep)
    }

    private func advanceStep() {
        if let nextStep = Step(rawValue: currentStep.rawValue + 1) {
            withAnimation {
                currentStep = nextStep
            }
        } else {
            // Last step completed
            onComplete()
        }
    }

    private func skipTutorial() {
        onComplete()
    }
}

// MARK: - Common Tutorial Animations

/// Staggered reveal animation for list items
struct StaggeredReveal: ViewModifier {
    let index: Int
    let isVisible: Bool
    let baseDelay: Double

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 10)
            .animation(
                .easeOut(duration: 0.3).delay(baseDelay + Double(index) * 0.1),
                value: isVisible
            )
    }
}

extension View {
    /// Apply staggered reveal animation
    func staggeredReveal(index: Int, isVisible: Bool, baseDelay: Double = 0.3) -> some View {
        modifier(StaggeredReveal(index: index, isVisible: isVisible, baseDelay: baseDelay))
    }
}

/// Pulsing animation for highlight elements
struct PulsingAnimation: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.1 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}

extension View {
    /// Apply pulsing animation
    func pulsing() -> some View {
        modifier(PulsingAnimation())
    }
}

// MARK: - Tutorial Info Card

/// Reusable info card for tutorial content
struct TutorialInfoCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Reusable feature highlight row
struct TutorialFeatureRow: View {
    let icon: String
    let iconColor: Color
    let label: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(iconColor)
                .frame(width: 24)

            Text(label)
                .font(.subheadline)

            Spacer()
        }
    }
}

#Preview {
    enum PreviewStep: Int, TutorialStepProtocol, CaseIterable {
        case first = 0
        case second = 1
        case third = 2
    }

    return TutorialFlowContainer(
        initialStep: PreviewStep.first,
        accentColor: .blue,
        onComplete: {}
    ) { step, advance, skip in
        switch step.wrappedValue {
        case .first:
            TutorialStepView(
                icon: "1.circle.fill",
                headline: "Step 1",
                subheadline: "First step content",
                primaryAction: advance,
                skipAction: skip
            )
        case .second:
            TutorialStepView(
                icon: "2.circle.fill",
                headline: "Step 2",
                subheadline: "Second step content",
                primaryAction: advance,
                skipAction: skip
            )
        case .third:
            TutorialStepView(
                icon: "3.circle.fill",
                headline: "Step 3",
                subheadline: "Final step content",
                primaryLabel: "Get Started",
                primaryAction: advance
            )
        }
    }
}
