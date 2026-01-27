import SwiftUI

/// Settings view for managing predictive intervention preferences
/// Emphasizes privacy and user control with clear opt-in
struct PredictionSettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer

    @State private var settings: PredictionSettings = .defaults
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var showDataInfo = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading settings...")
            } else {
                settingsList
            }
        }
        .navigationTitle("Wellness Predictions")
        .task { await loadSettings() }
        .alert("Delete Prediction Data?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All Data", role: .destructive) {
                Task { await deleteAllData() }
            }
        } message: {
            Text("This will permanently delete all your prediction data, including risk assessments, signals, and intervention history. This cannot be undone.")
        }
        .sheet(isPresented: $showDataInfo) {
            DataInfoSheet()
        }
        .trackScreen("prediction_settings")
    }

    private var settingsList: some View {
        List {
            // Privacy-focused info section
            infoSection

            // Main opt-in toggle
            optInSection

            if settings.predictionsEnabled {
                // Data sources
                dataSourcesSection

                // Intervention preferences
                interventionSection

                // Family alerts
                familySection

                // Data management
                dataManagementSection
            }
        }
    }

    // MARK: - Sections

    private var infoSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.purple.opacity(0.15))
                            .frame(width: 44, height: 44)

                        Image(systemName: "sparkles")
                            .foregroundStyle(.purple)
                            .font(.title3)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Wellness Predictions")
                            .font(.headline)
                        Text("Get proactive support before you need it")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("MindFriend can analyze your patterns to predict when you might need extra support, and reach out proactively with helpful resources.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    showDataInfo = true
                } label: {
                    HStack {
                        Image(systemName: "lock.shield")
                        Text("How we protect your data")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var optInSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { settings.predictionsEnabled },
                set: { newValue in
                    settings.predictionsEnabled = newValue
                    saveSettings()
                }
            )) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Predictions")
                        Text(settings.predictionsEnabled ? "Active" : "Off")
                            .font(.caption)
                            .foregroundStyle(settings.predictionsEnabled ? .green : .secondary)
                    }
                } icon: {
                    Image(systemName: settings.predictionsEnabled ? "brain.fill" : "brain")
                        .foregroundStyle(settings.predictionsEnabled ? .purple : .gray)
                }
            }
        } footer: {
            Text("When enabled, we'll analyze your patterns to provide proactive support. You can disable this at any time.")
        }
    }

    private var dataSourcesSection: some View {
        Section {
            DataSourceToggle(
                title: "Mood Check-ins",
                subtitle: "Your daily mood entries",
                icon: "face.smiling",
                iconColor: .yellow,
                isEnabled: $settings.useMoodData
            )

            DataSourceToggle(
                title: "Chat Conversations",
                subtitle: "Sentiment from your chats",
                icon: "bubble.left.and.bubble.right",
                iconColor: .blue,
                isEnabled: $settings.useChatSentiment
            )

            DataSourceToggle(
                title: "Health Data",
                subtitle: "HRV, heart rate, activity",
                icon: "heart.fill",
                iconColor: .red,
                isEnabled: $settings.useBiometrics
            )

            DataSourceToggle(
                title: "App Activity",
                subtitle: "How you use MindFriend",
                icon: "chart.bar.fill",
                iconColor: .orange,
                isEnabled: $settings.useAppUsage
            )

            DataSourceToggle(
                title: "Sleep Patterns",
                subtitle: "Sleep duration and quality",
                icon: "moon.fill",
                iconColor: .indigo,
                isEnabled: $settings.useSleepData
            )
        } header: {
            Text("Data Sources")
        } footer: {
            Text("Choose which data to include in predictions. More data sources = more accurate insights.")
        }
        .onChange(of: settings.useMoodData) { _, _ in saveSettings() }
        .onChange(of: settings.useChatSentiment) { _, _ in saveSettings() }
        .onChange(of: settings.useBiometrics) { _, _ in saveSettings() }
        .onChange(of: settings.useAppUsage) { _, _ in saveSettings() }
        .onChange(of: settings.useSleepData) { _, _ in saveSettings() }
    }

    private var interventionSection: some View {
        Section {
            Toggle(isOn: $settings.allowGentleNudges) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gentle Nudges")
                    Text("Friendly reminders when patterns suggest support")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: $settings.allowActiveCheckins) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Active Check-ins")
                    Text("More direct outreach when risk is elevated")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if settings.preferredInterventionTime != nil {
                HStack {
                    Text("Preferred Time")
                    Spacer()
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { settings.preferredInterventionTime ?? Date() },
                            set: { settings.preferredInterventionTime = $0 }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                }
            }

            Button {
                if settings.preferredInterventionTime == nil {
                    settings.preferredInterventionTime = Date()
                } else {
                    settings.preferredInterventionTime = nil
                }
                saveSettings()
            } label: {
                HStack {
                    Image(systemName: "clock")
                    Text(settings.preferredInterventionTime == nil ? "Set Preferred Time" : "Clear Preferred Time")
                }
            }
        } header: {
            Text("Intervention Preferences")
        } footer: {
            Text("Control how and when we reach out to you.")
        }
        .onChange(of: settings.allowGentleNudges) { _, _ in saveSettings() }
        .onChange(of: settings.allowActiveCheckins) { _, _ in saveSettings() }
        .onChange(of: settings.preferredInterventionTime) { _, _ in saveSettings() }
    }

    private var familySection: some View {
        Section {
            Toggle(isOn: $settings.allowFamilyAlerts) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Family Wellness Alerts")
                    Text("Notify connected family members")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if settings.allowFamilyAlerts {
                Picker("Alert Threshold", selection: $settings.familyAlertThreshold) {
                    Text("High Risk Only").tag(RiskLevel.high)
                    Text("Crisis Only").tag(RiskLevel.crisis)
                }
            }
        } header: {
            Text("Family Connection")
        } footer: {
            Text("If enabled, connected family members may receive a gentle notification when we detect elevated risk. They won't see specific details—just that you might appreciate some support.")
        }
        .onChange(of: settings.allowFamilyAlerts) { _, _ in saveSettings() }
        .onChange(of: settings.familyAlertThreshold) { _, _ in saveSettings() }
    }

    private var dataManagementSection: some View {
        Section {
            NavigationLink {
                PredictionHistoryView()
            } label: {
                Label("View Prediction History", systemImage: "clock.arrow.circlepath")
            }

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete All Prediction Data", systemImage: "trash")
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Data Management")
        } footer: {
            Text("Your prediction data is stored securely and encrypted. You can delete it at any time.")
        }
    }

    // MARK: - Actions

    @MainActor
    private func loadSettings() async {
        isLoading = true

        do {
            try await container.predictiveService.fetchSettings()
            settings = container.predictiveService.settings
        } catch {
            appState.showError(.apiError(error.localizedDescription))
        }

        isLoading = false
    }

    private func saveSettings() {
        guard !isSaving else { return }

        Task { @MainActor in
            isSaving = true

            do {
                try await container.predictiveService.updateSettings(settings)
            } catch {
                // Revert on error
                settings = container.predictiveService.settings
                appState.showError(.apiError(error.localizedDescription))
            }

            isSaving = false
        }
    }

    @MainActor
    private func deleteAllData() async {
        do {
            try await container.predictiveService.deleteAllPredictionData()
            settings = .defaults
            appState.showCelebration(title: "Deleted", subtitle: "Prediction data cleared", icon: "trash.fill")
        } catch {
            appState.showError(.apiError(error.localizedDescription))
        }
    }
}

