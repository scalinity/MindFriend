import Foundation
import Security
import SwiftUI
import WatchKit
import WidgetKit

// MARK: - Watch Keychain Helper

/// Lightweight Keychain wrapper for Watch app (stores small amounts of sensitive data)
enum WatchKeychain {
    private static let service = "app.mindfriend.watch"

    @discardableResult
    static func save(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        // Try atomic update first (no data loss window)
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if status == errSecItemNotFound {
            // Item doesn't exist yet — create it
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }

        if status != errSecSuccess {
            print("[WatchKeychain] Failed to save key '\(key)': \(status)")
        }
        return status == errSecSuccess
    }
    
    static func retrieve(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return value
    }
    
    static func delete(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

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
                .background(Color.gray.opacity(0.15))
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
    @Published var streak = 0
    @Published var completedToday = 0
    @Published var dailyGoal = 3
    @Published var showBreathing = false
    @Published var showFocus = false

    init() {
        loadData()
    }

    private func loadData() {
        let savedStreak = WatchAppConstants.sharedDefaults.integer(forKey: "watch_streak")
        streak = savedStreak

        let savedCompleted = WatchAppConstants.sharedDefaults.integer(forKey: "watch_completed_today")
        completedToday = savedCompleted

        let savedGoal = WatchAppConstants.sharedDefaults.integer(forKey: "watch_daily_goal")
        dailyGoal = savedGoal > 0 ? savedGoal : 3 // Default to 3 if not set
    }
}

// MARK: - Breathing View

struct WatchBreathingView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = WatchBreathingViewModel()

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                // Outer breathing ring
                Circle()
                    .stroke(viewModel.phaseColor.opacity(0.3), lineWidth: 8)
                    .frame(width: 120, height: 120)

                // Animated breathing circle
                Circle()
                    .fill(viewModel.phaseColor.opacity(0.4))
                    .frame(width: viewModel.circleSize, height: viewModel.circleSize)
                    .animation(.easeInOut(duration: viewModel.currentPhaseDuration), value: viewModel.circleSize)

