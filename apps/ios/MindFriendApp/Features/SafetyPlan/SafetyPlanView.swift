import SwiftUI

// MARK: - Safety Plan View

struct SafetyPlanView: View {
    @EnvironmentObject var container: DependencyContainer
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel: SafetyPlanViewModel

    @State private var showingCondensedView = false
    @State private var showingEditMode = false

    init() {
        _viewModel = StateObject(wrappedValue: SafetyPlanViewModel())
    }

    /// Set by the stable shell so pushed work adds no second NavigationStack; standalone callers keep their own.
    @Environment(\.supportRootEmbedded) private var supportEmbedded

    var body: some View {
        SupportRootNavigation(embedded: supportEmbedded) {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading...")
                } else if viewModel.hasExistingPlan {
                    planSummaryView
                } else {
                    wizardIntroView
                }
            }
            .supportScreen()
            .foregroundStyle(SupportTheme.textPrimary)
            .navigationTitle("Safety Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.hasExistingPlan {
                        Button {
                            showingEditMode = true
                        } label: {
                            Text("Edit")
                                .foregroundStyle(SupportTheme.textSecondary)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingCondensedView) {
                SafetyPlanCondensedView(
                    payload: viewModel.payload,
                    settings: viewModel.settings,
                    isStale: viewModel.isCacheStale
                )
            }
            .sheet(isPresented: $showingEditMode) {
                SafetyPlanWizardView(payload: viewModel.payload) { updatedPayload in
                    await viewModel.updatePlan(container: container, payload: updatedPayload)
                }
            }
            .task {
                await viewModel.loadPlan(container: container)
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage)
            }
        }
    }

    // MARK: - Wizard Intro View

    private var wizardIntroView: some View {
        VStack(spacing: SupportTheme.Spacing.l) {
            Spacer()

            Image(systemName: "shield.checkered")
                .font(.system(size: 80))
                .foregroundStyle(SupportTheme.Area.safety.palette.ink)

            VStack(spacing: SupportTheme.Spacing.s) {
                Text("Create Your Safety Plan")
                    .font(.title2)
                    .accessibilityAddTraits(.isHeader)
                    .fontWeight(.semibold)

                Text(
                    "A personal safety plan helps you take safe actions during difficult moments. It's private, stored securely, and available offline."
                )
                .font(.body)
                .foregroundStyle(SupportTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SupportTheme.Spacing.xl)
            }

            VStack(spacing: SupportTheme.Spacing.xs) {
                HStack(spacing: SupportTheme.Spacing.s) {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(SupportTheme.Area.safety.palette.ink)
                    Text("5-8 minutes to create")
                        .font(.subheadline)
                }

                HStack(spacing: SupportTheme.Spacing.s) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(SupportTheme.Status.positive)
                    Text("Private and protected")
                        .font(.subheadline)
                }

                HStack(spacing: SupportTheme.Spacing.s) {
                    Image(systemName: "wifi.slash")
                        .foregroundStyle(SupportTheme.Area.quests.palette.ink)
                    Text("Available offline")
                        .font(.subheadline)
                }
            }
            .foregroundStyle(SupportTheme.textSecondary)

            Spacer()

            Button {
                showingEditMode = true
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(SupportTheme.accent)
                    .foregroundStyle(SupportTheme.onAccent)
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
            }
            .padding(.horizontal, SupportTheme.Spacing.l)
            .padding(.bottom, SupportTheme.Spacing.xl)
        }
    }

    // MARK: - Plan Summary View

    private var planSummaryView: some View {
        List {
            Section {
                Button {
                    showingCondensedView = true
                } label: {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title2)
                            .foregroundStyle(.red)

                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                            Text("I Need Help Now")
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                                .foregroundStyle(SupportTheme.textPrimary)

                            Text("Quick access to your safety resources")
                                .font(.caption)
                                .foregroundStyle(SupportTheme.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                    .padding(.vertical, SupportTheme.Spacing.xs)
                }
            }
            .listRowBackground(SupportTheme.surface)

            Section("Your Plan") {
                if !viewModel.payload.warningSigns.isEmpty {
                    LabeledContent("Warning Signs", value: "\(viewModel.payload.warningSigns.count) items")
                }

                if !viewModel.payload.coping.isEmpty {
                    LabeledContent("Coping Strategies", value: "\(viewModel.payload.coping.count) items")
                }

                if !viewModel.payload.contacts.isEmpty {
                    LabeledContent("Trusted Contacts", value: "\(viewModel.payload.contacts.count) contacts")
                }

                if !viewModel.payload.resources.isEmpty {
                    LabeledContent("Professional Resources", value: "\(viewModel.payload.resources.count) resources")
                }

                if !viewModel.payload.environmentSteps.isEmpty {
                    LabeledContent("Environment Steps", value: "\(viewModel.payload.environmentSteps.count) items")
                }

                if !viewModel.payload.anchors.isEmpty {
                    LabeledContent("Reasons/Anchors", value: "\(viewModel.payload.anchors.count) items")
                }
            }

            .listRowBackground(SupportTheme.surface)

            Section("Settings") {
                Toggle("Allow AI to reference my Safety Plan", isOn: $viewModel.settings.allowAiReference)
                    .onChange(of: viewModel.settings.allowAiReference) { _, newValue in
                        Task {
                            await viewModel.updateSettings(container: container, allowAiReference: newValue)
                        }
                    }

                Toggle("Pin to Quick Actions", isOn: $viewModel.settings.pinnedToQuickActions)
                    .onChange(of: viewModel.settings.pinnedToQuickActions) { _, newValue in
                        Task {
                            await viewModel.updateSettings(container: container, pinnedToQuickActions: newValue)
                        }
                    }
            }

            .listRowBackground(SupportTheme.surface)

            Section {
                Button(role: .destructive) {
                    Task {
                        await viewModel.deletePlan(container: container)
                    }
                } label: {
                    Text("Delete Safety Plan")
                        .foregroundStyle(.red)
                }
            }

            .listRowBackground(SupportTheme.surface)
        }
    }
}

