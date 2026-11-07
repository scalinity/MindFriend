import SwiftUI

struct JournalEntryView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss

    // Edit mode if entry provided
    var existingEntry: JournalEntry?
    @State private var selectedPrompt: JournalPrompt?

    init(existingEntry: JournalEntry? = nil, selectedPrompt: JournalPrompt? = nil) {
        self.existingEntry = existingEntry
        _selectedPrompt = State(initialValue: selectedPrompt)
    }

    @State private var title = ""
    @State private var content = ""
    @State private var mood: Int?
    @State private var isSaving = false
    @State private var isRequestingAnalysis = false
    @State private var showingMoodPicker = false
    @State private var showingPromptPicker = false
    @State private var errorMessage: String?
    @State private var savedEntry: JournalEntry?
    @State private var analysis: JournalAnalysis?
    @State private var showingAnalysis = false
    @State private var quotaRemaining: Int?
    @State private var autoSaveTimer: Timer?
    @State private var lastSavedDraft: JournalDraftSnapshot?
    @State private var draftSaveTask: Task<Void, Never>?
    @State private var editorRevision = 0
    @State private var hasInitialized = false
    @State private var hasLoadedDraft = false
    @State private var isEditorActive = false
    @State private var recoveredDraft: JournalDraft?
    @State private var restoredPromptId: String?

    private let moodEmojis = ["😢", "😔", "😐", "🙂", "😊"]

    private var isEditing: Bool { savedEntry != nil || existingEntry != nil }

    private var draftSnapshot: JournalDraftSnapshot {
        JournalDraftSnapshot(title: title, content: content, mood: mood,
                             promptId: selectedPrompt?.id ?? restoredPromptId ?? savedEntry?.promptId)
    }

    private var wordCount: Int {
        content.split(separator: " ").count
    }

    private var canSave: Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 10
    }

    private var canAnalyze: Bool {
        wordCount >= 50 && savedEntry != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Prompt banner (if using a prompt)
                    if let prompt = selectedPrompt {
                        promptBanner(prompt)
                    }

                    if let draft = recoveredDraft {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("A previous draft is available. Your current writing has been kept.")
                                .font(.subheadline)
                            DisclosureGroup("Read previous draft") {
                                Text(draft.content).textSelection(.enabled)
                            }
                            Button("Add previous draft to this entry") {
                                content += content.isEmpty ? draft.content : "\n\n" + draft.content
                                recoveredDraft = nil
                                scheduleAutoSave()
                            }
                            Button("Keep only current writing") {
                                recoveredDraft = nil
                                scheduleAutoSave()
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // Mood selection
                    moodSelector

                    // Title field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Title (optional)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("Give your entry a title...", text: $title)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Main content
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Your thoughts")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(wordCount) words")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        TextEditor(text: $content)
                            .frame(minHeight: 200)
                            .padding(8)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Writing tips
                    if wordCount < 50 {
                        writingTips
                    }

                    // Analysis section (after save)
                    if savedEntry != nil {
                        analysisSection
                    }

                    // Error message
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        if !hasLoadedDraft && !isEditing {
                            Button("Retry loading draft") {
                                Task { await loadExistingData() }
                            }
                        }
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isEditing ? "Edit Entry" : "New Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await saveEntry() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
            .sheet(isPresented: $showingMoodPicker) {
                moodPickerSheet
            }
            .sheet(isPresented: $showingAnalysis) {
                if let analysis = analysis {
                    JournalAnalysisView(analysis: analysis)
                        .environmentObject(container)
                        .environmentObject(appState)
                }
            }
            .sheet(isPresented: $showingPromptPicker) {
                JournalPromptsView { prompt in
                    selectedPrompt = prompt
                    showingPromptPicker = false
                    scheduleAutoSave()
                }
                .environmentObject(container)
                .environmentObject(appState)
            }
            .onAppear {
                isEditorActive = true
                checkQuota()
            }
            .task { await loadExistingData() }
            .onChange(of: draftSnapshot) { _, _ in
                editorRevision += 1
                scheduleAutoSave()
            }
            .onDisappear {
                isEditorActive = false
                autoSaveTimer?.invalidate()
            }
            .keyboardDoneButton()
        }
    }

    // MARK: - Subviews

    private func promptBanner(_ prompt: JournalPrompt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
                Text("Writing Prompt")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            Text(prompt.promptText)
                .font(.subheadline)
                .italic()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var moodSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How are you feeling?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                ForEach(1...5, id: \.self) { score in
                    Button {
                        withAnimation {
                            mood = (mood == score) ? nil : score
                        }
                    } label: {
                        Text(moodEmojis[score - 1])
                            .font(.system(size: 32))
                            .opacity(mood == nil || mood == score ? 1 : 0.3)
                            .scaleEffect(mood == score ? 1.2 : 1)
                    }
                }

                Spacer()
            }
        }
    }

    private var writingTips: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(.blue)
                Text("Writing Tips")
                    .font(.caption)
                    .fontWeight(.semibold)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("• Write at least 50 words to unlock AI insights")
                Text("• There's no right or wrong way to journal")
                Text("• Your entries are completely private")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !content.isEmpty {
                Button {
                    showingPromptPicker = true
                } label: {
                    Label("Need inspiration?", systemImage: "lightbulb")
                        .font(.caption)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var analysisSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                Text("AI Insights")
                    .font(.headline)
                Spacer()

                if let quota = quotaRemaining, quota >= 0 {
                    Text("\(quota) analyses left today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let analysis = analysis {
                // Show analysis preview
                VStack(alignment: .leading, spacing: 8) {
                    if !analysis.emotionalThemes.isEmpty {
                        Text("Themes: \(analysis.emotionalThemes.joined(separator: ", "))")
                            .font(.subheadline)
                    }

                    Button {
                        showingAnalysis = true
                    } label: {
                        Label("View Full Analysis", systemImage: "arrow.right")
                    }
                    .buttonStyle(.bordered)
                }
            } else if canAnalyze {
                Button {
                    Task { await requestAnalysis() }
                } label: {
                    if isRequestingAnalysis {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Get AI Insights", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(isRequestingAnalysis || (quotaRemaining == 0))

                if quotaRemaining == 0 {
                    Text("Upgrade to Premium for unlimited analyses")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Write at least 50 words to unlock AI insights")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.purple.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var moodPickerSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("How are you feeling?")
                    .font(.title2)
                    .fontWeight(.semibold)

                HStack(spacing: 20) {
                    ForEach(1...5, id: \.self) { score in
                        Button {
                            mood = score
                            showingMoodPicker = false
                        } label: {
                            VStack {
                                Text(moodEmojis[score - 1])
                                    .font(.system(size: 48))
                                Text(moodLabel(score))
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
            .navigationTitle("Select Mood")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        mood = nil
                        showingMoodPicker = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Methods

    private func loadExistingData() async {
        if !hasInitialized {
            hasInitialized = true
            if let entry = existingEntry {
                title = entry.title ?? ""
                content = entry.content
                mood = entry.mood
                savedEntry = entry
            }
        }
        guard !isEditing, !hasLoadedDraft else { return }
        let revision = editorRevision
        let initialSnapshot = draftSnapshot
        do {
            let service = JournalService(supabase: container.supabase)
            let draft = try await service.fetchDraft()
            guard !Task.isCancelled, isEditorActive, !isEditing, !isSaving else { return }
            if let draft {
                if editorRevision == revision, draftSnapshot == initialSnapshot,
                   initialSnapshot == JournalDraftSnapshot() {
                    title = draft.title ?? ""
                    content = draft.content
                    mood = draft.moodBefore
                    restoredPromptId = draft.promptId
                    lastSavedDraft = draftSnapshot
                } else {
                    recoveredDraft = draft
                }
            }
            hasLoadedDraft = true
            scheduleAutoSave()
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = "Could not load your saved draft. Your current writing is still here. Please retry before draft autosave resumes."
        }
    }

    private func checkQuota() {
        Task {
            let service = JournalService(supabase: container.supabase)
            quotaRemaining = try? await service.checkAnalysisQuota()
        }
    }

    private func scheduleAutoSave() {
        autoSaveTimer?.invalidate()
        guard isEditorActive, hasLoadedDraft, recoveredDraft == nil, !isEditing, !isSaving else { return }
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { _ in
            Task { @MainActor in startDraftSave() }
        }
    }

    private func startDraftSave() {
        guard draftSaveTask == nil, !isEditing, !isSaving, isEditorActive,
              hasLoadedDraft, recoveredDraft == nil, draftSnapshot != lastSavedDraft else { return }
        let snapshot = draftSnapshot
        draftSaveTask = Task { @MainActor in
            defer {
                draftSaveTask = nil
                if draftSnapshot != lastSavedDraft { scheduleAutoSave() }
            }
            do {
                let service = JournalService(supabase: container.supabase)
                _ = try await service.saveDraft(title: snapshot.title.isEmpty ? nil : snapshot.title,
                                                content: snapshot.content, moodBefore: snapshot.mood,
                                                promptId: snapshot.promptId)
                lastSavedDraft = snapshot
            } catch {
                errorMessage = "Your draft could not be saved. Your writing is still here; autosave will retry."
            }
        }
    }

    private func saveEntry() async {
        guard !isSaving else { return }
        isSaving = true
        autoSaveTimer?.invalidate()
        // Let the single outstanding draft write finish before creation deletes the draft.
        await draftSaveTask?.value
        let snapshot = draftSnapshot
        errorMessage = nil

        do {
            let service = JournalService(supabase: container.supabase)

            if let existing = savedEntry ?? existingEntry {
                // Update existing
                savedEntry = try await service.updateEntry(
                    id: existing.id,
                    title: snapshot.title.isEmpty ? nil : snapshot.title,
                    content: snapshot.content,
                    moodBefore: snapshot.mood,
                    promptId: snapshot.promptId
                )
            } else {
                // Create new
                savedEntry = try await service.createEntry(
                    title: snapshot.title.isEmpty ? nil : snapshot.title,
                    content: snapshot.content,
                    moodBefore: snapshot.mood,
                    promptId: snapshot.promptId
                )
            }

            // Check if we should auto-request analysis
            let settings = try? await service.fetchSettings()
            if settings?.autoAnalyze == true && canAnalyze {
                await requestAnalysis()
            }

        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
        scheduleAutoSave()
    }

    private func requestAnalysis() async {
        guard let entry = savedEntry else { return }

        isRequestingAnalysis = true
        errorMessage = nil

        do {
            let service = JournalService(supabase: container.supabase)
            analysis = try await service.requestAnalysis(forEntryId: entry.id)
            showingAnalysis = true

            // Update remaining quota
            if let quota = quotaRemaining, quota > 0 {
                quotaRemaining = quota - 1
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isRequestingAnalysis = false
    }

    private func moodLabel(_ score: Int) -> String {
        switch score {
        case 1: return "Struggling"
        case 2: return "Low"
        case 3: return "Okay"
        case 4: return "Good"
        case 5: return "Great"
        default: return ""
        }
    }
}

private struct JournalDraftSnapshot: Equatable {
    var title = ""
    var content = ""
    var mood: Int?
    var promptId: String?
}

#Preview {
    JournalEntryView()
        .environmentObject(AppState())
        .environmentObject(DependencyContainer.preview)
}
