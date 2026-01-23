import SwiftUI

// MARK: - Thought Records List View

struct ThoughtRecordsListView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: AICoachingViewModel

    @State private var selectedFilter: ThoughtRecordFilter = .all
    @State private var showingNewRecord = false
    @State private var selectedRecord: ThoughtRecord?

    var body: some View {
        NavigationStack {
            List {
                // Filter picker
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(ThoughtRecordFilter.allCases, id: \.self) { filter in
                        Text(filter.displayName).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))

                // Records list
                ForEach(filteredRecords) { record in
                    ThoughtRecordRow(record: record)
                        .onTapGesture {
                            selectedRecord = record
                        }
                }

                if filteredRecords.isEmpty {
                    emptyStateView
                }
            }
            .navigationTitle("Thought Records")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewRecord = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewRecord) {
                AICoachingThoughtRecordView { record in
                    // Handle new record
                }
            }
            .sheet(item: $selectedRecord) { record in
                AICoachingThoughtRecordView { updatedRecord in
                    // Handle updated record
                }
            }
        }
    }

    private var filteredRecords: [ThoughtRecord] {
        switch selectedFilter {
        case .all:
            return viewModel.thoughtRecords
        case .completed:
            return viewModel.thoughtRecords.filter { $0.isCompleted }
        case .drafts:
            return viewModel.thoughtRecords.filter { !$0.isCompleted }
        case .recent:
            let oneWeekAgo = Date().addingTimeInterval(-7 * 86400)
            return viewModel.thoughtRecords.filter { $0.createdAt > oneWeekAgo }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "note.text")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No thought records yet")
                .font(.headline)

            Text("Start by creating your first thought record to work through challenging situations.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                showingNewRecord = true
            } label: {
                Text("Create Thought Record")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowBackground(Color.clear)
    }
}

// MARK: - Thought Record Row

struct ThoughtRecordRow: View {
    let record: ThoughtRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                let event = record.activatingEvent ?? ""
                Text(event.prefix(40) + (event.count > 40 ? "..." : ""))
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                if record.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "pencil.circle")
                        .foregroundStyle(.orange)
                }
            }

            HStack(spacing: 8) {
                if !record.cognitiveDistortions.isEmpty {
                    ForEach(record.cognitiveDistortions.prefix(2)) { distortion in
                        Text(distortion.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                Text(record.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let balancedThought = record.balancedThought {
                Text(balancedThought.prefix(60) + (balancedThought.count > 60 ? "..." : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Filter Enum

enum ThoughtRecordFilter: String, CaseIterable, Identifiable {
    case all
    case completed
    case drafts
    case recent

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "All"
        case .completed: return "Completed"
        case .drafts: return "Drafts"
        case .recent: return "Recent"
        }
    }
}

// MARK: - Coaching Preferences View

struct CoachingPreferencesView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: AICoachingViewModel

    @State private var defaultMode: ConversationMode = .supportive
    @State private var preferredTone: AITone = .friendly
    @State private var reflectionPromptsEnabled = true
    @State private var reframeRemindersEnabled = true

    var body: some View {
        NavigationStack {
            Form {
                // Default Mode
                Section("Default Coaching Mode") {
                    Picker("Mode", selection: $defaultMode) {
                        ForEach(ConversationMode.allCases) { mode in
                            HStack {
                                Image(systemName: mode.icon)
                                Text(mode.displayName)
                            }
                            .tag(mode)
                        }
                    }
                }

                // AI Tone
                Section("AI Communication Style") {
                    Picker("Preferred Tone", selection: $preferredTone) {
                        ForEach(AITone.allCases, id: \.self) { tone in
                            Text(tone.displayName).tag(tone)
                        }
                    }
                }

                // Notifications
                Section("Reminders") {
                    Toggle("Reflection Prompts", isOn: $reflectionPromptsEnabled)
                    Toggle("Reframe Reminders", isOn: $reframeRemindersEnabled)
                }

                // About
                Section("About AI Coaching") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reflect Mode")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Explore your thoughts and feelings in a supportive, non-judgmental space.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Plan Mode")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Work through actionable steps to achieve your goals with AI guidance.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reframe Mode")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Use cognitive restructuring techniques to shift negative thought patterns.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Coaching Preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        savePreferences()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                loadCurrentPreferences()
            }
        }
    }

    private func loadCurrentPreferences() {
        defaultMode = viewModel.preferences.defaultMode
        preferredTone = viewModel.preferences.preferredTone
        reflectionPromptsEnabled = viewModel.preferences.reflectionPromptsEnabled
        reframeRemindersEnabled = viewModel.preferences.reframeRemindersEnabled
    }

    private func savePreferences() {
        var updated = viewModel.preferences
        updated.defaultMode = defaultMode
        updated.preferredTone = preferredTone
        updated.reflectionPromptsEnabled = reflectionPromptsEnabled
        updated.reframeRemindersEnabled = reframeRemindersEnabled
        viewModel.preferences = updated
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Thought Records List") {
    ThoughtRecordsListView(viewModel: .preview)
}

#Preview("Preferences") {
    CoachingPreferencesView(viewModel: .preview)
}
#endif