// MARK: - Safety Plan Wizard View

struct SafetyPlanWizardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss

    @State private var currentStep: SafetyPlanWizardStep = .warningSigns
    @State private var payload: SafetyPlanPayload
    @State private var isSaving = false
    @State private var showingSaveSuccess = false

    let onSave: (SafetyPlanPayload) async -> Bool

    init(payload: SafetyPlanPayload, onSave: @escaping (SafetyPlanPayload) async -> Bool) {
        _payload = State(initialValue: payload)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress indicator
                progressView
                    .padding()

                // Step content
                Group {
                    switch currentStep {
                    case .warningSigns:
                        WarningSignsStepView(payload: $payload)
                    case .coping:
                        CopingStepView(payload: $payload)
                    case .contacts:
                        ContactsStepView(payload: $payload)
                    case .resources:
                        ResourcesStepView(payload: $payload)
                    case .environment:
                        EnvironmentStepView(payload: $payload)
                    case .anchors:
                        AnchorsStepView(payload: $payload)
                    case .review:
                        ReviewStepView(payload: payload)
                    }
                }
                .frame(maxHeight: .infinity)

                // Navigation buttons
                navigationButtons
                    .padding()
            }
            .supportScreen()
            .foregroundStyle(SupportTheme.textPrimary)
            .navigationTitle(currentStep.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .overlay {
                if isSaving {
                    SupportTheme.canvas.opacity(0.3)
                        .ignoresSafeArea()
                        .overlay {
                            ProgressView("Saving...")
                                .padding()
                                .background(SupportTheme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
                        }
                }
            }
            .alert("Plan Saved", isPresented: $showingSaveSuccess) {
                Button("Done") {
                    dismiss()
                }
            } message: {
                Text("Your safety plan has been saved.")
            }
        }
    }

    private var progressView: some View {
        HStack(spacing: SupportTheme.Spacing.xxs) {
            ForEach(SafetyPlanWizardStep.allCases, id: \.self) { step in
                Circle()
                    .fill(
                        step.rawValue <= currentStep.rawValue
                            ? SupportTheme.Area.safety.palette.ink : SupportTheme.textSecondary.opacity(0.3)
                    )
                    .frame(width: 8, height: 8)
                    .scaleEffect(reduceMotion ? 1 : (step == currentStep ? 1.2 : 1.0))

                if step != SafetyPlanWizardStep.allCases.last {
                    Rectangle()
                        .fill(
                            step.rawValue < currentStep.rawValue
                                ? SupportTheme.Area.safety.palette.ink : SupportTheme.textSecondary.opacity(0.3)
                        )
                        .frame(height: 2)
                }
            }
        }
    }

    private var navigationButtons: some View {
        HStack(spacing: SupportTheme.Spacing.m) {
            if currentStep != .warningSigns {
                Button {
                    withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .default) {
                        currentStep = currentStep.previous
                    }
                } label: {
                    Text("Back")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(SupportTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
                }
            }

            if currentStep == .review {
                Button {
                    savePlan()
                } label: {
                    Text("Save Plan")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(SupportTheme.accent)
                        .foregroundStyle(SupportTheme.onAccent)
                        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
                }
            } else {
                Button {
                    withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .default) {
                        currentStep = currentStep.next
                    }
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(SupportTheme.accent)
                        .foregroundStyle(SupportTheme.onAccent)
                        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
                }
            }
        }
    }

    private func savePlan() {
        isSaving = true
        Task {
            let success = await onSave(payload)
            await MainActor.run {
                isSaving = false
                if success {
                    showingSaveSuccess = true
                }
            }
        }
    }
}

