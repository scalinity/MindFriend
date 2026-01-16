import SwiftUI

@main
struct MindFriendWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchNavigationView()
        }
    }
}

// MARK: - Root Navigation View

struct WatchNavigationView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            WatchHomeView()
                .tag(0)

            WatchMoodView()
                .tag(1)

            WatchStatsView()
                .tag(2)
        }
        .tabViewStyle(.page)
    }
}

// MARK: - Home View

struct WatchHomeView: View {
    @StateObject private var viewModel = WatchHomeViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Streak Badge
                VStack(spacing: 4) {
                    HStack {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.orange)
                        Text("\(viewModel.streak)")
                            .font(.headline)
                    }
                    Text("Day Streak")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Quick Actions
                HStack(spacing: 8) {
                    Button {
                        viewModel.showBreathing = true
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "wind")
                                .font(.title3)
                            Text("Breathe")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    Button {
                        viewModel.showFocus = true
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "circle.dotted")
                                .font(.title3)
                            Text("Focus")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                // Today's Progress
                VStack(spacing: 6) {
                    HStack {
                        Text("Today")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(viewModel.completedToday)/\(viewModel.dailyGoal)")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }

                    let progress = viewModel.dailyGoal > 0 ? Double(viewModel.completedToday) / Double(viewModel.dailyGoal) : 0
                    ProgressView(value: min(progress, 1.0))
                        .tint(.green)
                }
                .padding()
                .background(Color(uiColor: .systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding()
        }
        .navigationTitle("MindFriend")
        .sheet(isPresented: $viewModel.showBreathing) {
            WatchBreathingView()
        }
        .sheet(isPresented: $viewModel.showFocus) {
            WatchFocusView()
        }
    }
}

// MARK: - Home View Model

@MainActor
final class WatchHomeViewModel: ObservableObject {
    @Published var streak = 14
    @Published var completedToday = 2
    @Published var dailyGoal = 3
    @Published var showBreathing = false
    @Published var showFocus = false

    init() {
        // Load from UserDefaults or sync with phone
        loadData()
    }

    private func loadData() {
        streak = UserDefaults.standard.integer(forKey: "watch_streak")
        completedToday = UserDefaults.standard.integer(forKey: "watch_completed_today")
        dailyGoal = UserDefaults.standard.integer(forKey: "watch_daily_goal")
    }
}

// MARK: - Breathing View

struct WatchBreathingView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = WatchBreathingViewModel()

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.3))
                    .frame(width: viewModel.circleSize, height: viewModel.circleSize)
                    .animation(.easeInOut(duration: viewModel.breathDuration), value: viewModel.circleSize)

                VStack(spacing: 2) {
                    Text(viewModel.instruction)
                        .font(.headline)

                    Text("\(viewModel.secondsRemaining)")
                        .font(.title2)
                        .monospacedDigit()
                }
            }

            Button("Done") {
                viewModel.stop()
                dismiss()
            }
            .padding()
        }
        .padding()
        .onAppear {
            viewModel.startBreathing()
        }
        .onDisappear {
            viewModel.stop()
        }
    }
}

// MARK: - Breathing View Model

@MainActor
final class WatchBreathingViewModel: ObservableObject {
    @Published var instruction = "Breathe In"
    @Published var secondsRemaining = 4
    @Published var circleSize: CGFloat = 80

    let breathDuration: Double = 4.0
    private var timer: Timer?
    private var isInhaling = true
    private var cycles = 0
    private let maxCycles = 5

    func startBreathing() {
        startCycle()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }

    private func startCycle() {
        isInhaling = true
        instruction = "Breathe In"
        circleSize = 140
        secondsRemaining = Int(breathDuration)

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func tick() {
        secondsRemaining -= 1

        if secondsRemaining <= 0 {
            if isInhaling {
                isInhaling = false
                instruction = "Breathe Out"
                circleSize = 80
                secondsRemaining = Int(breathDuration)
            } else {
                cycles += 1
                if cycles >= maxCycles {
                    stop()
                    instruction = "Complete"
                } else {
                    isInhaling = true
                    instruction = "Breathe In"
                    circleSize = 140
                    secondsRemaining = Int(breathDuration)
                }
            }
        }
    }
}

// MARK: - Focus View (Placeholder)

struct WatchFocusView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Focus Session")
                .font(.headline)

            Text("10 minutes")
                .font(.title)

            Button("Start") {
                dismiss()
            }
            .padding()
        }
    }
}

// MARK: - Mood View

struct WatchMoodView: View {
    @State private var selectedMood: String?
    let moods = [
        ("great", "😊"),
        ("good", "🙂"),
        ("okay", "😐"),
        ("low", "😔"),
        ("stressed", "😰")
    ]

    var body: some View {
        VStack(spacing: 12) {
            Text("How are you?")
                .font(.headline)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(moods, id: \.0) { mood, emoji in
                        Button {
                            selectedMood = mood
                            saveMood(mood)
                        } label: {
                            HStack {
                                Text(emoji)
                                    .font(.title)
                                Text(mood.capitalized)
                                    .font(.body)
                                Spacer()
                                if selectedMood == mood {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(selectedMood == mood ? Color.blue.opacity(0.2) : Color(uiColor: .systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
        .padding()
        .navigationTitle("Mood")
    }

    private func saveMood(_ mood: String) {
        UserDefaults.standard.set(mood, forKey: "watch_today_mood")
        UserDefaults.standard.set(Date(), forKey: "watch_mood_date")
    }
}

// MARK: - Stats View

struct WatchStatsView: View {
    @State private var weekMoods: [String] = ["😊", "🙂", "😐", "🙂", "😊", "🙂", "😐"]

    private static let dayOfWeekFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 12) {
            Text("This Week")
                .font(.headline)

            HStack(spacing: 4) {
                ForEach(weekMoods.indices, id: \.self) { index in
                    VStack(spacing: 1) {
                        Text(weekMoods[index])
                            .font(.caption)
                        Text(dayLabel(index))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Exercises Done")
                    Spacer()
                    Text("12")
                }

                HStack {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                    Text("Moods Logged")
                    Spacer()
                    Text("7")
                }
            }
            .font(.caption)
            .padding()
            .background(Color(uiColor: .systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Spacer()
        }
        .padding()
        .navigationTitle("Stats")
    }

    private func dayLabel(_ index: Int) -> String {
        let today = Date()
        let calendar = Calendar.current
        let dayOffset = weekMoods.count - 1 - index
        if let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) {
            return String(Self.dayOfWeekFormatter.string(from: date).prefix(1))
        }
        return "?"
    }
}
