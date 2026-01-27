import SwiftUI

/// List of available therapeutic programs (CBT, DBT, ACT, etc.)
struct TherapeuticProgramsListView: View {
    @StateObject private var viewModel: TherapeuticProgramsListViewModel
    @State private var selectedProgram: Program?

    init(service: TherapeuticProgramService) {
        _viewModel = StateObject(wrappedValue: TherapeuticProgramsListViewModel(service: service))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
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

                    Spacer(minLength: 40)
                }
                .padding()
            }
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Evidence-Based Programs")
                .font(.headline)

            Text("Structured therapeutic programs designed by mental health professionals to help you develop lasting coping skills.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Active Enrollment Card

    private func activeEnrollmentCard(_ enrollment: ProgramEnrollment) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Currently Enrolled")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(enrollment.program?.title ?? "Program")
                        .font(.headline)
                }

                Spacer()

                if let methodology = enrollment.program?.methodology {
                    Text(methodology.shortName)
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(methodology.color.opacity(0.2))
                        .foregroundStyle(methodology.color)
                        .clipShape(Capsule())
                }
            }

            // Progress bar
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Week \((enrollment.currentDay - 1) / 7 + 1)")
                        .font(.caption)
                    Spacer()
                    Text("\(Int(enrollment.progressPercentage * 100))% complete")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5))

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor)
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
                .padding()
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Methodology Section

    private func methodologySection(methodology: TherapeuticMethodology, programs: [Program]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: methodology.icon)
                    .foregroundStyle(methodology.color)

                Text(methodology.displayName)
                    .font(.headline)

                Spacer()

                Text("\(programs.count) program\(programs.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(program.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)

                        Text(program.formattedDuration)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if program.premiumOnly {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Target conditions
                if !program.targetConditions.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(program.targetConditions.prefix(3), id: \.self) { condition in
                            Text(condition)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(.systemGray5))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
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
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    headerSection

                    // Description
                    Text(program.description)
                        .font(.body)
                        .foregroundStyle(.secondary)

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

                    Spacer(minLength: 100)
                }
                .padding()
            }
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
        VStack(alignment: .leading, spacing: 12) {
            if let methodology = program.methodology {
                HStack {
                    Image(systemName: methodology.icon)
                    Text(methodology.displayName)
                }
                .font(.subheadline)
                .foregroundStyle(methodology.color)
            }

            HStack {
                Label(program.formattedDuration, systemImage: "calendar")
                Spacer()
                Label("\(program.estimatedDailyMinutes) min/day", systemImage: "clock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func evidenceCard(_ evidence: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Evidence-Based", systemImage: "checkmark.seal.fill")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.green)

            Text(evidence)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let url = program.evidenceUrl, let evidenceURL = URL(string: url) {
                Link(destination: evidenceURL) {
                    Label("Learn More", systemImage: "arrow.up.right")
                        .font(.caption)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var objectivesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What You'll Learn")
                .font(.headline)

            ForEach(program.learningObjectives, id: \.self) { objective in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)

                    Text(objective)
                        .font(.subheadline)
                }
            }
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Program Details")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    Text("Duration")
                        .foregroundStyle(.secondary)
                    Text(program.formattedDuration)
                        .fontWeight(.medium)
                }

                GridRow {
                    Text("Difficulty")
                        .foregroundStyle(.secondary)
                    Text(program.difficulty.displayName)
                        .fontWeight(.medium)
                }

                if program.requiresBaselineAssessment {
                    GridRow {
                        Text("Assessment")
                            .foregroundStyle(.secondary)
                        Text(program.assessmentType?.uppercased() ?? "Required")
                            .fontWeight(.medium)
                    }
                }
            }
            .font(.subheadline)
        }
    }

    private var enrollButton: some View {
        VStack(spacing: 8) {
            if !canEnroll {
                Text("Complete your current program before starting a new one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: {
                showEnrollmentConfirmation = true
            }) {
                Text(canEnroll ? "Start Program" : "Already Enrolled in Another Program")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canEnroll ? Color.accentColor : Color(.systemGray4))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!canEnroll)
        }
        .padding()
        .background(Color(.systemBackground))
    }
}

#Preview {
    Text("Therapeutic Programs List Preview")
}