// MARK: - Wizard Steps

enum SafetyPlanWizardStep: Int, CaseIterable, Identifiable {
    case warningSigns = 0
    case coping = 1
    case contacts = 2
    case resources = 3
    case environment = 4
    case anchors = 5
    case review = 6

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .warningSigns: return "Warning Signs"
        case .coping: return "Coping Strategies"
        case .contacts: return "Trusted Contacts"
        case .resources: return "Professional Resources"
        case .environment: return "Environment"
        case .anchors: return "Reasons & Anchors"
        case .review: return "Review"
        }
    }

    var previous: SafetyPlanWizardStep {
        SafetyPlanWizardStep(rawValue: rawValue - 1) ?? self
    }

    var next: SafetyPlanWizardStep {
        SafetyPlanWizardStep(rawValue: rawValue + 1) ?? self
    }
}

// MARK: - Warning Signs Step

struct WarningSignsStepView: View {
    @Binding var payload: SafetyPlanPayload

    @State private var newItemText = ""

    private let defaultSigns = [
        "Withdrawing from others",
        "Sleep quality decreases",
        "Racing thoughts",
        "Irritability increases",
        "Loss of interest in activities",
        "Feeling overwhelmed",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.l) {
                Text(
                    "What signs indicate your stress is increasing? These are early warnings that help you take action before a crisis."
                )
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)

