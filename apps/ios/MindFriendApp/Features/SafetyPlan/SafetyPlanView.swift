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

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading...")
                } else if viewModel.hasExistingPlan {
                    planSummaryView
                } else {
                    wizardIntroView
                }
            }
            .navigationTitle("Safety Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.hasExistingPlan {
                        Button {
                            showingEditMode = true
                        } label: {
                            Text("Edit")
                                .foregroundStyle(.secondary)
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
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "shield.checkered")
                .font(.system(size: 80))
                .foregroundStyle(.blue)

            VStack(spacing: 12) {
                Text("Create Your Safety Plan")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("A personal safety plan helps you take safe actions during difficult moments. It's private, stored securely, and available offline.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(.blue)
                    Text("5-8 minutes to create")
                        .font(.subheadline)
                }

                HStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.green)
                    Text("Private and protected")
                        .font(.subheadline)
                }

                HStack(spacing: 12) {
                    Image(systemName: "wifi.slash")
                        .foregroundStyle(.orange)
                    Text("Available offline")
                        .font(.subheadline)
                }
            }
            .foregroundStyle(.secondary)

            Spacer()

            Button {
                showingEditMode = true
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
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

                        VStack(alignment: .leading, spacing: 2) {
                            Text("I Need Help Now")
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Text("Quick access to your safety resources")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 8)
                }
            }

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
        }
    }
}

// MARK: - Safety Plan Wizard View

