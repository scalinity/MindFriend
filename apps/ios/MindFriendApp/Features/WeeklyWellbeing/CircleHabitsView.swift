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
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .foregroundStyle(SupportTheme.textPrimary)
            .supportScreen()
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
                LazyVStack(spacing: SupportTheme.Spacing.s) {
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
                LazyVStack(spacing: SupportTheme.Spacing.s) {
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
                LazyVStack(spacing: SupportTheme.Spacing.s) {
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

    private func tipRow(icon: String, text: String) -> some View {
        HStack(spacing: SupportTheme.Spacing.s) {
            Image(systemName: icon)
                .foregroundStyle(SupportTheme.accent)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
        }
    }

    // MARK: - Helpers

    private func emptyStateView(icon: String, title: String, message: String, action: (() -> Void)? = nil) -> some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(SupportTheme.textSecondary)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let action = action {
                Button(action: action) {
                    Text("Get Started")
                        .fontWeight(.semibold)
                        .clipShape(Capsule())
                }
                .buttonStyle(.supportPrimary)
                .padding(.top, SupportTheme.Spacing.xs)
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
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)

                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                        Text(checkin.name)
                            .font(.headline)

                        Text("\(checkin.questions.count) questions")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundStyle(SupportTheme.textSecondary)
                }

                HStack {
                    ForEach(checkin.reminderDays, id: \.self) { day in
                        Text(dayAbbreviation(day))
                            .font(.caption2)
                            .clipShape(Capsule())
                    }

                    Spacer()

                    Text(checkin.reminderTime)
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
        }
        .buttonStyle(.supportSecondary)
        .buttonStyle(.plain)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }()

    private func dayAbbreviation(_ day: Int) -> String {
        // Convert 1-based day (1-7) to 0-based index (0-6)
        let symbols = Self.dayFormatter.shortWeekdaySymbols ?? []
        guard !symbols.isEmpty else { return "?" }
        return String(symbols[((day - 1) % 7)].prefix(2))
    }
}

struct TemplateCard: View {
    let template: CircleTemplate
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                HStack {
                    Image(systemName: "doc.text.fill")
                        .font(.title2)

                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                        Text(template.name)
                            .font(.headline)

                        if let description = template.description {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(SupportTheme.textSecondary)
                        }
                    }

                    Spacer()

                    Image(systemName: template.isActive ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(template.isActive ? SupportTheme.accent : SupportTheme.textSecondary)
                }

                HStack {
                    Text("\(template.questions.count) questions")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)

                    Spacer()

                    if template.isActive {
                        Label("Active", systemImage: "checkmark")
                            .font(.caption)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
        }
        .buttonStyle(.supportSecondary)
        .buttonStyle(.plain)
    }
}

struct NudgeCard: View {
    let nudge: CircleNudge
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            HStack {
                Image(systemName: "bell.fill")
                    .foregroundStyle(SupportTheme.accent)

                Text(nudge.message)
                    .font(.subheadline)

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(SupportTheme.textSecondary)
                    .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                }
                .accessibilityLabel("Dismiss nudge")
            }

            Text("From: \(nudge.circleId.uuidString.prefix(8))...")
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .padding()
        .background(SupportTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
    }
}

// MARK: - Tab Enum

enum CircleHabitsTab: String, CaseIterable, Identifiable, Hashable {
    case checkins
    case templates
    case nudges

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .checkins: return "Check-ins"
        case .templates: return "Templates"
        case .nudges: return "Nudges"
        }
    }

    var icon: String {
        switch self {
        case .checkins: return "checkmark.circle"
        case .templates: return "doc.text"
        case .nudges: return "bell"
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
