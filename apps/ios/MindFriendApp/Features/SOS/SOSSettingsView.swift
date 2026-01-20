// SOSSettingsView.swift
// MindFriend - SOS Feature Settings

import SwiftUI

/// Settings view for configuring SOS feature preferences
struct SOSSettingsView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss

    var sosCoordinator: SOSCoordinator {
        container.sosCoordinator
    }

    @State private var settings: SOSSettings?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var showEmergencyContactSheet = false
    @State private var errorMessage: String?

    // Local state for editing
    @State private var enableSOS = true
    @State private var selectedPattern: BreathingPattern = .calm478
    @State private var autoNotifyContacts = false
    @State private var countdownSeconds = 3
    @State private var includeBreathing = true
    @State private var includeGrounding = true
    @State private var emergencyContactName: String?
    @State private var emergencyContactPhone: String?

    var body: some View {
        List {
            // Enable SOS Section
            Section {
                Toggle("Enable SOS Button", isOn: $enableSOS)
                    .tint(.blue)
            } header: {
                Text("General")
            } footer: {
                Text("When enabled, the SOS button appears on your home screen for quick access to calming exercises.")
            }

            // Breathing Pattern Section
            Section {
                Picker("Breathing Pattern", selection: $selectedPattern) {
                    ForEach(BreathingPattern.allCases) { pattern in
                        VStack(alignment: .leading) {
                            Text(pattern.displayName)
                            Text(pattern.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(pattern)
                    }
                }
                .pickerStyle(.navigationLink)
            } header: {
                Text("Breathing Exercise")
            } footer: {
                Text(selectedPattern.description)
            }

            // Intervention Flow Section
            Section {
                Toggle("Include Breathing Exercise", isOn: $includeBreathing)
                    .tint(.blue)

                Toggle("Include Grounding Exercise", isOn: $includeGrounding)
                    .tint(.blue)
            } header: {
                Text("Intervention Flow")
            } footer: {
                Text("Customize which calming exercises are included in your SOS intervention.")
            }

            // Emergency Contact Section
            Section {
                if let name = emergencyContactName, let phone = emergencyContactPhone {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(name)
                                .font(.body)
                            Text(phone)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("Edit") {
                            showEmergencyContactSheet = true
                        }
                        .foregroundStyle(.blue)
                    }
                } else {
                    Button {
                        showEmergencyContactSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "person.badge.plus")
                            Text("Add Emergency Contact")
                        }
                    }
                }

                Toggle("Auto-notify after countdown", isOn: $autoNotifyContacts)
                    .tint(.blue)
                    .disabled(emergencyContactName == nil)

                if autoNotifyContacts && emergencyContactName != nil {
                    Stepper("Countdown: \(countdownSeconds) seconds", value: $countdownSeconds, in: 3...10)
                }
            } header: {
                Text("Emergency Contact")
            } footer: {
                if autoNotifyContacts && emergencyContactName != nil {
                    Text("When you use SOS, your emergency contact will receive a text message after \(countdownSeconds) seconds unless you cancel.")
                } else {
                    Text("Optional: Add a trusted person who can be notified when you use the SOS feature.")
                }
            }

            // Privacy Section
            Section {
                NavigationLink {
                    SOSPrivacyInfoView()
                } label: {
                    Label("Privacy Information", systemImage: "lock.shield")
                }

                NavigationLink {
                    SOSHistoryView()
                } label: {
                    Label("View SOS History", systemImage: "clock.arrow.circlepath")
                }
            } header: {
                Text("Privacy & Data")
            }

            // Test Section
            Section {
                Button {
                    testSOSButton()
                } label: {
                    HStack {
                        Image(systemName: "play.circle")
                        Text("Test SOS Flow")
                    }
                }
            } header: {
                Text("Testing")
            } footer: {
                Text("Try the SOS flow without logging any events or notifying contacts.")
            }
        }
        .navigationTitle("SOS Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") {
                        saveSettings()
                    }
                    .disabled(!hasChanges)
                }
            }
        }
        .sheet(isPresented: $showEmergencyContactSheet) {
            EmergencyContactSheet(
                name: $emergencyContactName,
                phone: $emergencyContactPhone
            )
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            await loadSettings()
        }
    }

    private var hasChanges: Bool {
        guard let settings else { return true }
        return settings.sosEnabled != enableSOS ||
            settings.preferredBreathingPattern != selectedPattern ||
            settings.autoNotifyContacts != autoNotifyContacts ||
            settings.countdownSeconds != countdownSeconds ||
            settings.includeBreathing != includeBreathing ||
            settings.includeGrounding != includeGrounding ||
            settings.emergencyContactName != emergencyContactName ||
            settings.emergencyContactPhone != emergencyContactPhone
    }

    private func loadSettings() async {
        isLoading = true
        defer { isLoading = false }

        // Load from coordinator (which caches settings)
        if let existing = sosCoordinator.settings {
            applySettings(existing)
        } else {
            // Use defaults with placeholder userId (will be set properly when saving)
            let defaults = SOSSettings(
                userId: UUID().uuidString,
                sosEnabled: true,
                autoNotifyEnabled: false,
                preferredBreathingPattern: .calm478,
                countdownSeconds: 3,
                includeBreathing: true,
                includeGrounding: true
            )
            applySettings(defaults)
        }
    }

    private func applySettings(_ s: SOSSettings) {
        settings = s
        enableSOS = s.sosEnabled
        selectedPattern = s.preferredBreathingPattern
        autoNotifyContacts = s.autoNotifyContacts
        countdownSeconds = s.countdownSeconds
        includeBreathing = s.includeBreathing
        includeGrounding = s.includeGrounding
        emergencyContactName = s.emergencyContactName
        emergencyContactPhone = s.emergencyContactPhone
    }

    private func saveSettings() {
        isSaving = true

        Task {
            do {
                let updated = SOSSettings(
                    id: settings?.id,
                    userId: settings?.userId ?? UUID().uuidString,
                    sosEnabled: enableSOS,
                    autoNotifyEnabled: autoNotifyContacts,
                    emergencyContactName: emergencyContactName,
                    emergencyContactPhone: emergencyContactPhone,
                    preferredBreathingPattern: selectedPattern,
                    countdownSeconds: countdownSeconds,
                    includeBreathing: includeBreathing,
                    includeGrounding: includeGrounding
                )

                try await sosCoordinator.updateSettings(updated)
                isSaving = false
                dismiss()
            } catch {
                errorMessage = "Failed to save settings: \(error.localizedDescription)"
                isSaving = false
            }
        }
    }

    private func testSOSButton() {
        // Show a test version of the intervention
        sosCoordinator.startTestMode()
    }
}