                // Default items
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                    Text("Common Warning Signs")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)

                    ForEach(defaultSigns, id: \.self) { sign in
                        WarningSignRow(
                            text: sign,
                            isSelected: payload.warningSigns.contains { $0.text == sign },
                            onToggle: {
                                toggleDefaultSign(sign)
                            }
                        )
                    }
                }

                Divider()

                // Custom items
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                    Text("Add Your Own")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)

                    HStack {
                        TextField("Describe your warning sign...", text: $newItemText)
                            .supportField()

                        Button {
                            addCustomSign()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(SupportTheme.Area.safety.palette.ink)
                        }
                        .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                        .accessibilityLabel("Add item")
                        .disabled(newItemText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    if !payload.warningSigns.filter({ !$0.isCustom }).isEmpty {
                        ForEach(payload.warningSigns.filter({ $0.isCustom })) { item in
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(SupportTheme.Area.safety.palette.ink)
                                Text(item.text)
                                    .font(.subheadline)
                                Spacer()
                                Button {
                                    removeCustomSign(item)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(SupportTheme.textSecondary)
                                }
                                .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                                .accessibilityLabel("Close")
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func toggleDefaultSign(_ text: String) {
        if let index = payload.warningSigns.firstIndex(where: { $0.text == text }) {
            payload.warningSigns.remove(at: index)
        } else {
            payload.warningSigns.append(SafetyPlanItem(text: text, isCustom: false))
        }
    }

    private func addCustomSign() {
        let text = newItemText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        payload.warningSigns.append(SafetyPlanItem(text: text, isCustom: true))
        newItemText = ""
    }

    private func removeCustomSign(_ item: SafetyPlanItem) {
        payload.warningSigns.removeAll { $0.id == item.id }
    }
}

struct WarningSignRow: View {
    let text: String
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: SupportTheme.Spacing.s) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? SupportTheme.Area.safety.palette.ink : SupportTheme.textSecondary)

                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textPrimary)

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Coping Step

struct CopingStepView: View {
    @Binding var payload: SafetyPlanPayload

    @State private var showingExercisePicker = false
    @State private var newCustomCoping = ""
    @State private var selectedCategory: CopingCategory = .breathing

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.l) {
                Text(
                    "What actions can you take alone to manage distress? You can link to in-app exercises or add your own strategies."
                )
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)

                // Exercise picker button
                Button {
                    showingExercisePicker = true
                } label: {
                    HStack {
                        Image(systemName: "figure.mind.and.body")
                        Text("Add Exercise")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding()
                    .background(SupportTheme.surface)
                    .foregroundStyle(SupportTheme.Area.safety.palette.ink)
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
                }

                // Favorites section
                if !payload.coping.filter({ $0.isFavorite }).isEmpty {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                        Text("Top Favorites")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)

                        ForEach(payload.coping.filter({ $0.isFavorite })) { coping in
                            CopingRowView(
                                coping: coping,
                                onRemove: {
                                    removeCoping(coping)
                                })
                        }
                    }
                }

                Divider()

                // All coping strategies
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                    Text("All Strategies")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)

                    ForEach(payload.coping) { coping in
                        CopingRowView(
                            coping: coping,
                            onRemove: {
                                removeCoping(coping)
                            })
                    }
                }

                Divider()

                // Add custom coping
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                    Text("Add Custom Strategy")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)

                    Picker("Category", selection: $selectedCategory) {
                        ForEach(CopingCategory.allCases, id: \.self) { category in
                            Label(category.displayName, systemImage: category.icon)
                                .tag(category)
                        }
                    }

                    HStack {
                        TextField("Describe your coping strategy...", text: $newCustomCoping)
                            .supportField()

                        Button {
                            addCustomCoping()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(SupportTheme.Area.safety.palette.ink)
                        }
                        .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                        .accessibilityLabel("Add item")
                        .disabled(newCustomCoping.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .padding()
        }
        .sheet(isPresented: $showingExercisePicker) {
            ExercisePickerView { exercise in
                payload.coping.append(
                    CopingStrategy(
                        type: .exercise,
                        label: exercise.title,
                        duration: exercise.durationSeconds / 60,
                        category: categoryFromExerciseType(exercise.type),
                        exerciseId: exercise.id
                    ))
            }
        }
    }

    private func categoryFromExerciseType(_ type: ExerciseType) -> CopingCategory {
        switch type {
        case .breathing: return .breathing
        case .meditation: return .meditation
        case .grounding: return .grounding
        case .journaling: return .journaling
        case .movement: return .movement
        }
    }

    private func removeCoping(_ coping: CopingStrategy) {
        payload.coping.removeAll { $0.id == coping.id }
    }

    private func addCustomCoping() {
        let text = newCustomCoping.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        payload.coping.append(CopingStrategy.custom(label: text, category: selectedCategory))
        newCustomCoping = ""
    }
}

struct CopingRowView: View {
    let coping: CopingStrategy
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.s) {
            Image(systemName: coping.category.icon)
                .foregroundStyle(SupportTheme.Area.safety.palette.ink)
                .frame(minWidth: 24)

            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(coping.label)
                    .font(.subheadline)

                if let duration = coping.duration {
                    Text("\(duration) min")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
            }

            Spacer()

            if coping.isFavorite {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(SupportTheme.textSecondary)
            }
        }
        .padding(.vertical, SupportTheme.Spacing.xs)
    }
}

// MARK: - Exercise Picker View

