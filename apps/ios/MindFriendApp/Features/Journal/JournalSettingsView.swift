import SwiftUI

struct JournalSettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss

    @State private var settings: JournalSettings?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingExportOptions = false

    // Local editing state
    @State private var dailyReminderEnabled = false
    @State private var reminderTime = Date()
    @State private var autoAnalyze = true
    @State private var showWordCount = true
    @State private var defaultMoodTracking = true

    var body: some View {
        NavigationStack {
            Form {
                if isLoading {
                    ProgressView()
                } else {
                    // Reminders section
                    remindersSection

                    // Analysis preferences
                    analysisSection

                    // Display preferences
                    displaySection

                    // Export
                    exportSection

                    // Danger zone
                    dangerZoneSection
                }
            }
            .navigationTitle("Journal Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveSettings() }
                    }
                    .disabled(isSaving)
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(isPresented: $showingExportOptions) {
                ExportOptionsSheet()
                    .environmentObject(container)
            }
            .task {
                await loadSettings()
            }
        }
    }

    // MARK: - Sections

    private var remindersSection: some View {
        Section {
            Toggle("Daily Reminder", isOn: $dailyReminderEnabled)

            if dailyReminderEnabled {
                DatePicker(
                    "Reminder Time",
                    selection: $reminderTime,
                    displayedComponents: .hourAndMinute
                )
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("Get a gentle nudge to journal at your preferred time.")
        }
    }

    private var analysisSection: some View {
        Section {
            Toggle("Auto-Analyze Entries", isOn: $autoAnalyze)
        } header: {
            Text("AI Analysis")
        } footer: {
            Text("When enabled, AI insights will be requested automatically after saving an entry (if you have remaining quota).")
        }
    }

    private var displaySection: some View {
        Section {
            Toggle("Show Word Count", isOn: $showWordCount)
            Toggle("Track Mood by Default", isOn: $defaultMoodTracking)
        } header: {
            Text("Display")
        } footer: {
            Text("Customize how your journal entries are displayed.")
        }
    }

    private var exportSection: some View {
        Section {
            Button {
                showingExportOptions = true
            } label: {
                Label("Export Journal Entries", systemImage: "square.and.arrow.up")
            }
        } header: {
            Text("Your Data")
        } footer: {
            Text("Download your journal entries as JSON, Markdown, or CSV.")
        }
    }

    private var dangerZoneSection: some View {
        Section {
            Button(role: .destructive) {
                // Show confirmation
            } label: {
                Label("Delete All Journal Data", systemImage: "trash")
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Danger Zone")
        } footer: {
            Text("This will permanently delete all your journal entries, analyses, and settings. This cannot be undone.")
        }
    }

    // MARK: - Methods

    private func loadSettings() async {
        isLoading = true

        let service = JournalService(supabase: container.supabase)
        settings = try? await service.fetchSettings()

        if let settings = settings {
            dailyReminderEnabled = settings.dailyReminderEnabled
            autoAnalyze = settings.autoAnalyze
            showWordCount = settings.showWordCount
            defaultMoodTracking = settings.defaultMoodTracking

            if let timeString = settings.reminderTime {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"
                if let time = formatter.date(from: timeString) {
                    reminderTime = time
                }
            }
        }

        isLoading = false
    }

    private func saveSettings() async {
        guard var settings = settings else { return }

        isSaving = true

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        settings.dailyReminderEnabled = dailyReminderEnabled
        settings.reminderTime = formatter.string(from: reminderTime)
        settings.autoAnalyze = autoAnalyze
        settings.showWordCount = showWordCount
        settings.defaultMoodTracking = defaultMoodTracking

        let service = JournalService(supabase: container.supabase)

        do {
            _ = try await service.updateSettings(settings)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
    }
}

// MARK: - Supporting Views

struct DayToggle: View {
    let dayName: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(dayName)
                .font(.caption2)
                .fontWeight(.medium)
                .frame(width: 36, height: 36)
                .background(isSelected ? Color.accentColor : Color(.systemGray5))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

struct ExportOptionsSheet: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss

    @State private var selectedFormat: JournalService.ExportFormat = .markdown
    @State private var isExporting = false
    @State private var exportedData: Data?
    @State private var showingShareSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Choose Export Format")
                    .font(.title3)
                    .fontWeight(.semibold)

                VStack(spacing: 12) {
                    ExportFormatOption(
                        format: .markdown,
                        title: "Markdown",
                        description: "Best for reading and printing",
                        icon: "doc.richtext",
                        isSelected: selectedFormat == .markdown
                    ) {
                        selectedFormat = .markdown
                    }

                    ExportFormatOption(
                        format: .json,
                        title: "JSON",
                        description: "For backups and importing",
                        icon: "doc.badge.gearshape",
                        isSelected: selectedFormat == .json
                    ) {
                        selectedFormat = .json
                    }

                    ExportFormatOption(
                        format: .csv,
                        title: "CSV",
                        description: "For spreadsheets",
                        icon: "tablecells",
                        isSelected: selectedFormat == .csv
                    ) {
                        selectedFormat = .csv
                    }
                }

                Spacer()

                Button {
                    Task { await exportData() }
                } label: {
                    if isExporting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Export", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isExporting)
            }
            .padding()
            .navigationTitle("Export Journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let data = exportedData {
                    ShareSheet(items: [data])
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func exportData() async {
        isExporting = true

        let service = JournalService(supabase: container.supabase)
        exportedData = try? await service.exportEntries(format: selectedFormat)

        isExporting = false

        if exportedData != nil {
            showingShareSheet = true
        }
    }
}

struct ExportFormatOption: View {
    let format: JournalService.ExportFormat
    let title: String
    let description: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 40)

                VStack(alignment: .leading) {
                    Text(title)
                        .font(.headline)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding()
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    JournalSettingsView()
        .environmentObject(AppState())
        .environmentObject(DependencyContainer.preview)
}