// MARK: - Emergency Contact Sheet

struct EmergencyContactSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var name: String?
    @Binding var phone: String?

    @State private var editName = ""
    @State private var editPhone = ""
    @FocusState private var focusedField: Field?

    enum Field {
        case name, phone
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Contact Name", text: $editName)
                        .textContentType(.name)
                        .focused($focusedField, equals: .name)

                    TextField("Phone Number", text: $editPhone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                        .focused($focusedField, equals: .phone)
                } header: {
                    Text("Emergency Contact")
                } footer: {
                    Text("This person can be automatically notified when you use the SOS feature.")
                }

                if name != nil {
                    Section {
                        Button(role: .destructive) {
                            name = nil
                            phone = nil
                            dismiss()
                        } label: {
                            HStack {
                                Spacer()
                                Text("Remove Contact")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Emergency Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        name = editName.isEmpty ? nil : editName
                        phone = editPhone.isEmpty ? nil : editPhone
                        dismiss()
                    }
                    .disabled(editName.isEmpty || editPhone.isEmpty)
                }
            }
            .onAppear {
                editName = name ?? ""
                editPhone = phone ?? ""
                focusedField = .name
            }
        }
    }
}

// MARK: - Privacy Info View

struct SOSPrivacyInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.blue)

                    Text("Your Privacy Matters")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Here's how we handle your SOS data")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Data stored
                VStack(alignment: .leading, spacing: 12) {
                    Text("What we store")
                        .font(.headline)

                    BulletPoint("When you use the SOS feature")
                    BulletPoint("Which exercises you complete")
                    BulletPoint("Your helpfulness ratings")
                    BulletPoint("Your mood before and after")
                }

                // Why
                VStack(alignment: .leading, spacing: 12) {
                    Text("Why we store this")
                        .font(.headline)

                    BulletPoint("To track what helps you most")
                    BulletPoint("To personalize recommendations")
                    BulletPoint("To show you patterns over time")
                }

                // What we don't store
                VStack(alignment: .leading, spacing: 12) {
                    Text("What we don't store")
                        .font(.headline)

                    BulletPoint("Exact location data")
                    BulletPoint("Recording of your sessions")
                    BulletPoint("Your conversations during crisis")
                }

                // Control
                VStack(alignment: .leading, spacing: 12) {
                    Text("You're in control")
                        .font(.headline)

                    BulletPoint("View your history anytime")
                    BulletPoint("Delete individual entries")
                    BulletPoint("Export or delete all data")
                }

                Spacer(minLength: 40)
            }
            .padding(24)
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - History View

struct SOSHistoryView: View {
    @EnvironmentObject var container: DependencyContainer
    @State private var events: [SOSEvent] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if events.isEmpty {
                ContentUnavailableView(
                    "No History",
                    systemImage: "heart.circle",
                    description: Text("Your SOS usage history will appear here.")
                )
            } else {
                List {
                    ForEach(events) { event in
                        SOSHistoryRow(event: event)
                    }
                }
            }
        }
        .navigationTitle("SOS History")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadHistory()
        }
    }

    private func loadHistory() async {
        isLoading = true
        defer { isLoading = false }

        // Load from coordinator
        events = await container.sosCoordinator.fetchRecentEvents(limit: 50)
    }
}

private struct SOSHistoryRow: View {
    let event: SOSEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(event.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                if event.completedSuccessfully {
                    Label("Completed", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Label("Cancelled", systemImage: "xmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let moodBefore = event.moodBefore, let moodAfter = event.moodAfter {
                HStack {
                    Text("Mood: \(moodEmoji(for: moodBefore)) → \(moodEmoji(for: moodAfter))")
                        .font(.body)
                }
            }

            if let rating = event.helpfulnessRating {
                HStack {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.caption)
                            .foregroundStyle(star <= rating ? .yellow : .secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func moodEmoji(for mood: Int) -> String {
        switch mood {
        case 1: return "😢"
        case 2: return "😕"
        case 3: return "😐"
        case 4: return "🙂"
        case 5: return "😌"
        default: return "😐"
        }
    }
}

#Preview {
    NavigationStack {
        SOSSettingsView()
            .environmentObject(DependencyContainer.preview)
    }
}
