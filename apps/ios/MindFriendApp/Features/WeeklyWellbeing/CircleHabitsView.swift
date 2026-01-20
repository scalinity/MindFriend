import SwiftUI

// MARK: - Circle Habits Hub View

struct CircleHabitsView: View {
    @EnvironmentObject private var container: DependencyContainer
    @StateObject private var viewModel = CircleHabitsViewModel()

    @State private var selectedTab: CircleHabitsTab = .checkins
    @State private var showingTemplateEditor = false
    @State private var showingRecap = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab picker
                Picker("Tab", selection: $selectedTab) {
                    ForEach(CircleHabitsTab.allCases) { tab in
                        Text(tab.displayName).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                // Content based on tab
                TabView(selection: $selectedTab) {
                    upcomingCheckinsTab.tag(CircleHabitsTab.checkins)
                    templatesTab.tag(CircleHabitsTab.templates)
                    nudgesTab.tag(CircleHabitsTab.nudges)
                    streaksTab.tag(CircleHabitsTab.streaks)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Circle Habits")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingTemplateEditor = true
                        } label: {
                            Label("New Template", systemImage: "plus")
                        }

                        Button {
                            showingRecap = true
                        } label: {
                            Label("Weekly Recap", systemImage: "doc.text")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingTemplateEditor) {
                CircleTemplateEditorView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingRecap) {
                CircleRecapView(viewModel: viewModel)
            }
            .task {
                await viewModel.loadData(container: container)
            }
        }
    }

    // MARK: - Upcoming Check-ins Tab

    private var upcomingCheckinsTab: some View {
        ScrollView {
            if viewModel.upcomingCheckins.isEmpty {
                emptyStateView(
                    icon: "calendar.badge.clock",
                    title: "No Upcoming Check-ins",
                    message: "Set up templates to schedule regular check-ins with your circle"
                )
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.upcomingCheckins) { checkin in
                        UpcomingCheckinCard(checkin: checkin) {
                            Task {
                                await viewModel.startCheckin(checkin, container: container)
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }

    // MARK: - Templates Tab

    private var templatesTab: some View {
        ScrollView {
            if viewModel.templates.isEmpty {
                emptyStateView(
                    icon: "doc.badge.plus",
                    title: "No Templates",
                    message: "Create templates to define consistent check-in questions for your circle"
                ) {
                    showingTemplateEditor = true
                }
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.templates) { template in
                        TemplateCard(template: template) {
                            showingTemplateEditor = true
                        }
                    }
                }
                .padding()
            }
        }
    }

    // MARK: - Nudges Tab

    private var nudgesTab: some View {
        ScrollView {
            if viewModel.pendingNudges.isEmpty {
                emptyStateView(
                    icon: "bell.slash",
                    title: "No Pending Nudges",
                    message: "You're all caught up with your circle check-ins!"
                )
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.pendingNudges) { nudge in
                        NudgeCard(nudge: nudge) {
                            Task {
                                await viewModel.dismissNudge(nudge, container: container)
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }

    // MARK: - Streaks Tab

    private var streaksTab: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Current streak card
                streakCard

                // Streak history
                if !viewModel.streakHistory.isEmpty {
                    streakHistorySection
                }

                // Tips
                streakTipsSection
            }
            .padding()
        }
    }

    private var streakCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "flame.fill")
                .font(.system(size: 64))
                .foregroundStyle(.orange)

            Text("\(viewModel.currentStreak.currentStreak)")
                .font(.system(size: 72, weight: .bold))

            Text("Day Streak")
                .font(.title3)
                .foregroundStyle(.secondary)

            if viewModel.currentStreak.longestStreak > 0 {
                Text("Best: \(viewModel.currentStreak.longestStreak) days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if viewModel.currentStreak.isAtRisk {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text("Check in soon to keep your streak!")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.yellow.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var streakHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.headline)

            ForEach(viewModel.streakHistory) { day in
                HStack {
                    Image(systemName: day.completed ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(day.completed ? .green : .gray)

                    Text(day.date, style: .date)
                        .font(.subheadline)

                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var streakTipsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tips to Keep Your Streak")
                .font(.headline)

            tipRow(icon: "alarm", text: "Set reminders for check-in days")
            tipRow(icon: "calendar", text: "Schedule check-ins at consistent times")
            tipRow(icon: "person.2", text: "Invite your circle to check in together")
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
        }
    }

    // MARK: - Helpers

    private func emptyStateView(icon: String, title: String, message: String, action: (() -> Void)? = nil) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let action = action {
                Button(action: action) {
                    Text("Get Started")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .padding(.top, 8)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Supporting Views

struct UpcomingCheckinCard: View {
    let checkin: CircleTemplate
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(checkin.name)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text("\(checkin.questions.count) questions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    ForEach(checkin.reminderDays, id: \.self) { day in
                        Text(dayAbbreviation(day))
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }

                    Spacer()

                    Text(checkin.reminderTime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }()

    private func dayAbbreviation(_ day: Int) -> String {
        // Convert 1-based day (1-7) to 0-based index (0-6)
        let symbols = Self.dayFormatter.shortWeekdaySymbols
        return String(symbols[((day - 1) % 7)].prefix(2))
    }
}

struct TemplateCard: View {
    let template: CircleTemplate
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "doc.text.fill")
                        .font(.title2)
                        .foregroundStyle(.purple)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(template.name)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if let description = template.description {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Image(systemName: template.isActive ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(template.isActive ? .green : .gray)
                }

                HStack {
                    Text("\(template.questions.count) questions")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if template.isActive {
                        Label("Active", systemImage: "checkmark")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

struct NudgeCard: View {
    let nudge: CircleNudge
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bell.fill")
                    .foregroundStyle(.orange)

                Text(nudge.message)
                    .font(.subheadline)

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            Text("From: \(nudge.circleId.uuidString.prefix(8))...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Tab Enum

enum CircleHabitsTab: String, CaseIterable, Identifiable, Hashable {
    case checkins
    case templates
    case nudges
    case streaks

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .checkins: return "Check-ins"
        case .templates: return "Templates"
        case .nudges: return "Nudges"
        case .streaks: return "Streaks"
        }
    }

    var icon: String {
        switch self {
        case .checkins: return "checkmark.circle"
        case .templates: return "doc.text"
        case .nudges: return "bell"
        case .streaks: return "flame"
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    CircleHabitsView()
        .environmentObject(DependencyContainer.preview)
}
#endif
