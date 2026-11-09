import SwiftUI

/// Multi-step onboarding flow for setting up a user's stress signature
struct SignatureOnboardingFlow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss

    @State private var currentStep: OnboardingStep = .introduction
    @State private var selectedComponents: Set<UUID> = []
    @State private var sensitivity: Double = 0.5
    @State private var isCreating = false
    @State private var error: Error?

    enum OnboardingStep: Int, CaseIterable {
        case introduction
        case sleep
        case social
        case cognitive
        case emotional
        case behavioral
        case physical
        case sensitivity
        case summary
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress indicator
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(SupportTheme.accent)
                    .padding(.horizontal, SupportTheme.Spacing.m)

                // Content
                TabView(selection: $currentStep) {
                    introductionView
                        .tag(OnboardingStep.introduction)

                    categoryView(for: .sleep)
                        .tag(OnboardingStep.sleep)

                    categoryView(for: .social)
                        .tag(OnboardingStep.social)

                    categoryView(for: .cognitive)
                        .tag(OnboardingStep.cognitive)

                    categoryView(for: .emotional)
                        .tag(OnboardingStep.emotional)

                    categoryView(for: .behavioral)
                        .tag(OnboardingStep.behavioral)

                    categoryView(for: .physical)
                        .tag(OnboardingStep.physical)

                    sensitivityView
                        .tag(OnboardingStep.sensitivity)

                    summaryView
                        .tag(OnboardingStep.summary)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(reduceMotion ? nil : .easeInOut, value: currentStep)

                // Navigation buttons
                navigationButtons
            }
            .supportScreen()
            .navigationTitle("Your Warning Signs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if error != nil {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                        Text(error?.localizedDescription ?? "Unknown error")

                        Button("OK") { error = nil }
                    }
                    .foregroundStyle(SupportTheme.textSecondary)
                    .buttonStyle(.supportSecondary)
                    .supportCard()
                    .padding(SupportTheme.Spacing.m)
                }
            }
        }
    }

    // MARK: - Progress

    private var progress: Double {
        Double(currentStep.rawValue + 1) / Double(OnboardingStep.allCases.count)
    }

    // MARK: - Introduction View

    private var introductionView: some View {
        ScrollView {
            VStack(spacing: SupportTheme.Spacing.l) {
                Image(systemName: "shield.checkered")
                    .font(.system(.largeTitle))
                    .foregroundStyle(SupportTheme.accent)
                    .padding(.top, SupportTheme.Spacing.xl)

                Text("Learn Your Warning Signs")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Everyone has unique patterns that appear before stress overwhelms them. By learning your personal warning signs, MindFriend can alert you 24-72 hours before a crisis and help you intervene early.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .padding(.horizontal, SupportTheme.Spacing.m)

                VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
                    benefitRow(
                        icon: "eye.fill",
                        title: "Personalized Detection",
                        description: "We learn your unique patterns"
                    )
                    benefitRow(
                        icon: "clock.fill",
                        title: "Early Warning",
                        description: "Get alerts 24-72 hours ahead"
                    )
                    benefitRow(
                        icon: "hand.raised.fill",
                        title: "Prevent Crisis",
                        description: "Intervene before things spiral"
                    )
                }
                .supportCard()
                .padding(.horizontal, SupportTheme.Spacing.m)

                Text("This takes about 3 minutes")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
            .padding(.bottom, SupportTheme.Spacing.xl)
        }
    }

    private func benefitRow(icon: String, title: String, description: String) -> some View {
        HStack(spacing: SupportTheme.Spacing.s) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(SupportTheme.accent)
                .frame(width: 32)

            VStack(alignment: .leading) {
                Text(title)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
        }
    }

    // MARK: - Category Views

    private func categoryView(for category: SignatureComponentCategory) -> some View {
        let components = SignatureComponent.components(for: category)

        return ScrollView {
            VStack(spacing: SupportTheme.Spacing.l) {
                VStack(spacing: SupportTheme.Spacing.xs) {
                    Image(systemName: category.icon)
                        .font(.system(.largeTitle))
                        .foregroundStyle(SupportTheme.accent)

                    Text(category.displayName)
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Select any that feel familiar when you're struggling")
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, SupportTheme.Spacing.m)

                VStack(spacing: SupportTheme.Spacing.s) {
                    ForEach(components) { component in
                        componentCard(component)
                    }
                }
                .padding(.horizontal, SupportTheme.Spacing.m)
            }
            .padding(.bottom, SupportTheme.Spacing.xl)
        }
    }

    private func componentCard(_ component: SignatureComponent) -> some View {
        let isSelected = selectedComponents.contains(component.id)

        return Button {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3)) {
                if isSelected {
                    selectedComponents.remove(component.id)
                } else {
                    selectedComponents.insert(component.id)
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text(component.displayName)
                        .font(.headline)
                        .foregroundStyle(isSelected ? SupportTheme.onAccent : SupportTheme.textPrimary)

                    Text(component.description)
                        .font(.caption)
                        .foregroundStyle(isSelected ? SupportTheme.onAccent.opacity(0.8) : SupportTheme.textSecondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? SupportTheme.onAccent : SupportTheme.textSecondary)
            }
            .padding(SupportTheme.Spacing.m)
            .background(isSelected ? SupportTheme.accent : SupportTheme.separator)
            .cornerRadius(SupportTheme.controlRadius)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sensitivity View

    private var sensitivityView: some View {
        ScrollView {
            VStack(spacing: SupportTheme.Spacing.l) {
                VStack(spacing: SupportTheme.Spacing.xs) {
                    Image(systemName: "dial.medium.fill")
                        .font(.system(.largeTitle))
                        .foregroundStyle(SupportTheme.accent)

                    Text("Detection Sensitivity")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("How sensitive should pattern detection be?")
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
                .padding(.top, SupportTheme.Spacing.m)

                VStack(spacing: SupportTheme.Spacing.m) {
                    HStack {
                        Text("Fewer Alerts")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                        Spacer()
                        Text("More Alerts")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }

                    Slider(value: $sensitivity, in: 0.3...0.8, step: 0.1)
                        .tint(SupportTheme.accent)

                    Text(sensitivityDescription)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(SupportTheme.textSecondary)
                        .supportCard()
                }
                .padding(.horizontal, SupportTheme.Spacing.m)

                Text("You can adjust this anytime in Settings")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
            .padding(.bottom, SupportTheme.Spacing.xl)
        }
    }

    private var sensitivityDescription: String {
        switch sensitivity {
        case 0.3..<0.4:
            return "Very conservative. Only alerts when many warning signs are present. May miss some patterns."
        case 0.4..<0.5:
            return "Conservative. Fewer false alarms, but may miss early warning signs."
        case 0.5..<0.6:
            return "Balanced. Good balance between catching patterns early and avoiding false alarms."
        case 0.6..<0.7:
            return "Sensitive. More likely to catch patterns early, but may have occasional false alerts."
        default:
            return "Very sensitive. Maximum early detection, but expect more check-ins."
        }
    }

    // MARK: - Summary View

    private var summaryView: some View {
        ScrollView {
            VStack(spacing: SupportTheme.Spacing.l) {
                VStack(spacing: SupportTheme.Spacing.xs) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(.largeTitle))
                        .foregroundStyle(SupportTheme.accent)

                    Text("Your Warning Signs")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("\(selectedComponents.count) patterns selected")
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
                .padding(.top, SupportTheme.Spacing.m)

                if selectedComponents.isEmpty {
                    emptySelectionView
                } else {
                    selectedComponentsList
                }
            }
            .padding(.bottom, SupportTheme.Spacing.xl)
        }
    }

    private var emptySelectionView: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(SupportTheme.accent)

            Text("No warning signs selected")
                .font(.headline)

            Text("Please go back and select at least 2 warning signs that feel familiar to you.")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .supportCard()
        .padding(.horizontal, SupportTheme.Spacing.m)
    }

    private var selectedComponentsList: some View {
        VStack(spacing: SupportTheme.Spacing.s) {
            ForEach(SignatureComponentCategory.allCases, id: \.self) { category in
                let categoryComponents = selectedComponents.compactMap { id in
                    SignatureComponent.library.first { $0.id == id && $0.category == category }
                }

                if !categoryComponents.isEmpty {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                        Label(category.displayName, systemImage: category.icon)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(SupportTheme.textSecondary)

                        ForEach(categoryComponents) { component in
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(SupportTheme.accent)
                                Text(component.displayName)
                                    .font(.subheadline)
                                Spacer()
                            }
                        }
                    }
                    .supportCard()
                }
            }
        }
        .padding(.horizontal, SupportTheme.Spacing.m)
    }

    // MARK: - Navigation

    private var navigationButtons: some View {
        HStack(spacing: SupportTheme.Spacing.m) {
            if currentStep != .introduction {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentStep = OnboardingStep(rawValue: currentStep.rawValue - 1) ?? .introduction
                    }
                } label: {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(SupportTheme.Spacing.m)
                    .background(SupportTheme.separator)
                    .foregroundStyle(SupportTheme.textPrimary)
                    .cornerRadius(SupportTheme.controlRadius)
                }
            }

            Button {
                if currentStep == .summary {
                    createSignature()
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentStep = OnboardingStep(rawValue: currentStep.rawValue + 1) ?? .summary
                    }
                }
            } label: {
                HStack {
                    if isCreating {
                        ProgressView()
                            .tint(SupportTheme.accent)
                    } else {
                        Text(currentStep == .summary ? "Create My Signature" : "Continue")
                        if currentStep != .summary {
                            Image(systemName: "chevron.right")
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(SupportTheme.Spacing.m)
                .background(canProceed ? SupportTheme.accent : SupportTheme.textSecondary)
                .foregroundStyle(SupportTheme.textPrimary)
                .cornerRadius(SupportTheme.controlRadius)
            }
            .disabled(!canProceed || isCreating)
        }
        .padding(SupportTheme.Spacing.m)
        .background(SupportTheme.elevated)
    }

    private var canProceed: Bool {
        switch currentStep {
        case .summary:
            return selectedComponents.count >= 2
        default:
            return true
        }
    }

    // MARK: - Actions

    private func createSignature() {
        isCreating = true

        Task {
            do {
                let engine = container.stressSignatureEngine
                _ = try await engine.createSignature(
                    selectedComponentIds: selectedComponents
                )

                try await engine.updateSensitivity(sensitivity)

                dismiss()
            } catch {
                self.error = error
            }

            isCreating = false
        }
    }
}

#Preview {
    SignatureOnboardingFlow()
        .environmentObject(DependencyContainer())
}
