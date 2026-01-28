//
//  TutorialManager.swift
//  MindFriendApp
//
//  Centralized tutorial completion tracking
//  Provides keys and utilities for managing feature tutorials
//

import SwiftUI

/// Keys for all feature tutorial completion states
enum TutorialKey: String, CaseIterable {
    case home = "home_tutorial_completed"
    case quest = "quest_tutorial_completed"
    case chat = "chat_tutorial_completed"
    case programs = "programs_tutorial_completed"
    case exercises = "exercises_tutorial_completed"
    case insights = "insights_tutorial_completed"
    case achievements = "achievements_tutorial_completed"
    case circles = "circles_tutorial_completed"
    case mood = "mood_tutorial_completed"
    case longitudinal = "longitudinal_tutorial_completed"
    case outcomes = "outcomes_tutorial_completed"
    case wellbeingDebt = "wellbeing_debt_tutorial_completed"
    case questArcs = "quest_arcs_tutorial_completed"

    var displayName: String {
        switch self {
        case .home: return "Home"
        case .quest: return "Quests"
        case .chat: return "Chat"
        case .programs: return "Programs"
        case .exercises: return "Exercises"
        case .insights: return "Insights"
        case .achievements: return "Achievements"
        case .circles: return "Circles"
        case .mood: return "Mood"
        case .longitudinal: return "Longitudinal"
        case .outcomes: return "Wellness Tracking"
        case .wellbeingDebt: return "Wellbeing Debt"
        case .questArcs: return "Quest Arcs"
        }
    }
}

/// Manager for tutorial completion states
@MainActor
final class TutorialManager: ObservableObject {
    static let shared = TutorialManager()

    private init() {}

    /// Check if a tutorial has been completed
    func isCompleted(_ key: TutorialKey) -> Bool {
        UserDefaults.standard.bool(forKey: key.rawValue)
    }

    /// Mark a tutorial as completed
    func markCompleted(_ key: TutorialKey) {
        UserDefaults.standard.set(true, forKey: key.rawValue)
        objectWillChange.send()
    }

    /// Reset a specific tutorial (for re-watching)
    func reset(_ key: TutorialKey) {
        UserDefaults.standard.set(false, forKey: key.rawValue)
        objectWillChange.send()
    }

    /// Reset all tutorials (for testing/development)
    func resetAll() {
        for key in TutorialKey.allCases {
            UserDefaults.standard.set(false, forKey: key.rawValue)
        }
        objectWillChange.send()
    }

    /// Get completion status for all tutorials
    func allCompletionStatus() -> [TutorialKey: Bool] {
        var status: [TutorialKey: Bool] = [:]
        for key in TutorialKey.allCases {
            status[key] = isCompleted(key)
        }
        return status
    }

    /// Count of completed tutorials
    var completedCount: Int {
        TutorialKey.allCases.filter { isCompleted($0) }.count
    }

    /// Total number of tutorials
    var totalCount: Int {
        TutorialKey.allCases.count
    }
}

/// View modifier for presenting a tutorial on first visit
struct TutorialPresenter<TutorialContent: View>: ViewModifier {
    let key: TutorialKey
    @ViewBuilder let tutorialContent: () -> TutorialContent

    @State private var showingTutorial = false
    @AppStorage private var tutorialCompleted: Bool

    init(key: TutorialKey, @ViewBuilder tutorialContent: @escaping () -> TutorialContent) {
        self.key = key
        self.tutorialContent = tutorialContent
        self._tutorialCompleted = AppStorage(wrappedValue: false, key.rawValue)
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                if !tutorialCompleted {
                    // Small delay to allow view to settle
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showingTutorial = true
                    }
                }
            }
            .fullScreenCover(isPresented: $showingTutorial) {
                tutorialContent()
            }
    }
}

extension View {
    /// Present a tutorial on first visit to this view
    func tutorial<TutorialContent: View>(
        key: TutorialKey,
        @ViewBuilder content: @escaping () -> TutorialContent
    ) -> some View {
        modifier(TutorialPresenter(key: key, tutorialContent: content))
    }
}

#Preview {
    Text("Main Content")
        .tutorial(key: .home) {
            Text("Tutorial Content")
        }
}