                VStack(spacing: 4) {
                    Text(viewModel.instruction)
                        .font(.headline)
                        .multilineTextAlignment(.center)

                    Text("\(viewModel.secondsRemaining)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()

                    if viewModel.isActive {
                        Text("Cycle \(viewModel.currentCycle)/\(viewModel.totalCycles)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !viewModel.isActive && !viewModel.isComplete {
                Button("Start") {
                    viewModel.startBreathing()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            } else if viewModel.isComplete {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.green)

                    Text("Great job!")
                        .font(.headline)

                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Button("Stop") {
                    viewModel.stop()
                    dismiss()
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding()
        .navigationTitle("4-7-8 Breathe")
        .onDisappear {
            viewModel.stop()
        }
    }
}

// MARK: - Breathing View Model (4-7-8 Pattern with Haptics)

@MainActor
final class WatchBreathingViewModel: ObservableObject {
    // MARK: - Published State

    @Published var instruction = "Ready?"
    @Published var secondsRemaining = 4
    @Published var circleSize: CGFloat = 50
    @Published var isActive = false
    @Published var isComplete = false
    @Published var currentCycle = 1
    @Published var currentPhase: BreathPhase = .ready

    // MARK: - Configuration

    let totalCycles = 4
    let inhaleDuration = 4   // 4 seconds
    let holdDuration = 7     // 7 seconds
    let exhaleDuration = 8   // 8 seconds

    private let minCircleSize: CGFloat = 50
    private let maxCircleSize: CGFloat = 110

    // MARK: - Timer

    private var timer: Timer?
    private let haptics = HapticManager.shared

    // Timer cleanup handled by stop() in onDisappear.
    // The [weak self] in the timer callback prevents retain cycles,
    // so the timer fires harmlessly if the view model is deallocated.

    // MARK: - Breath Phase

    enum BreathPhase {
        case ready
        case inhale
        case hold
        case exhale
        case complete
    }

    // MARK: - Computed Properties

    var phaseColor: Color {
        switch currentPhase {
        case .ready: return .gray
        case .inhale: return .blue
        case .hold: return .purple
        case .exhale: return .teal
        case .complete: return .green
        }
    }

    var currentPhaseDuration: Double {
        switch currentPhase {
        case .inhale: return Double(inhaleDuration)
        case .hold: return Double(holdDuration)
        case .exhale: return Double(exhaleDuration)
        default: return 1.0
        }
    }

    // MARK: - Public Methods

    func startBreathing() {
        isActive = true
        isComplete = false
        currentCycle = 1
        startInhale()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isActive = false
        currentPhase = .ready
        instruction = "Ready?"
        circleSize = minCircleSize
    }

    // MARK: - Phase Management

    private func startInhale() {
        currentPhase = .inhale
        instruction = "Breathe In"
        secondsRemaining = inhaleDuration
        circleSize = maxCircleSize

        haptics.playInhaleStart()
        // Invalidate existing timer before starting new one
        timer?.invalidate()
        startTimer()
    }

    private func startHold() {
        currentPhase = .hold
        instruction = "Hold"
        secondsRemaining = holdDuration
        // Circle stays at max size during hold

        haptics.playHoldStart()
    }

    private func startExhale() {
        currentPhase = .exhale
        instruction = "Breathe Out"
        secondsRemaining = exhaleDuration
        circleSize = minCircleSize

        haptics.playExhaleStart()
    }

    private func completeCycle() {
        haptics.playExhaleComplete()

        if currentCycle >= totalCycles {
            completeSession()
        } else {
            currentCycle += 1
            startInhale()
        }
    }

    private func completeSession() {
        timer?.invalidate()
        timer = nil
        isActive = false
        isComplete = true
        currentPhase = .complete
        instruction = "Complete!"
        circleSize = maxCircleSize

        haptics.playSessionComplete()

        // Sync breathing completion to iOS app
        WatchConnectivityManager.shared.sendBreathingCompletedToPhone(cycles: totalCycles)
    }

    // MARK: - Timer

    private func startTimer() {
        timer?.invalidate()
        let newTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        RunLoop.current.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func tick() {
        secondsRemaining -= 1

        // Phase transitions first (prevents "0" from displaying)
        if secondsRemaining <= 0 {
            switch currentPhase {
            case .inhale:
                startHold()
            case .hold:
                startExhale()
            case .exhale:
                completeCycle()
            default:
                break
            }
            return
        }

        // Play progress haptic at certain intervals (only when secondsRemaining > 0)
        switch currentPhase {
        case .inhale:
            haptics.playInhaleProgress()
        case .hold:
            let midpoint = holdDuration / 2
            if midpoint > 0 && secondsRemaining == midpoint {
                haptics.playHoldProgress()
            }
        case .exhale:
            if secondsRemaining % 2 == 0 {
                haptics.playClick()
            }
        default:
            break
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
                            .background(selectedMood == mood ? Color.blue.opacity(0.2) : Color.gray.opacity(0.15))
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
        // Derive score from mood (great=5 ... stressed=1)
        let moodScoreMap: [String: Int] = ["great": 5, "good": 4, "okay": 3, "low": 2, "stressed": 1]
        let score = moodScoreMap[mood] ?? 3

        // Use Keychain for sensitive mood data
        WatchKeychain.save(mood, forKey: "watch_today_mood")
        WatchKeychain.save(Date().ISO8601Format(), forKey: "watch_mood_date")
        // Also store in shared App Group UserDefaults for complications
        WatchAppConstants.sharedDefaults.set(mood, forKey: "watch_today_mood_display")
        WatchAppConstants.sharedDefaults.set(Date(), forKey: "watch_mood_date_display")

        // Sync mood to iOS app
        WatchConnectivityManager.shared.sendMoodToPhone(mood, score: score)
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
            .background(Color.gray.opacity(0.15))
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
