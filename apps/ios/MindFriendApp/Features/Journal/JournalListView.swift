import SwiftUI

struct JournalListView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer

    @State private var entries: [JournalEntryWithAnalysis] = []
    @State private var streak: JournalStreak?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingNewEntry = false
    @State private var selectedPrompt: JournalPrompt?
    @State private var showingPrompts = false
    @State private var showingSettings = false
    @State private var searchText = ""

    private var filteredEntries: [JournalEntryWithAnalysis] {
        if searchText.isEmpty {
            return entries
        }
        let search = searchText.lowercased()
        return entries.filter { entry in
            entry.entry.content.lowercased().contains(search) ||
            (entry.entry.title?.lowercased().contains(search) ?? false)
        }
    }

    /// Set by the stable shell so pushed work adds no second NavigationStack; standalone callers keep their own.
    @Environment(\.supportRootEmbedded) private var supportEmbedded

    var body: some View {
        SupportRootNavigation(embedded: supportEmbedded) {
            ZStack {
                if isLoading {
                    ProgressView("Loading journal...")
                } else if let error = errorMessage {
                    ContentUnavailableView {
                        Label("Error", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try Again") {
                            Task { await loadData() }
                        }
                    }
                } else if entries.isEmpty {
                    emptyStateView
                } else {
                    journalListContent
                }
            }
            .supportScreen()
            .navigationTitle("Journal")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gear")
                        .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                        .accessibilityLabel("Journal settings")
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showingPrompts = true
                    } label: {
                        Image(systemName: "lightbulb")
                        .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                        .accessibilityLabel("Journal prompts")
                    }

                    Button {
                        selectedPrompt = nil
                        showingNewEntry = true
                    } label: {
                        Image(systemName: "plus")
                        .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                        .accessibilityLabel("New journal entry")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search entries...")
            .sheet(isPresented: $showingNewEntry, onDismiss: {
                selectedPrompt = nil
                Task { await loadData() }
            }) {
                JournalEntryView(selectedPrompt: selectedPrompt)
                    .environmentObject(container)
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showingPrompts, onDismiss: {
                if selectedPrompt != nil {
                    showingNewEntry = true
                }
            }) {
                JournalPromptsView { prompt in
                    selectedPrompt = prompt
                    showingPrompts = false
                }
                .environmentObject(container)
                .environmentObject(appState)
            }
            .sheet(isPresented: $showingSettings) {
                JournalSettingsView()
                    .environmentObject(container)
                    .environmentObject(appState)
            }
            .refreshable {
                await loadData()
            }
            .task {
                await loadData()
            }
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Journal Entries", systemImage: "book.closed")
        } description: {
            Text("Start writing to track your thoughts and emotions. Your journal is completely private.")
        } actions: {
            VStack(spacing: SupportTheme.Spacing.s) {
                Button {
                    selectedPrompt = nil
                    showingNewEntry = true
                } label: {
                    Label("Write Now", systemImage: "pencil")
                }
                .buttonStyle(.supportPrimary)

                Button {
                    showingPrompts = true
                } label: {
                    Label("Get a Prompt", systemImage: "lightbulb")
                }
                .buttonStyle(.supportSecondary)
            }
        }
    }

    private var journalListContent: some View {
        ScrollView {
            LazyVStack(spacing: SupportTheme.Spacing.m) {


                // Quick stats
                quickStatsView
                    .padding(.horizontal, SupportTheme.Spacing.m)

                // Entries list
                ForEach(filteredEntries) { entryWithAnalysis in
                    NavigationLink {
                        JournalDetailView(entryId: entryWithAnalysis.id) {
                            Task { await loadData() }
                        }
                        .environmentObject(container)
                        .environmentObject(appState)
                    } label: {
                        JournalEntryCard(entry: entryWithAnalysis)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, SupportTheme.Spacing.m)
            }
            .padding(.vertical, SupportTheme.Spacing.m)
        }
    }

    private var quickStatsView: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: dynamicTypeSize.isAccessibilitySize ? 1 : 3), spacing: SupportTheme.Spacing.m) {
            StatBox(
                title: "This Week",
                value: "\(entries.filter { Calendar.current.isDate($0.entry.createdAt, equalTo: Date(), toGranularity: .weekOfYear) }.count)",
                icon: "calendar"
            )

            StatBox(
                title: "Total",
                value: "\(streak?.totalEntries ?? entries.count)",
                icon: "book.fill"
            )

            StatBox(
                title: "Analyzed",
                value: "\(entries.filter { $0.analysis != nil }.count)",
                icon: "sparkles"
            )
        }
    }

    private func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            let journalService = JournalService(supabase: container.supabase)

            // Load entries and streak in parallel
            async let entriesTask = journalService.fetchEntries(filter: .recent)
            async let streakTask = journalService.fetchStreak()

            let fetchedEntries = try await entriesTask
            streak = try await streakTask

            // Convert entries to entries with analysis
            var entriesWithAnalysis: [JournalEntryWithAnalysis] = []
            for entry in fetchedEntries {
                let analysis = try? await journalService.fetchAnalysis(forEntryId: entry.id)
                entriesWithAnalysis.append(JournalEntryWithAnalysis(entry: entry, analysis: analysis, prompt: nil))
            }
            entries = entriesWithAnalysis

        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

// MARK: - Supporting Views



private struct StatBox: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.xxs) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(SupportTheme.textSecondary)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .supportCard()
    }
}

struct JournalEntryCard: View {
    let entry: JournalEntryWithAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            HStack {
                if let mood = entry.moodEmoji {
                    Text(mood)
                        .font(.title2)
                }

                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text(entry.entry.title ?? "Untitled")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(entry.formattedDate)
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }

                Spacer()

                if entry.analysis != nil {
                    Image(systemName: "sparkles")
                        .foregroundStyle(SupportTheme.accent)
                }

                Image(systemName: "chevron.right")
                    .foregroundStyle(SupportTheme.textSecondary)
            }

            Text(entry.previewText)
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let analysis = entry.analysis, !analysis.emotionalThemes.isEmpty {
                HStack {
                    ForEach(analysis.emotionalThemes.prefix(3), id: \.self) { theme in
                        Text(theme)
                            .font(.caption2)
                            .padding(.horizontal, SupportTheme.Spacing.xs)
                            .padding(.vertical, SupportTheme.Spacing.xxs)
                            .background(SupportTheme.surface)
                            .foregroundStyle(SupportTheme.accent)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .supportCard()
        .shadow(color: SupportTheme.canvas.opacity(0.05), radius: 2, y: 1)
    }
}

#Preview {
    JournalListView()
        .environmentObject(AppState())
        .environmentObject(DependencyContainer.preview)
}