struct SafetyPlanWizardView: View {
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
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .overlay {
                            ProgressView("Saving...")
                                .padding()
                                .background(.regularMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
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
        HStack(spacing: 4) {
            ForEach(SafetyPlanWizardStep.allCases, id: \.self) { step in
                Circle()
                    .fill(step.rawValue <= currentStep.rawValue ? Color.blue : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .scaleEffect(step == currentStep ? 1.2 : 1.0)

                if step != SafetyPlanWizardStep.allCases.last {
                    Rectangle()
                        .fill(step.rawValue < currentStep.rawValue ? Color.blue : Color.gray.opacity(0.3))
                        .frame(height: 2)
                }
            }
        }
    }

    private var navigationButtons: some View {
        HStack(spacing: 16) {
            if currentStep != .warningSigns {
                Button {
                    withAnimation {
                        currentStep = currentStep.previous
                    }
                } label: {
                    Text("Back")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            if currentStep == .review {
                Button {
                    savePlan()
                } label: {
                    Text("Save Plan")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            } else {
                Button {
                    withAnimation {
                        currentStep = currentStep.next
                    }
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
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
        "Feeling overwhelmed"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("What signs indicate your stress is increasing? These are early warnings that help you take action before a crisis.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Default items
                VStack(alignment: .leading, spacing: 12) {
                    Text("Common Warning Signs")
                        .font(.headline)

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
                VStack(alignment: .leading, spacing: 12) {
                    Text("Add Your Own")
                        .font(.headline)

                    HStack {
                        TextField("Describe your warning sign...", text: $newItemText)
                            .textFieldStyle(.roundedBorder)

                        Button {
                            addCustomSign()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.blue)
                        }
                        .disabled(newItemText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    if !payload.warningSigns.filter({ !$0.isCustom }).isEmpty {
                        ForEach(payload.warningSigns.filter({ $0.isCustom })) { item in
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                                Text(item.text)
                                    .font(.subheadline)
                                Spacer()
                                Button {
                                    removeCustomSign(item)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
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
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)

                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

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
            VStack(alignment: .leading, spacing: 20) {
                Text("What actions can you take alone to manage distress? You can link to in-app exercises or add your own strategies.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

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
                    .background(Color.blue.opacity(0.1))
                    .foregroundStyle(.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Favorites section
                if !payload.coping.filter({ $0.isFavorite }).isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Top Favorites")
                            .font(.headline)

                        ForEach(payload.coping.filter({ $0.isFavorite })) { coping in
                            CopingRowView(coping: coping, onRemove: {
                                removeCoping(coping)
                            })
                        }
                    }
                }

                Divider()

                // All coping strategies
                VStack(alignment: .leading, spacing: 12) {
                    Text("All Strategies")
                        .font(.headline)

                    ForEach(payload.coping) { coping in
                        CopingRowView(coping: coping, onRemove: {
                            removeCoping(coping)
                        })
                    }
                }

                Divider()

                // Add custom coping
                VStack(alignment: .leading, spacing: 12) {
                    Text("Add Custom Strategy")
                        .font(.headline)

                    Picker("Category", selection: $selectedCategory) {
                        ForEach(CopingCategory.allCases, id: \.self) { category in
                            Label(category.displayName, systemImage: category.icon)
                                .tag(category)
                        }
                    }

                    HStack {
                        TextField("Describe your coping strategy...", text: $newCustomCoping)
                            .textFieldStyle(.roundedBorder)

                        Button {
                            addCustomCoping()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.blue)
                        }
                        .disabled(newCustomCoping.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .padding()
        }
        .sheet(isPresented: $showingExercisePicker) {
            ExercisePickerView { exercise in
                payload.coping.append(CopingStrategy(
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
        HStack(spacing: 12) {
            Image(systemName: coping.category.icon)
                .foregroundStyle(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(coping.label)
                    .font(.subheadline)

                if let duration = coping.duration {
                    Text("\(duration) min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if coping.isFavorite {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
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
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Image(systemName: type.icon)
                                        .foregroundStyle(.blue)
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    } header: {
                        Label(type.displayName, systemImage: type.icon)
                    }
                }
            }
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
            VStack(alignment: .leading, spacing: 20) {
                Text("Who can you reach out to during difficult moments? Add up to 3 trusted contacts.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

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
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                        ContactRowView(contact: contact, onRemove: {
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(contact.name)
                    .font(.headline)

                if contact.isPrimary {
                    Text("Primary")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }

                Spacer()

                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
            }

            HStack(spacing: 16) {
                Label(contact.formattedPhone, systemImage: "phone.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label(contact.relationship.displayName, systemImage: "person.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let whatToSay = contact.whatToSay {
                Text("\"\(whatToSay)\"")
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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

                Section("What to Say (Optional)") {
                    TextField("Guidance for how they can help...", text: $whatToSay, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Text("This contact will only be visible to you and accessible during emergencies.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
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
        ProfessionalResource(type: .hotline, name: "International Association for Suicide Prevention", phone: "+442329516889", country: "International")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Crisis hotlines and professional resources. These are always available.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Default crisis resources
                VStack(alignment: .leading, spacing: 12) {
                    Text("Crisis Resources")
                        .font(.headline)

                    ForEach(defaultResources) { resource in
                        ResourceRowView(resource: resource)
                    }
                }

                Divider()

                // Custom resources
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("My Professional Resources")
                            .font(.headline)

                        Spacer()

                        Button {
                            showingAddTherapist = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                    }

                    if payload.resources.isEmpty {
                        Text("No custom resources added. Add your therapist or other professionals.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(payload.resources) { resource in
                            ResourceRowView(resource: resource, onRemove: {
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
            VStack(alignment: .leading, spacing: 4) {
                Text(resource.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if !resource.phone.isEmpty {
                    Text(resource.phone)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if !resource.phone.isEmpty {
                Link(destination: URL(string: "tel://\(resource.phone.replacingOccurrences(of: "+", with: ""))")!) {
                    Image(systemName: "phone.fill")
                        .foregroundStyle(.blue)
                }
            }

            if let onRemove = onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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

                Section("Notes (Optional)") {
                    TextField("Notes...", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
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
        "Open a window for fresh air"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("What actions can you take to create physical safety? Simple steps to make your environment safer.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
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
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .green : .secondary)

                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

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
            VStack(alignment: .leading, spacing: 20) {
                Text("What motivates you to stay safe? Personal reasons, future plans, or values that anchor you. This section is optional.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    HStack {
                        TextField("What are you protecting?", text: $newAnchor)
                            .textFieldStyle(.roundedBorder)

                        Button {
                            addAnchor()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.blue)
                        }
                        .disabled(newAnchor.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    if !payload.anchors.isEmpty {
                        ForEach(payload.anchors) { anchor in
                            HStack {
                                Image(systemName: "heart.fill")
                                    .foregroundStyle(.pink)

                                Text(anchor.text)
                                    .font(.subheadline)

                                Spacer()

                                Button {
                                    payload.anchors.removeAll { $0.id == anchor.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
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
            VStack(alignment: .leading, spacing: 24) {
                Text("Review your safety plan before saving.")
                    .font(.headline)

                ReviewSection(title: "Warning Signs (\(payload.warningSigns.count))", items: payload.warningSigns.map(\.text))
                ReviewSection(title: "Coping Strategies (\(payload.coping.count))", items: payload.coping.map(\.label))
                ReviewSection(title: "Trusted Contacts (\(payload.contacts.count))", items: payload.contacts.map(\.name))
                ReviewSection(title: "Environment Steps (\(payload.environmentSteps.count))", items: payload.environmentSteps.map(\.text))
                if !payload.anchors.isEmpty {
                    ReviewSection(title: "Reasons/Anchors (\(payload.anchors.count))", items: payload.anchors.map(\.text))
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
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            ForEach(items, id: \.self) { item in
                HStack(spacing: 8) {
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