struct ExercisePickerView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss

    @State private var exercises: [Exercise] = []
    @State private var selectedType: ExerciseType?

    let onSelect: (Exercise) -> Void

    var filteredExercises: [Exercise] {
        if let type = selectedType {
            return exercises.filter { $0.type == type }
        }
        return exercises
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(ExerciseType.allCases, id: \.self) { type in
                    Section {
                        ForEach(exercises.filter { $0.type == type }) { exercise in
                            Button {
                                onSelect(exercise)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(exercise.title)
                                            .font(.subheadline)
                                        Text("\(exercise.durationSeconds / 60) min")
                                            .font(.caption)
                                            .foregroundStyle(SupportTheme.textSecondary)
                                    }

                                    Spacer()

                                    Image(systemName: type.icon)
                                        .foregroundStyle(SupportTheme.Area.safety.palette.ink)
                                }
                            }
                            .foregroundStyle(SupportTheme.textPrimary)
                        }
                    } header: {
                        Label(type.displayName, systemImage: type.icon)
                    }
                    .listRowBackground(SupportTheme.surface)
                }
            }
            .supportScreen()
            .foregroundStyle(SupportTheme.textPrimary)
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                exercises = (try? await container.supabaseDataService.getExercises()) ?? []
            }
        }
    }
}

// MARK: - Contacts Step

struct ContactsStepView: View {
    @Binding var payload: SafetyPlanPayload

    @State private var showingAddContact = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.l) {
                Text("Who can you reach out to during difficult moments? Add up to 3 trusted contacts.")
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textSecondary)

                if payload.contacts.count < 3 {
                    Button {
                        showingAddContact = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Contact")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(SupportTheme.accent)
                        .foregroundStyle(SupportTheme.onAccent)
                        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
                    }
                }

                if payload.contacts.isEmpty {
                    ContentUnavailableView(
                        "No Contacts Added",
                        systemImage: "person.crop.circle.badge.plus",
                        description: Text("Add trusted contacts who can support you during difficult moments.")
                    )
                } else {
                    ForEach(payload.contacts) { contact in
                        ContactRowView(
                            contact: contact,
                            onRemove: {
                                payload.contacts.removeAll { $0.id == contact.id }
                            })
                    }
                }
            }
            .padding()
        }
        .sheet(isPresented: $showingAddContact) {
            AddContactView { contact in
                payload.contacts.append(contact)
            }
            .presentationDetents([.medium])
        }
    }
}

struct ContactRowView: View {
    let contact: TrustedContact
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            HStack {
                Text(contact.name)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                if contact.isPrimary {
                    Text("Primary")
                        .font(.caption)
                        .padding(.horizontal, SupportTheme.Spacing.xs)
                        .padding(.vertical, SupportTheme.Spacing.xxs)
                        .background(SupportTheme.accent)
                        .foregroundStyle(SupportTheme.onAccent)
                        .clipShape(Capsule())
                }

                Spacer()

                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
            }

            HStack(spacing: SupportTheme.Spacing.m) {
                Label(contact.formattedPhone, systemImage: "phone.fill")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)

                Label(contact.relationship.displayName, systemImage: "person.fill")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }

            if let whatToSay = contact.whatToSay {
                Text("\"\(whatToSay)\"")
                    .font(.caption)
                    .italic()
                    .foregroundStyle(SupportTheme.textSecondary)
            }
        }
        .padding()
        .background(SupportTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
    }
}

