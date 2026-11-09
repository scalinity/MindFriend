import SwiftUI

/// List of available therapeutic programs (CBT, DBT, ACT, etc.)
struct TherapeuticProgramsListView: View {
    @StateObject private var viewModel: TherapeuticProgramsListViewModel
    @State private var selectedProgram: Program?

    init(service: TherapeuticProgramService) {
        _viewModel = StateObject(wrappedValue: TherapeuticProgramsListViewModel(service: service))
    }

    /// Set by the stable shell so pushed work adds no second NavigationStack; standalone callers keep their own.
    @Environment(\.supportRootEmbedded) private var supportEmbedded

    var body: some View {
        SupportRootNavigation(embedded: supportEmbedded) {
            ScrollView {
                VStack(spacing: SupportTheme.Spacing.l) {
                    // Header
                    headerSection

                    // Active enrollment (if any)
                    if let activeEnrollment = viewModel.activeEnrollment {
                        activeEnrollmentCard(activeEnrollment)
                    }

                    // Available programs by methodology
                    ForEach(TherapeuticMethodology.allCases, id: \.self) { methodology in
                        let programs = viewModel.programs.filter { $0.methodology == methodology }
                        if !programs.isEmpty {
                            methodologySection(methodology: methodology, programs: programs)
                        }
                    }

                    Spacer(minLength: SupportTheme.Spacing.xl)
                }
                .padding(SupportTheme.Spacing.m)
            }
            .supportScreen()
            .navigationTitle("Therapeutic Programs")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await viewModel.loadPrograms()
            }
            .task {
                await viewModel.loadPrograms()
            }
            .sheet(item: $selectedProgram) { program in
                TherapeuticProgramDetailSheet(
                    program: program,
                    canEnroll: viewModel.canEnroll,
                    onEnroll: { enrollmentId in
                        Task {
                            await viewModel.loadPrograms()
                        }
                    }
                )
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Evidence-Based Programs")
                .font(.headline)

            Text("Structured therapeutic programs designed by mental health professionals to help you develop lasting coping skills.")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Active Enrollment Card

    private func activeEnrollmentCard(_ enrollment: ProgramEnrollment) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
            HStack {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text("Currently Enrolled")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)

                    Text(enrollment.program?.title ?? "Program")
                        .font(.headline)
                }

                Spacer()

                if let methodology = enrollment.program?.methodology {
                    Text(methodology.shortName)
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, SupportTheme.Spacing.xs)
                        .padding(.vertical, SupportTheme.Spacing.xxs)
                        .background(SupportTheme.accent.opacity(0.2))
                        .foregroundStyle(SupportTheme.accent)
                        .clipShape(Capsule())
                }
            }

            // Progress bar
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                HStack {
                    Text("Week \((enrollment.currentDay - 1) / 7 + 1)")
                        .font(.caption)
                    Spacer()
                    Text("\(Int(enrollment.progressPercentage * 100))% complete")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                            .fill(SupportTheme.separator)

                        RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                            .fill(SupportTheme.accent)
                            .frame(width: geometry.size.width * enrollment.progressPercentage)
                    }
                }
                .frame(height: 8)
            }

            // Continue button
            NavigationLink(destination: Text("Program Detail View")) {
                HStack {
                    Text("Continue Program")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(SupportTheme.Spacing.m)
                .background(SupportTheme.accent)
                .foregroundStyle(SupportTheme.onAccent)
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
            }
        }
        .supportCard()
    }

    // MARK: - Methodology Section

    private func methodologySection(methodology: TherapeuticMethodology, programs: [Program]) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
            HStack {
                Image(systemName: methodology.icon)
                    .foregroundStyle(SupportTheme.accent)

                Text(methodology.displayName)
                    .font(.headline)

                Spacer()

                Text("\(programs.count) program\(programs.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }

            ForEach(programs, id: \.id) { program in
                programCard(program)
            }
        }
    }

    private func programCard(_ program: Program) -> some View {
        Button(action: {
            selectedProgram = program
        }) {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                HStack {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                        Text(program.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(SupportTheme.textPrimary)

                        Text(program.formattedDuration)
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }

                    Spacer()

                    if program.premiumOnly {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.accent)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }

                // Target conditions
                if !program.targetConditions.isEmpty {
                    HStack(spacing: SupportTheme.Spacing.xs) {
                        ForEach(program.targetConditions.prefix(3), id: \.self) { condition in
                            Text(condition)
                                .font(.caption2)
                                .padding(.horizontal, SupportTheme.Spacing.xs)
                                .padding(.vertical, SupportTheme.Spacing.xxs)
                                .background(SupportTheme.separator)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .supportCard()
            .shadow(color: SupportTheme.canvas.opacity(0.05), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - View Model

@MainActor
final class TherapeuticProgramsListViewModel: ObservableObject {
    @Published var programs: [Program] = []
    @Published var activeEnrollment: ProgramEnrollment?
    @Published var canEnroll = true
    @Published var isLoading = false

    private let service: TherapeuticProgramService

    init(service: TherapeuticProgramService) {
        self.service = service
    }

    func loadPrograms() async {
        isLoading = true
        defer { isLoading = false }

        do {
            programs = try await service.fetchTherapeuticPrograms()
            canEnroll = try await service.canEnrollInTherapeuticProgram()
            activeEnrollment = try await service.fetchActiveTherapeuticEnrollment()
        } catch {
            print("Failed to load programs: \(error)")
        }
    }

    func enrollInProgram(programId: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            activeEnrollment = try await service.enrollInProgram(programId: programId)
            canEnroll = false
        } catch {
            print("Failed to enroll: \(error)")
        }
    }
}

// MARK: - Program Detail Sheet

struct TherapeuticProgramDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let program: Program
    let canEnroll: Bool
    let onEnroll: (String) -> Void

    @State private var showEnrollmentConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.l) {
                    // Header
                    headerSection

                    // Description
                    Text(program.description)
                        .font(.body)
                        .foregroundStyle(SupportTheme.textSecondary)

                    // Evidence summary
                    if let evidence = program.evidenceSummary {
                        evidenceCard(evidence)
                    }

                    // Learning objectives
                    if !program.learningObjectives.isEmpty {
                        objectivesSection
                    }

                    // Program details
                    detailsSection

                    Spacer(minLength: SupportTheme.Spacing.xl)
                }
                .padding(SupportTheme.Spacing.m)
            }
            .supportScreen()
            .navigationTitle(program.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                enrollButton
            }
            .alert("Start Program?", isPresented: $showEnrollmentConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Start") {
                    onEnroll(program.id)
                    dismiss()
                }
            } message: {
                Text("You'll complete a baseline assessment before starting the program.")
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            if let methodology = program.methodology {
                HStack {
                    Image(systemName: methodology.icon)
                    Text(methodology.displayName)
                }
                .font(.subheadline)
                .foregroundStyle(SupportTheme.accent)
            }

            HStack {
                Label(program.formattedDuration, systemImage: "calendar")
                Spacer()
                Label("\(program.estimatedDailyMinutes) min/day", systemImage: "clock")
            }
            .font(.caption)
            .foregroundStyle(SupportTheme.textSecondary)
        }
    }

    private func evidenceCard(_ evidence: String) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            Label("Evidence-Based", systemImage: "checkmark.seal.fill")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(SupportTheme.accent)

            Text(evidence)
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)

            if let url = program.evidenceUrl, let evidenceURL = URL(string: url) {
                Link(destination: evidenceURL) {
                    Label("Learn More", systemImage: "arrow.up.right")
                        .font(.caption)
                }
            }
        }
        .padding(SupportTheme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SupportTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
    }

    private var objectivesSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("What You'll Learn")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            ForEach(program.learningObjectives, id: \.self) { objective in
                HStack(alignment: .top, spacing: SupportTheme.Spacing.s) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(SupportTheme.accent)

                    Text(objective)
                        .font(.subheadline)
                }
            }
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Program Details")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    Text("Duration")
                        .foregroundStyle(SupportTheme.textSecondary)
                    Text(program.formattedDuration)
                        .fontWeight(.medium)
                }

                GridRow {
                    Text("Difficulty")
                        .foregroundStyle(SupportTheme.textSecondary)
                    Text(program.difficulty.displayName)
                        .fontWeight(.medium)
                }

                if program.requiresBaselineAssessment {
                    GridRow {
                        Text("Assessment")
                            .foregroundStyle(SupportTheme.textSecondary)
                        Text(program.assessmentType?.uppercased() ?? "Required")
                            .fontWeight(.medium)
                    }
                }
            }
            .font(.subheadline)
        }
    }

    private var enrollButton: some View {
        VStack(spacing: SupportTheme.Spacing.xs) {
            if !canEnroll {
                Text("Complete your current program before starting a new one.")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: {
                showEnrollmentConfirmation = true
            }) {
                Text(canEnroll ? "Start Program" : "Already Enrolled in Another Program")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(SupportTheme.Spacing.m)
                    .background(canEnroll ? SupportTheme.accent : SupportTheme.separator)
                    .foregroundStyle(canEnroll ? SupportTheme.onAccent : SupportTheme.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
            }
            .disabled(!canEnroll)
        }
        .padding(SupportTheme.Spacing.m)
        .background(SupportTheme.canvas)
    }
}

#Preview {
    Text("Therapeutic Programs List Preview")
}
