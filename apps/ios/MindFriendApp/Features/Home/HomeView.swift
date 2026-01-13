import SwiftUI

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @State private var isLoading = true

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

                    // Today's quest
                    if let quest = appState.todayQuest {
                        QuestCard(quest: quest)
                    } else {
                        QuestLoadingCard()
                    }

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

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let quest = container.questService.getTodayQuest()
            async let profile = container.userService.getProfile()

            let (questResult, profileResult) = try await (quest, profile)

            await MainActor.run {
                appState.todayQuest = questResult
                appState.currentUser = profileResult
                appState.currentStreak = profileResult.stats.currentStreakDays
                appState.entitlements = profileResult.entitlements
            }
        } catch {
            appState.showError(.apiError(error.localizedDescription))
        }
    }
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
        default: return "Good night"
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
