import SwiftUI

struct JournalDetailView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss

    let entryId: String
    var onChange: () -> Void = {}

    @State private var entry: JournalEntry?
    @State private var analysis: JournalAnalysis?
    @State private var prompt: JournalPrompt?
    @State private var isLoading = true
    @State private var isRequestingAnalysis = false
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var showingAnalysis = false
    @State private var showingEditSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var quotaRemaining: Int?

    private let moodEmojis = ["😢", "😔", "😐", "🙂", "😊"]

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView("Loading entry...")
                    .padding(.top, SupportTheme.Spacing.xl)
            } else if let entry = entry {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.l) {
                    // Header with mood and date
                    headerSection(entry: entry)

                    // Prompt (if used)
                    if let prompt = prompt {
                        promptSection(prompt: prompt)
                    }

                    // Main content
                    contentSection(entry: entry)

                    // Analysis section
                    analysisSection

                    // Metadata
                    metadataSection(entry: entry)
                }
                .padding(SupportTheme.Spacing.m)
            } else {
                ContentUnavailableView {
                    Label("Entry Not Found", systemImage: "doc.questionmark")
                } description: {
                    Text("This journal entry could not be loaded.")
                }
            }
        }
        .supportScreen()
        .navigationTitle(entry?.title ?? "Journal Entry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingEditSheet = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                    .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                    .accessibilityLabel("More options")
                }
                .disabled(isDeleting || entry == nil)
            }
        }
        .safeAreaInset(edge: .bottom) {
                if errorMessage != nil {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                    Text(errorMessage ?? "")

                    Button("OK") {
                        errorMessage = nil
                    }
                }
                    .foregroundStyle(SupportTheme.textSecondary)
                    .buttonStyle(.supportSecondary)
                    .supportCard()
                    .padding(SupportTheme.Spacing.m)
                }
            }
        .alert("Delete Entry?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await deleteEntry() }
            }
        } message: {
            Text("This will permanently delete this journal entry and any associated analysis. This cannot be undone.")
        }
        .sheet(isPresented: $showingAnalysis) {
            if let analysis = analysis {
                JournalAnalysisView(analysis: analysis)
                    .environmentObject(container)
                    .environmentObject(appState)
            }
        }
        .sheet(isPresented: $showingEditSheet, onDismiss: {
            Task { await loadData() }
            onChange()
        }) {
            if let entry = entry {
                JournalEntryView(existingEntry: entry)
                    .environmentObject(container)
                    .environmentObject(appState)
            }
        }
        .task {
            await loadData()
        }
    }

    // MARK: - Sections

    private func headerSection(entry: JournalEntry) -> some View {
        HStack(alignment: .top) {
            if let mood = entry.mood {
                VStack {
                    Text(moodEmojis[mood - 1])
                        .font(.system(.largeTitle))
                    Text(moodLabel(mood))
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: SupportTheme.Spacing.xxs) {
                Text(entry.createdAt, style: .date)
                    .font(.headline)
                Text(entry.createdAt, style: .time)
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
        }
    }

    private func promptSection(prompt: JournalPrompt) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(SupportTheme.accent)
                Text("Writing Prompt")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            Text(prompt.promptText)
                .font(.subheadline)
                .italic()
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .padding(SupportTheme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SupportTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
    }

    private func contentSection(entry: JournalEntry) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            if let title = entry.title, !title.isEmpty {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
            }

            Text(entry.content)
                .font(.body)
                .lineSpacing(6)

            HStack {
                Text("\(entry.wordCount) words")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)

                if entry.moodBefore != nil {
                    Text("•")
                        .foregroundStyle(SupportTheme.textSecondary)
                    Text("\(entry.characterCount) characters")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
            }
        }
    }

    private var analysisSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(SupportTheme.accent)
                Text("AI Insights")
                    .font(.headline)
                Spacer()

                if let quota = quotaRemaining, quota >= 0 {
                    Text("\(quota) analyses left today")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
            }

            if let analysis = analysis {
                // Analysis preview
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                    // Emotional themes
                    if !analysis.emotionalThemes.isEmpty {
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                            Text("Emotional Themes")
                                .font(.caption)
                                .foregroundStyle(SupportTheme.textSecondary)
                            HStack {
                                ForEach(analysis.emotionalThemes.prefix(4), id: \.self) { theme in
                                    Text(theme.capitalized)
                                        .font(.caption)
                                        .padding(.horizontal, SupportTheme.Spacing.xs)
                                        .padding(.vertical, SupportTheme.Spacing.xxs)
                                        .background(SupportTheme.surface)
                                        .foregroundStyle(SupportTheme.accent)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    // Sentiment
                    HStack {
                        Text("Overall tone:")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                        Text(analysis.overallSentiment.capitalized)
                            .font(.caption)
                            .fontWeight(.medium)
                    }

                    // Distortions indicator
                    if analysis.hasDistortions {
                        HStack {
                            Image(systemName: "brain.head.profile")
                                .foregroundStyle(SupportTheme.accent)
                            Text("\(analysis.cognitiveDistortions.count) thinking pattern\(analysis.cognitiveDistortions.count == 1 ? "" : "s") identified")
                                .font(.caption)
                        }
                    }

                    Button {
                        showingAnalysis = true
                    } label: {
                        Label("View Full Analysis", systemImage: "arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.supportSecondary)
                }
            } else if canRequestAnalysis {
                VStack(spacing: SupportTheme.Spacing.s) {
                    Text("Get personalized insights about your thoughts and feelings from this entry.")
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)

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
                    .buttonStyle(.supportPrimary)
                    .tint(SupportTheme.accent)
                    .disabled(isRequestingAnalysis || quotaRemaining == 0)

                    if quotaRemaining == 0 {
                        Text("Upgrade to Premium for unlimited analyses")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                }
            } else {
                Text("Write at least 50 words to unlock AI insights")
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
        }
        .supportCard()
    }

    private func metadataSection(entry: JournalEntry) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            Text("Entry Details")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(SupportTheme.textSecondary)

            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                HStack {
                    Text("Created:")
                        .foregroundStyle(SupportTheme.textSecondary)
                    Spacer()
                    Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                }

                if entry.updatedAt != entry.createdAt {
                    HStack {
                        Text("Last edited:")
                            .foregroundStyle(SupportTheme.textSecondary)
                        Spacer()
                        Text(entry.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }

                if analysis != nil {
                    HStack {
                        Text("Analyzed:")
                            .foregroundStyle(SupportTheme.textSecondary)
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(SupportTheme.accent)
                    }
                }
            }
            .font(.caption)
        }
        .supportCard()
    }

    // MARK: - Computed Properties

    private var canRequestAnalysis: Bool {
        guard let entry = entry else { return false }
        return entry.wordCount >= 50
    }

    // MARK: - Methods

    private func loadData() async {
        isLoading = true

        let service = JournalService(supabase: container.supabase)

        do {
            // Load entry
            entry = try await service.fetchEntry(id: entryId)

            // Load analysis if exists
            analysis = try? await service.fetchAnalysis(forEntryId: entryId)

            // Load prompt if used
            if let promptId = entry?.promptId {
                prompt = try? await service.fetchPrompt(id: promptId)
            }

            // Check quota
            quotaRemaining = try? await service.checkAnalysisQuota()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func requestAnalysis() async {
        guard let entry = entry else { return }

        isRequestingAnalysis = true
        errorMessage = nil

        do {
            let service = JournalService(supabase: container.supabase)
            analysis = try await service.requestAnalysis(forEntryId: entry.id)
            showingAnalysis = true

            // Update quota
            if let quota = quotaRemaining, quota > 0 {
                quotaRemaining = quota - 1
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isRequestingAnalysis = false
    }

    private func deleteEntry() async {
        guard entry != nil, !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }

        do {
            let service = JournalService(supabase: container.supabase)
            try await service.deleteEntry(id: entryId)
            onChange()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
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

#Preview {
    NavigationStack {
        JournalDetailView(entryId: "preview-id")
            .environmentObject(AppState())
            .environmentObject(DependencyContainer.preview)
    }
}
