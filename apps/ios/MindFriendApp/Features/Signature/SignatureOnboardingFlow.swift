import SwiftUI

/// Multi-step onboarding flow for setting up a user's stress signature
struct SignatureOnboardingFlow: View {
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
                    .tint(.purple)
                    .padding(.horizontal)

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
                .animation(.easeInOut, value: currentStep)

                // Navigation buttons
                navigationButtons
            }
            .navigationTitle("Your Warning Signs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: .init(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("OK") { error = nil }
            } message: {
                Text(error?.localizedDescription ?? "Unknown error")
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
            VStack(spacing: 24) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 80))
                    .foregroundStyle(.purple.gradient)
                    .padding(.top, 40)

                Text("Learn Your Warning Signs")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Everyone has unique patterns that appear before stress overwhelms them. By learning your personal warning signs, MindFriend can alert you 24-72 hours before a crisis and help you intervene early.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 16) {
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
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)

                Text("This takes about 3 minutes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 100)
        }
    }

    private func benefitRow(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.purple)
                .frame(width: 32)

            VStack(alignment: .leading) {
                Text(title)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Category Views

    private func categoryView(for category: SignatureComponentCategory) -> some View {
        let components = SignatureComponent.components(for: category)

        return ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: category.icon)
                        .font(.system(size: 48))
                        .foregroundStyle(.purple.gradient)

                    Text(category.displayName)
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Select any that feel familiar when you're struggling")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)

                VStack(spacing: 12) {
                    ForEach(components) { component in
                        componentCard(component)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 100)
        }
    }

    private func componentCard(_ component: SignatureComponent) -> some View {
        let isSelected = selectedComponents.contains(component.id)

        return Button {
            withAnimation(.spring(response: 0.3)) {
                if isSelected {
                    selectedComponents.remove(component.id)
                } else {
                    selectedComponents.insert(component.id)
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(component.displayName)
                        .font(.headline)
                        .foregroundStyle(isSelected ? .white : .primary)

                    Text(component.description)
                        .font(.caption)
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? .white : .secondary)
            }
            .padding()
            .background(isSelected ? Color.purple : Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sensitivity View

    private var sensitivityView: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "dial.medium.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.purple.gradient)

                    Text("Detection Sensitivity")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("How sensitive should pattern detection be?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)

                VStack(spacing: 16) {
                    HStack {
                        Text("Fewer Alerts")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("More Alerts")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: $sensitivity, in: 0.3...0.8, step: 0.1)
                        .tint(.purple)

                    Text(sensitivityDescription)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
                .padding(.horizontal)

                Text("You can adjust this anytime in Settings")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, 100)
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
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green.gradient)

                    Text("Your Warning Signs")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("\(selectedComponents.count) patterns selected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)

                if selectedComponents.isEmpty {
                    emptySelectionView
                } else {
                    selectedComponentsList
                }
            }
            .padding(.bottom, 100)
        }
    }

    private var emptySelectionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)

            Text("No warning signs selected")
                .font(.headline)

            Text("Please go back and select at least 2 warning signs that feel familiar to you.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private var selectedComponentsList: some View {
        VStack(spacing: 12) {
            ForEach(SignatureComponentCategory.allCases, id: \.self) { category in
                let categoryComponents = selectedComponents.compactMap { id in
                    SignatureComponent.library.first { $0.id == id && $0.category == category }
                }

                if !categoryComponents.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(category.displayName, systemImage: category.icon)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        ForEach(categoryComponents) { component in
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.purple)
                                Text(component.displayName)
                                    .font(.subheadline)
                                Spacer()
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Navigation

    private var navigationButtons: some View {
        HStack(spacing: 16) {
            if currentStep != .introduction {
                Button {
                    withAnimation {
                        currentStep = OnboardingStep(rawValue: currentStep.rawValue - 1) ?? .introduction
                    }
                } label: {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray5))
                    .foregroundStyle(.primary)
                    .cornerRadius(12)
                }
            }

            Button {
                if currentStep == .summary {
                    createSignature()
                } else {
                    withAnimation {
                        currentStep = OnboardingStep(rawValue: currentStep.rawValue + 1) ?? .summary
                    }
                }
            } label: {
                HStack {
                    if isCreating {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(currentStep == .summary ? "Create My Signature" : "Continue")
                        if currentStep != .summary {
                            Image(systemName: "chevron.right")
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(canProceed ? Color.purple : Color.gray)
                .foregroundStyle(.white)
                .cornerRadius(12)
            }
            .disabled(!canProceed || isCreating)
        }
        .padding()
        .background(.ultraThinMaterial)
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