struct AddContactView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var phone = ""
    @State private var relationship: TrustedContactRelationship = .friend
    @State private var preferredMethod: ContactMethod = .call
    @State private var whatToSay = ""

    let onAdd: (TrustedContact) -> Void

    // MARK: - Phone Validation

    private func isValidPhone(_ phone: String) -> Bool {
        let phonePattern = #"^\+[1-9]\d{6,14}$"#
        return phone.range(of: phonePattern, options: .regularExpression) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Contact Info") {
                    TextField("Name", text: $name)
                        .textContentType(.name)

                    TextField("Phone (+1234567890)", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)

                    Picker("Relationship", selection: $relationship) {
                        ForEach(TrustedContactRelationship.allCases, id: \.self) { rel in
                            Text(rel.displayName).tag(rel)
                        }
                    }

                    Picker("Preferred Contact", selection: $preferredMethod) {
                        Text("Call").tag(ContactMethod.call)
                        Text("Text").tag(ContactMethod.text)
                    }
                }
                .listRowBackground(SupportTheme.surface)

                Section("What to Say (Optional)") {
                    TextField("Guidance for how they can help...", text: $whatToSay, axis: .vertical)
                        .lineLimit(3...6)
                }

                .listRowBackground(SupportTheme.surface)

                Section {
                    Text("This contact will only be visible to you and accessible during emergencies.")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }

                .listRowBackground(SupportTheme.surface)
            }
            .supportScreen()
            .foregroundStyle(SupportTheme.textPrimary)
            .navigationTitle("Add Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        let contact = TrustedContact(
                            name: name,
                            phone: phone.hasPrefix("+") ? phone : "+\(phone)",
                            relationship: relationship,
                            preferredMethod: preferredMethod,
                            whatToSay: whatToSay.isEmpty ? nil : whatToSay
                        )
                        onAdd(contact)
                        dismiss()
                    }
                    .disabled(name.isEmpty || !isValidPhone(phone))
                }
            }
        }
    }
}

// MARK: - Resources Step

struct ResourcesStepView: View {
    @Binding var payload: SafetyPlanPayload

    @State private var showingAddTherapist = false

    // Default crisis resources
    private let defaultResources: [ProfessionalResource] = [
        ProfessionalResource(type: .hotline, name: "988 Suicide & Crisis Lifeline", phone: "988", country: "US"),
        ProfessionalResource(type: .crisisLine, name: "Crisis Text Line", phone: "741741", country: "US"),
        ProfessionalResource(
            type: .hotline, name: "International Association for Suicide Prevention", phone: "+442329516889",
            country: "International"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.l) {
                Text("Crisis hotlines and professional resources. These are always available.")
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textSecondary)

                // Default crisis resources
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                    Text("Crisis Resources")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)

                    ForEach(defaultResources) { resource in
                        ResourceRowView(resource: resource)
                    }
                }

                Divider()

                // Custom resources
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                    HStack {
                        Text("My Professional Resources")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)

                        Spacer()

                        Button {
                            showingAddTherapist = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                        .accessibilityLabel("Add item")
                    }

                    if payload.resources.isEmpty {
                        Text("No custom resources added. Add your therapist or other professionals.")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    } else {
                        ForEach(payload.resources) { resource in
                            ResourceRowView(
                                resource: resource,
                                onRemove: {
                                    payload.resources.removeAll { $0.id == resource.id }
                                })
                        }
                    }
                }
            }
            .padding()
        }
        .sheet(isPresented: $showingAddTherapist) {
            AddTherapistView { resource in
                payload.resources.append(resource)
            }
            .presentationDetents([.medium])
        }
    }
}

struct ResourceRowView: View {
    let resource: ProfessionalResource
    var onRemove: (() -> Void)?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(resource.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if !resource.phone.isEmpty {
                    Text(resource.phone)
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
            }

            Spacer()

            if !resource.phone.isEmpty {
                Link(destination: URL(string: "tel://\(resource.phone.replacingOccurrences(of: "+", with: ""))")!) {
                    Image(systemName: "phone.fill")
                        .foregroundStyle(SupportTheme.accent)
                }
            }

            if let onRemove = onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(SupportTheme.textSecondary)
                }
            }
        }
        .padding()
        .background(SupportTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
    }
}

struct AddTherapistView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var phone = ""
    @State private var notes = ""

    let onAdd: (ProfessionalResource) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Therapist Info") {
                    TextField("Name", text: $name)
                        .textContentType(.name)

                    TextField("Phone (+1234567890)", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                }
                .listRowBackground(SupportTheme.surface)

                Section("Notes (Optional)") {
                    TextField("Notes...", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                .listRowBackground(SupportTheme.surface)
            }
            .supportScreen()
            .foregroundStyle(SupportTheme.textPrimary)
            .navigationTitle("Add Therapist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        let resource = ProfessionalResource(
                            type: .therapist,
                            name: name,
                            phone: phone.hasPrefix("+") ? phone : "+\(phone)",
                            description: notes.isEmpty ? nil : notes
                        )
                        onAdd(resource)
                        dismiss()
                    }
                    .disabled(name.isEmpty || phone.isEmpty)
                }
            }
        }
    }
}

