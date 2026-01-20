import SwiftUI

// MARK: - Program Detail View

struct ProgramDetailView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer

    let program: Program

    @State private var days: [ProgramDay] = []
    @State private var isLoading = true
    @State private var showEnrollSheet = false
    @State private var existingEnrollment: ProgramEnrollment?

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView("Loading program...")
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .accessibilityLabel("Loading program details")
            } else {
                programContent
            }
        }
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
        VStack(alignment: .leading, spacing: 24) {
            // Header
            ProgramHeaderView(program: program)

                // Learning objectives
                VStack(alignment: .leading, spacing: 8) {
                    Text("What You'll Learn")
                        .font(.headline)

                    ForEach(program.learningObjectives, id: \.self) { objective in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(objective)
                        }
                        .font(.subheadline)
                    }
                }

                // Program overview
                if !days.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Program Overview")
                            .font(.headline)

                        ForEach(days.prefix(5)) { day in
                            ProgramDayPreviewRow(day: day, isExpanded: day.dayNumber == 1)
                        }

                        if days.count > 5 {
                            Text("+ \(days.count - 5) more days")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button {
                        showEnrollSheet = true
                    } label: {
                        HStack {
                            Text(program.premiumOnly ? "Start Program (Premium)" : "Start Program")
                            if program.premiumOnly {
                                Image(systemName: "crown.fill")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding()
        }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            days = try await container.supabaseDataService.getProgramDays(programId: program.id)
            existingEnrollment = try await container.supabaseDataService.getEnrollment(programId: program.id)

            Analytics.shared.track(.programViewed, properties: [
                "program_id": program.id,
                "category": program.category.rawValue
            ])
        } catch {
            appState.showError(.apiError(error.localizedDescription))
        }
    }
}

// MARK: - Program Header View

struct ProgramHeaderView: View {
    let program: Program

    var body: some View {
        VStack(spacing: 16) {
            // Icon/Image
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(program.category.color.gradient)
                    .frame(width: 100, height: 100)

                Image(systemName: program.category.icon)
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text(program.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text(program.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Stats row
            HStack(spacing: 24) {
                StatItem(
                    icon: "calendar",
                    value: program.formattedDuration,
                    label: "Duration"
                )

                StatItem(
                    icon: "clock",
                    value: "\(program.estimatedDailyMinutes) min",
                    label: "Daily"
                )

                StatItem(
                    icon: "chart.bar",
                    value: program.difficulty.displayName,
                    label: "Level"
                )
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Program details: Duration \(program.formattedDuration), \(program.estimatedDailyMinutes) minutes daily, \(program.difficulty.displayName) level")

            // Tags
            if !program.tags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(program.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color(.tertiarySystemBackground))
                            .clipShape(Capsule())
                            .accessibilityLabel("Tag: \(tag)")
                    }
                }
                .accessibilityLabel("Tags: \(program.tags.joined(separator: ", "))")
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct StatItem: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - Program Day Preview Row

struct ProgramDayPreviewRow: View {
    let day: ProgramDay
    let isExpanded: Bool

    @State private var expanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expanded.toggle()
                }
            } label: {
                HStack {
                    Text("Day \(day.dayNumber)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    Text(day.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Day \(day.dayNumber): \(day.title)")
            .accessibilityHint(expanded ? "Double tap to collapse" : "Double tap to expand details")

            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    if let theme = day.theme {
                        Text(theme)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Content type icons
                    HStack(spacing: 12) {
                        ForEach(day.content) { content in
                            Label {
                                Text(content.type.displayName)
                            } icon: {
                                Image(systemName: content.type.icon)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }

                    Text("~\(day.estimatedMinutes) min")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.bottom, 12)
                .padding(.leading, 8)
            }
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
