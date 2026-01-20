import SwiftUI

struct JournalDetailView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer

    let entryId: String

    @State private var entry: JournalEntry?
    @State private var analysis: JournalAnalysis?
    @State private var prompt: JournalPrompt?
    @State private var isLoading = true
    @State private var isRequestingAnalysis = false
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
                    .padding(.top, 100)
            } else if let entry = entry {
                VStack(alignment: .leading, spacing: 24) {
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
                .padding()
            } else {
                ContentUnavailableView {
                    Label("Entry Not Found", systemImage: "doc.questionmark")
                } description: {
                    Text("This journal entry could not be loaded.")
                }
            }
        }
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
                }
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
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
        .sheet(isPresented: $showingEditSheet) {
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
                        .font(.system(size: 48))
                    Text(moodLabel(mood))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(entry.createdAt, style: .date)
                    .font(.headline)
                Text(entry.createdAt, style: .time)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func promptSection(prompt: JournalPrompt) -> some View {
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
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func contentSection(entry: JournalEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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
                    .foregroundStyle(.secondary)

                if let characterCount = entry.characterCount {
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text("\(characterCount) characters")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
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
                // Analysis preview
                VStack(alignment: .leading, spacing: 12) {
                    // Emotional themes
                    if !analysis.emotionalThemes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Emotional Themes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                ForEach(analysis.emotionalThemes.prefix(4), id: \.self) { theme in
                                    Text(theme.capitalized)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.purple.opacity(0.15))
                                        .foregroundStyle(.purple)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    // Sentiment
                    HStack {
                        Text("Overall tone:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(analysis.overallSentiment.capitalized)
                            .font(.caption)
                            .fontWeight(.medium)
                    }

                    // Distortions indicator
                    if analysis.hasDistortions {
                        HStack {
                            Image(systemName: "brain.head.profile")
                                .foregroundStyle(.orange)
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
                    .buttonStyle(.bordered)
                }
            } else if canRequestAnalysis {
                VStack(spacing: 12) {
                    Text("Get personalized insights about your thoughts and feelings from this entry.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

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
                    .disabled(isRequestingAnalysis || quotaRemaining == 0)

                    if quotaRemaining == 0 {
                        Text("Upgrade to Premium for unlimited analyses")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Write at least 50 words to unlock AI insights")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.purple.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func metadataSection(entry: JournalEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Entry Details")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Created:")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                }

                if let updatedAt = entry.updatedAt, updatedAt != entry.createdAt {
                    HStack {
                        Text("Last edited:")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(updatedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }

                if analysis != nil {
                    HStack {
                        Text("Analyzed:")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .font(.caption)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
        guard entry != nil else { return }

        do {
            let service = JournalService(supabase: container.supabase)
            try await service.deleteEntry(id: entryId)
            // Dismiss the view - in a real app this would pop the navigation
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
