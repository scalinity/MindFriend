import SwiftUI

// MARK: - Quest Loading State
enum QuestLoadingState {
    case loading
    case loaded(Quest)
    case noQuest
    case error(String)
}

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @State private var questState: QuestLoadingState = .loading
    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Greeting
                    GreetingHeader(userName: appState.currentUser?.displayName ?? "Friend")

                    // Mood check-in prompt
                    if let mood = appState.todayMood {
                        TodayMoodCard(mood: mood)
                    } else {
                        MoodPromptCard()
                    }

                    // Today's quest - with proper state handling
                    questCard

                    // Streak
                    StreakCard(
                        currentStreak: appState.currentStreak,
                        longestStreak: appState.currentUser?.stats.longestStreakDays ?? 0
                    )

                    // Quick actions
                    QuickActionsSection()

                    Spacer(minLength: 32)
                }
                .padding()
            }
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        appState.showCrisisResources = true
                    } label: {
                        Image(systemName: "heart.text.square.fill")
                            .foregroundStyle(.red)
                    }
                    .accessibilityLabel("Crisis Resources")
                }
            }
            .refreshable {
                await loadData()
            }
            .task {
                await loadData()
            }
        }
    }

    // MARK: - Quest Card View
    @ViewBuilder
    private var questCard: some View {
        switch questState {
        case .loading:
            QuestLoadingCard()
        case .loaded(let quest):
            QuestCard(quest: quest)
        case .noQuest:
            QuestEmptyCard(onRetry: { Task { await loadData() } })
        case .error(let message):
            QuestErrorCard(message: message, onRetry: { Task { await loadData() } })
        }
    }

    private func loadData() async {
        questState = .loading

        // Check if we're in dev mode (no real Supabase session)
        let isDevMode = container.supabaseAuthService.userId == nil

        if isDevMode {
            // In dev mode, show a mock quest
            #if DEBUG
            await loadMockData()
            #else
            questState = .error("Please sign in to view your quest")
            #endif
            return
        }

        do {
            // Use Supabase data service for quests
            let questResult = try await container.supabaseDataService.getTodayQuest()

            // Use Supabase auth service for profile
            let profileResult = try await container.supabaseAuthService.fetchProfile()

            await MainActor.run {
                if let quest = questResult {
                    questState = .loaded(quest)
                    appState.todayQuest = quest
                } else {
                    questState = .noQuest
                }
                appState.currentUser = profileResult
                appState.currentStreak = profileResult.stats.currentStreakDays
                appState.entitlements = profileResult.entitlements
            }
        } catch {
            print("HomeView loadData error: \(error)")
            questState = .error(error.localizedDescription)
        }
    }

    #if DEBUG
    private func loadMockData() async {
        // Simulate network delay
        try? await Task.sleep(nanoseconds: 500_000_000)

        let mockQuest = Quest(
            id: "mock-quest-1",
            localDate: ISO8601DateFormatter.dateOnly.string(from: Date()),
            status: .assigned,
            assignedAt: Date(),
            completedAt: nil,
            template: QuestTemplate(
                id: "mock-template-1",
                type: .gratitude,
                title: "Morning Gratitude",
                description: "Write down 3 things you are grateful for this morning. Take a moment to reflect on the positive aspects of your life.",
                estimatedMinutes: 5,
                difficulty: "easy",
                tags: ["gratitude", "morning"],
                instructions: [
                    QuestInstruction(step: 1, text: "Find a quiet space", durationSeconds: nil),
                    QuestInstruction(step: 2, text: "Think of 3 things you're grateful for", durationSeconds: nil),
                    QuestInstruction(step: 3, text: "Write them down", durationSeconds: nil)
                ]
            )
        )

        await MainActor.run {
            questState = .loaded(mockQuest)
            appState.todayQuest = mockQuest
        }
    }
    #endif
}

// MARK: - Components

struct GreetingHeader: View {
    let userName: String

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<21: return "Good evening"
        default: return "Goodnight"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greeting + ",")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text(userName)
                .font(.largeTitle)
                .fontWeight(.bold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MoodPromptCard: View {
    var body: some View {
        NavigationLink {
            MoodCheckInView()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How are you feeling?")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("Log your mood to track your wellness journey")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "plus.circle.fill")
                    .font(.title)
                    .foregroundStyle(Color.accentColor)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

struct TodayMoodCard: View {
    let mood: MoodEntry

    var moodEmoji: String {
        switch mood.moodScore {
        case 1: return "😢"
        case 2: return "😔"
        case 3: return "😐"
        case 4: return "🙂"
        case 5: return "😊"
        default: return "😐"
        }
    }

    var body: some View {
        HStack {
            Text(moodEmoji)
                .font(.system(size: 40))

            VStack(alignment: .leading, spacing: 4) {
                Text("Today's mood")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    ForEach(1...5, id: \.self) { index in
                        Image(systemName: index <= mood.moodScore ? "circle.fill" : "circle")
                            .font(.caption)
                            .foregroundStyle(index <= mood.moodScore ? Color.accentColor : Color.secondary)
                    }
                }
            }

            Spacer()

            NavigationLink {
                MoodCheckInView(existingMood: mood)
            } label: {
                Text("Update")
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
}

struct QuestCard: View {
    let quest: Quest

    var body: some View {
        NavigationLink {
            QuestDetailView(quest: quest)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Today's Quest", systemImage: "star.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)

                    Spacer()

                    if quest.status == .completed {
                        Label("Done", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                Text(quest.template.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(quest.template.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack {
                    Label("\(quest.template.estimatedMinutes) min", systemImage: "clock")
                    Spacer()
                    Image(systemName: quest.template.type.icon)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [.orange.opacity(0.1), .yellow.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct QuestLoadingCard: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading today's quest...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
}

struct QuestEmptyCard: View {
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "star.slash")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text("No Quest Available")
                    .font(.headline)

                Text("Check back tomorrow for a new quest!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                onRetry()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
}

struct QuestErrorCard: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            VStack(spacing: 4) {
                Text("Unable to Load Quest")
                    .font(.headline)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            Button {
                onRetry()
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(.subheadline)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
}

struct StreakCard: View {
    let currentStreak: Int
    let longestStreak: Int

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                    Text("\(currentStreak) day streak")
                        .fontWeight(.semibold)
                }

                Text("Longest: \(longestStreak) days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if currentStreak >= 7 {
                Image(systemName: "trophy.fill")
                    .font(.title2)
                    .foregroundStyle(.yellow)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
}

struct QuickActionsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)

            HStack(spacing: 12) {
                NavigationLink {
                    ExerciseLibraryView()
                } label: {
                    QuickActionButton(
                        icon: "figure.mind.and.body",
                        title: "Exercises",
                        color: .purple
                    )
                }

                NavigationLink {
                    MoodHistoryView()
                } label: {
                    QuickActionButton(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Mood History",
                        color: .blue
                    )
                }

                NavigationLink {
                    BadgesView()
                } label: {
                    QuickActionButton(
                        icon: "medal.fill",
                        title: "Badges",
                        color: .yellow
                    )
                }
            }
        }
    }
}

struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            Text(title)
                .font(.caption)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

#Preview {
    HomeView()
        .environmentObject(AppState())
        .environmentObject(DependencyContainer())
}
