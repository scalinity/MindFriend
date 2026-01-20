import SwiftUI

struct JournalListView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer

    @State private var entries: [JournalEntryWithAnalysis] = []
    @State private var streak: JournalStreak?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingNewEntry = false
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

    var body: some View {
        NavigationStack {
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
            .navigationTitle("Journal")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showingPrompts = true
                    } label: {
                        Image(systemName: "lightbulb")
                    }

                    Button {
                        showingNewEntry = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search entries...")
            .sheet(isPresented: $showingNewEntry) {
                JournalEntryView()
                    .environmentObject(container)
                    .environmentObject(appState)
            }
            .sheet(isPresented: $showingPrompts) {
                JournalPromptsView { prompt in
                    showingPrompts = false
                    showingNewEntry = true
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
            VStack(spacing: 12) {
                Button {
                    showingNewEntry = true
                } label: {
                    Label("Write Now", systemImage: "pencil")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    showingPrompts = true
                } label: {
                    Label("Get a Prompt", systemImage: "lightbulb")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var journalListContent: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Streak card
                if let streak = streak {
                    StreakCardView(streak: streak)
                        .padding(.horizontal)
                }

                // Quick stats
                quickStatsView
                    .padding(.horizontal)

                // Entries list
                ForEach(filteredEntries) { entryWithAnalysis in
                    NavigationLink {
                        // TODO: Fix JournalDetailView - currently not in build target
                        // JournalDetailView(entryId: entryWithAnalysis.id)
                        //     .environmentObject(container)
                        //     .environmentObject(appState)
                        Text("Journal Detail - Coming Soon")
                    } label: {
                        JournalEntryCard(entry: entryWithAnalysis)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
    }

    private var quickStatsView: some View {
        HStack(spacing: 16) {
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

struct StreakCardView: View {
    let streak: JournalStreak

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                Text("Journal Streak")
                    .fontWeight(.semibold)
                Spacer()
                Text("\(streak.currentStreak) days")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.orange)
            }

            Text(streak.statusMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if streak.longestStreak > streak.currentStreak {
                Text("Best: \(streak.longestStreak) days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct StatBox: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct JournalEntryCard: View {
    let entry: JournalEntryWithAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let mood = entry.moodEmoji {
                    Text(mood)
                        .font(.title2)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.entry.title ?? "Untitled")
                        .font(.headline)
                        .lineLimit(1)
                    Text(entry.formattedDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if entry.analysis != nil {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.purple)
                }

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }

            Text(entry.previewText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if let analysis = entry.analysis, !analysis.emotionalThemes.isEmpty {
                HStack {
                    ForEach(analysis.emotionalThemes.prefix(3), id: \.self) { theme in
                        Text(theme)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.purple.opacity(0.1))
                            .foregroundStyle(.purple)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }
}

#Preview {
    JournalListView()
        .environmentObject(AppState())
        .environmentObject(DependencyContainer.preview)
}