// MARK: - Environment Step

struct EnvironmentStepView: View {
    @Binding var payload: SafetyPlanPayload

    private let defaultSteps = [
        "Move to a brighter room",
        "Remove triggers from reach",
        "Go to a safe place",
        "Put on calming music",
        "Adjust the lighting",
        "Open a window for fresh air",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.l) {
                Text(
                    "What actions can you take to create physical safety? Simple steps to make your environment safer."
                )
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)

                VStack(spacing: SupportTheme.Spacing.s) {
                    ForEach(defaultSteps, id: \.self) { step in
                        EnvironmentStepRow(
                            text: step,
                            isSelected: payload.environmentSteps.contains { $0.text == step },
                            onToggle: {
                                toggleStep(step)
                            }
                        )
                    }
                }
            }
            .padding()
        }
    }

    private func toggleStep(_ text: String) {
        if let index = payload.environmentSteps.firstIndex(where: { $0.text == text }) {
            payload.environmentSteps.remove(at: index)
        } else {
            payload.environmentSteps.append(SafetyPlanItem(text: text, isCustom: false))
        }
    }
}

struct EnvironmentStepRow: View {
    let text: String
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: SupportTheme.Spacing.s) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? SupportTheme.Area.safety.palette.ink : SupportTheme.textSecondary)

                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textPrimary)

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Anchors Step

struct AnchorsStepView: View {
    @Binding var payload: SafetyPlanPayload

    @State private var newAnchor = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.l) {
                Text(
                    "What motivates you to stay safe? Personal reasons, future plans, or values that anchor you. This section is optional."
                )
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)

                VStack(spacing: SupportTheme.Spacing.s) {
                    HStack {
                        TextField("What are you protecting?", text: $newAnchor)
                            .supportField()

                        Button {
                            addAnchor()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(SupportTheme.Area.safety.palette.ink)
                        }
                        .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                        .accessibilityLabel("Add item")
                        .disabled(newAnchor.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    if !payload.anchors.isEmpty {
                        ForEach(payload.anchors) { anchor in
                            HStack {
                                Image(systemName: "heart.fill")
                                    .foregroundStyle(SupportTheme.Area.quests.palette.ink)

                                Text(anchor.text)
                                    .font(.subheadline)

                                Spacer()

                                Button {
                                    payload.anchors.removeAll { $0.id == anchor.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(SupportTheme.textSecondary)
                                }
                                .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                                .accessibilityLabel("Close")
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func addAnchor() {
        let text = newAnchor.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        payload.anchors.append(SafetyPlanItem(text: text))
        newAnchor = ""
    }
}

// MARK: - Review Step

struct ReviewStepView: View {
    let payload: SafetyPlanPayload

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.l) {
                Text("Review your safety plan before saving.")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                ReviewSection(
                    title: "Warning Signs (\(payload.warningSigns.count))", items: payload.warningSigns.map(\.text))
                ReviewSection(title: "Coping Strategies (\(payload.coping.count))", items: payload.coping.map(\.label))
                ReviewSection(
                    title: "Trusted Contacts (\(payload.contacts.count))", items: payload.contacts.map(\.name))
                ReviewSection(
                    title: "Environment Steps (\(payload.environmentSteps.count))",
                    items: payload.environmentSteps.map(\.text))
                if !payload.anchors.isEmpty {
                    ReviewSection(
                        title: "Reasons/Anchors (\(payload.anchors.count))", items: payload.anchors.map(\.text))
                }
            }
            .padding()
        }
    }
}

struct ReviewSection: View {
    let title: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            ForEach(items, id: \.self) { item in
                HStack(spacing: SupportTheme.Spacing.xs) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 4))
                    Text(item)
                        .font(.subheadline)
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
    #Preview {
        SafetyPlanView()
            .environmentObject(DependencyContainer.shared)
            .environmentObject(AppState())
    }
#endif
