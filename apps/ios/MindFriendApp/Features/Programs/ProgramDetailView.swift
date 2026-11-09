import SwiftUI

// MARK: - Program Detail View

struct ProgramDetailView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer

    let program: Program

    @State private var days: [ProgramDay] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showEnrollSheet = false
    @State private var existingEnrollment: ProgramEnrollment?

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView("Loading program...")
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .accessibilityLabel("Loading program details")
            } else if let loadError {
                SupportUnavailableState(title: "Program unavailable", message: loadError, actionTitle: "Try again") {
                    Task { await loadData() }
                }
            } else {
                programContent
            }
        }
        .supportScreen()
        .navigationTitle(program.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadData() }
        .sheet(isPresented: $showEnrollSheet) {
            EnrollmentSheet(program: program) { enrollment in
                existingEnrollment = enrollment
            }
        }
    }

    @ViewBuilder
    private var programContent: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.l) {
            // Header
            ProgramHeaderView(program: program)

                // Learning objectives
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                    Text("What You'll Learn")
                        .font(.headline)
                .accessibilityAddTraits(.isHeader)

                    ForEach(program.learningObjectives, id: \.self) { objective in
                        HStack(alignment: .top, spacing: SupportTheme.Spacing.xs) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(SupportTheme.accent)
                            Text(objective)
                        }
                        .font(.subheadline)
                    }
                }

                // Program overview
                if !days.isEmpty {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                        Text("Program Overview")
                            .font(.headline)
                .accessibilityAddTraits(.isHeader)

                        ForEach(days.prefix(5)) { day in
                            ProgramDayPreviewRow(day: day, isExpanded: day.dayNumber == 1)
                        }

                        if days.count > 5 {
                            Text("+ \(days.count - 5) more days")
                                .font(.caption)
                                .foregroundStyle(SupportTheme.textSecondary)
                        }
                    }
                }

                // Enroll or continue button
                if let enrollment = existingEnrollment {
                    NavigationLink {
                        ProgramDayView(enrollment: enrollment)
                    } label: {
                        Text("Continue Program")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.supportPrimary)
                    .controlSize(.large)
                } else {
                    Button {
                        // Gate premium programs behind paywall for free users
                        if program.premiumOnly && appState.entitlements.tier != .premium {
                            appState.showPaywall = true
                        } else {
                            showEnrollSheet = true
                        }
                    } label: {
                        HStack {
                            Text("Start Program")
                            if program.premiumOnly {
                                Image(systemName: "crown.fill")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.supportPrimary)
                    .controlSize(.large)
                }
            }
            .padding(SupportTheme.Spacing.m)
        }

    private func loadData() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            days = try await container.supabaseDataService.getProgramDays(programId: program.id)
            existingEnrollment = try await container.supabaseDataService.getEnrollment(programId: program.id)

            Analytics.shared.track(.programViewed, properties: [
                "program_id": program.id,
                "category": program.category.rawValue
            ])
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// MARK: - Program Header View

struct ProgramHeaderView: View {
    let program: Program

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            // Icon/Image
            ZStack {
                RoundedRectangle(cornerRadius: SupportTheme.cardRadius)
                    .fill(SupportTheme.accent)
                    .frame(width: 100, height: 100)

                Image(systemName: program.category.icon)
                    .font(.system(.largeTitle))
                    .foregroundStyle(SupportTheme.textPrimary)
            }
            .accessibilityHidden(true)

            VStack(spacing: SupportTheme.Spacing.xxs) {
                Text(program.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text(program.description)
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Stats row
            HStack(spacing: SupportTheme.Spacing.l) {
                StatItem(
                    value: program.formattedDuration,
                    label: "Duration"
                )

                StatItem(
                    value: "\(program.estimatedDailyMinutes) min",
                    label: "Daily"
                )

                StatItem(
                    value: program.difficulty.displayName,
                    label: "Level"
                )
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Program details: Duration \(program.formattedDuration), \(program.estimatedDailyMinutes) minutes daily, \(program.difficulty.displayName) level")

            // Tags
            if !program.tags.isEmpty {
                FlowLayout(spacing: SupportTheme.Spacing.xs) {
                    ForEach(program.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                            .padding(.horizontal, SupportTheme.Spacing.s)
                            .padding(.vertical, SupportTheme.Spacing.xxs)
                            .background(SupportTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                            .overlay(
                                RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                                    .stroke(SupportTheme.separator, lineWidth: 0.5)
                            )
                            .accessibilityLabel("Tag: \(tag)")
                    }
                }
                .accessibilityLabel("Tags: \(program.tags.joined(separator: ", "))")
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Program Day Preview Row

struct ProgramDayPreviewRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let day: ProgramDay
    let isExpanded: Bool

    @State private var expanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: 0.2)) {
                    expanded.toggle()
                }
            } label: {
                HStack {
                    Text("Day \(day.dayNumber)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(SupportTheme.textPrimary)

                    Text(day.title)
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                        .rotationEffect(.degrees(reduceMotion ? 0 : (expanded ? 180 : 0)))
                        .accessibilityHidden(true)
                }
                .padding(.vertical, SupportTheme.Spacing.s)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Day \(day.dayNumber): \(day.title)")
            .accessibilityHint(expanded ? "Double tap to collapse" : "Double tap to expand details")

            if expanded {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                    if let theme = day.theme {
                        Text(theme)
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }

                    // Content type icons
                    HStack(spacing: SupportTheme.Spacing.s) {
                        ForEach(day.content) { content in
                            Label {
                                Text(content.type.displayName)
                            } icon: {
                                Image(systemName: content.type.icon)
                            }
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                        }
                    }

                    Text("~\(day.estimatedMinutes) min")
                        .font(.caption2)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
                .padding(.bottom, SupportTheme.Spacing.s)
                .padding(.leading, SupportTheme.Spacing.xs)
            }
        }
        .background(SupportTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
        .onAppear {
            expanded = isExpanded
        }
    }
}

#Preview {
    NavigationStack {
        ProgramDetailView(program: Program(
            id: "1",
            slug: "21-day-anxiety-reset",
            title: "21-Day Anxiety Reset",
            description: "A comprehensive program to reduce anxiety and build resilience",
            durationDays: 21,
            category: .anxiety,
            difficulty: .beginner,
            premiumOnly: false,
            learningObjectives: [
                "Understand your anxiety triggers",
                "Master breathing techniques",
                "Build a daily calm routine"
            ],
            tags: ["anxiety", "calm", "breathing"],
            coverImageUrl: nil,
            estimatedDailyMinutes: 15,
            sortOrder: 1,
            methodology: nil,
            evidenceSummary: nil,
            evidenceUrl: nil,
            targetConditions: [],
            requiresBaselineAssessment: false,
            assessmentType: nil
        ))
    }
    .environmentObject(AppState())
    .environmentObject(DependencyContainer())
}