// MARK: - Data Source Toggle

private struct DataSourceToggle: View {
    let title: String
    let subtitle: String
    let icon: String
    let iconColor: Color
    @Binding var isEnabled: Bool

    var body: some View {
        Toggle(isOn: $isEnabled) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Data Info Sheet

private struct DataInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    IconInfoRow(
                        icon: "lock.shield.fill",
                        iconColor: .green,
                        title: "End-to-End Security",
                        description: "Your prediction data is encrypted at rest and in transit."
                    )

                    IconInfoRow(
                        icon: "person.crop.circle.badge.xmark",
                        iconColor: .blue,
                        title: "No Data Sharing",
                        description: "We never sell or share your personal data with third parties."
                    )

                    IconInfoRow(
                        icon: "iphone.and.arrow.forward",
                        iconColor: .purple,
                        title: "On-Device Processing",
                        description: "Much of the analysis happens locally on your device."
                    )

                    IconInfoRow(
                        icon: "trash",
                        iconColor: .red,
                        title: "Right to Delete",
                        description: "Delete all your prediction data at any time from settings."
                    )
                }

                Section {
                    IconInfoRow(
                        icon: "chart.line.uptrend.xyaxis",
                        iconColor: .orange,
                        title: "How It Works",
                        description: "We look for patterns in your mood, activity, and health data to predict when you might need support."
                    )

                    IconInfoRow(
                        icon: "bell.badge",
                        iconColor: .yellow,
                        title: "Proactive Support",
                        description: "When we detect elevated risk, we'll reach out with helpful resources—before you have to ask."
                    )
                }
            }
            .navigationTitle("Your Privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct IconInfoRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Prediction History View

struct PredictionHistoryView: View {
    @EnvironmentObject var container: DependencyContainer
    @State private var assessments: [RiskAssessment] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading history...")
            } else if assessments.isEmpty {
                ContentUnavailableView(
                    "No Predictions Yet",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Predictions will appear here once enough data has been collected.")
                )
            } else {
                List {
                    ForEach(assessments) { assessment in
                        AssessmentRow(assessment: assessment)
                    }
                }
            }
        }
        .navigationTitle("Prediction History")
        .task { await loadHistory() }
    }

    @MainActor
    private func loadHistory() async {
        isLoading = true

        do {
            assessments = try await container.predictiveService.fetchAssessmentHistory(limit: 30)
        } catch {
            // Silently fail - empty state is shown
        }

        isLoading = false
    }
}

private struct AssessmentRow: View {
    let assessment: RiskAssessment

    var body: some View {
        HStack(spacing: 12) {
            // Risk level indicator
            Circle()
                .fill(assessment.riskLevel.color.opacity(0.3))
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: assessment.riskLevel.icon)
                        .foregroundStyle(assessment.riskLevel.color)
                        .font(.caption)
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(assessment.riskLevel.description)
                        .font(.subheadline.weight(.medium))

                    Spacer()

                    Text(assessment.assessedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !assessment.topFactors.isEmpty {
                    Text(assessment.topFactors.joined(separator: " • "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let confidence = assessment.confidencePercent {
                    HStack(spacing: 4) {
                        Text("Confidence:")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("\(confidence)%")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PredictionSettingsView()
            .environmentObject(AppState())
            .environmentObject(DependencyContainer())
    }
}
