import SwiftUI

// MARK: - Programs Library View

struct ProgramsLibraryView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer

    @State private var programs: [Program] = []
    @State private var activeEnrollment: ProgramEnrollment?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var selectedCategory: ProgramCategory?
    @State private var showARExercises = false

    // Programs tutorial state
    @AppStorage("programs_tutorial_completed") private var programsTutorialCompleted = false
    @State private var showProgramsTutorial = false

    var filteredPrograms: [Program] {
        guard let category = selectedCategory else { return programs }
        return programs.filter { $0.category == category }
    }

    /// Set by the stable shell so pushed work adds no second NavigationStack; standalone callers keep their own.
    @Environment(\.supportRootEmbedded) private var supportEmbedded

    var body: some View {
        SupportRootNavigation(embedded: supportEmbedded) {
            ScrollView {
                VStack(spacing: SupportTheme.Spacing.l) {
                    // Active program card
                    if let enrollment = activeEnrollment {
                        ActiveProgramCard(enrollment: enrollment)
                            .padding(.horizontal, SupportTheme.Spacing.m)
                    }

                    // AR Grounding section
                    ARGroundingCard(showARExercises: $showARExercises)
                        .padding(.horizontal, SupportTheme.Spacing.m)

                    // Category filter
                    CategoryFilterRow(selected: $selectedCategory)
                        .padding(.horizontal, SupportTheme.Spacing.m)

                    // Program grid
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, SupportTheme.Spacing.xl)
                    } else if let loadError {
                        SupportUnavailableState(title: "Programs unavailable", message: loadError, actionTitle: "Try again") {
                            Task { await loadData() }
                        }
                    } else if filteredPrograms.isEmpty {
                        EmptyProgramsView(hasFilter: selectedCategory != nil) {
                            selectedCategory = nil
                        }
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: SupportTheme.Spacing.m) {
                            ForEach(filteredPrograms) { program in
                                NavigationLink {
                                    ProgramDetailView(program: program)
                                } label: {
                                    ProgramCard(program: program)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, SupportTheme.Spacing.m)
                    }
                }
                .padding(.vertical, SupportTheme.Spacing.m)
            }
            .supportScreen()
            .navigationTitle("Programs")
            .task { await loadData() }
            .refreshable { await loadData() }
            .fullScreenCover(isPresented: $showARExercises) {
                ARExerciseListView()
                    .environmentObject(container)
                    .environmentObject(container.arExerciseService)
                    .environmentObject(container.arCapabilityService)
            }
            .onAppear {
                if !programsTutorialCompleted {
                    showProgramsTutorial = true
                }
            }
            .fullScreenCover(isPresented: $showProgramsTutorial) {
                ProgramsTutorialFlow(onComplete: {
                    programsTutorialCompleted = true
                    showProgramsTutorial = false
                })
                .environmentObject(container)
            }
        }
    }

    private func loadData() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            async let programsTask = container.supabaseDataService.getPrograms()
            async let enrollmentTask = container.supabaseDataService.getActiveEnrollment()

            programs = try await programsTask
            activeEnrollment = try await enrollmentTask
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// MARK: - AR Grounding Card

struct ARGroundingCard: View {
    @Binding var showARExercises: Bool

    var body: some View {
        Button {
            showARExercises = true
        } label: {
            HStack(spacing: SupportTheme.Spacing.m) {
                // AR Icon
                ZStack {
                    RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                        .fill(
                            SupportTheme.surface
                        )
                        .frame(width: 56, height: 56)

                    Image(systemName: "arkit")
                        .font(.title2)
                        .foregroundStyle(SupportTheme.textPrimary)
                }

                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text("AR Grounding")
                        .font(.headline)

                    Text("Immersive exercises using augmented reality")
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
            .supportCard()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("AR Grounding")
        .accessibilityHint("Open immersive augmented reality grounding exercises")
    }
}

// MARK: - Category Filter Row

struct CategoryFilterRow: View {
    @Binding var selected: ProgramCategory?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SupportTheme.Spacing.xs) {
                // All category button
                FilterChip(
                    label: "All",
                    isSelected: selected == nil
                ) {
                    selected = nil
                }

                ForEach(ProgramCategory.allCases, id: \.self) { category in
                    FilterChip(
                        label: category.displayName,
                        icon: category.icon,
                        color: SupportTheme.accent,
                        isSelected: selected == category
                    ) {
                        selected = category
                    }
                }
            }
        }
    }
}

struct FilterChip: View {
    let label: String
    var icon: String? = nil
    var color: Color = .blue
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SupportTheme.Spacing.xxs) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(label)
                    .font(.subheadline)
            }
            .padding(.horizontal, SupportTheme.Spacing.s)
            .padding(.vertical, SupportTheme.Spacing.xs)
            .background(isSelected ? color : SupportTheme.surface)
            .foregroundStyle(isSelected ? SupportTheme.onAccent : SupportTheme.textPrimary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Program Card

struct ProgramCard: View {
    let program: Program

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            // Cover image or icon
            ZStack {
                RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                    .fill(SupportTheme.accent)

                Image(systemName: program.category.icon)
                    .font(.largeTitle)
                    .foregroundStyle(SupportTheme.textPrimary.opacity(0.8))
            }
            .frame(height: 100)

            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                // Title - fixed height for 2 lines
                Text(program.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .frame(height: 48, alignment: .topLeading)

                // Duration - single line, no wrapping
                Text("\(program.formattedDuration)  •  \(program.estimatedDailyMinutes) min/day")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Premium badge - fixed height to reserve space
                Group {
                    if program.premiumOnly {
                        Label("Premium", systemImage: "crown.fill")
                            .font(.caption2)
                            .foregroundStyle(SupportTheme.accent)
                    } else {
                        Color.clear
                    }
                }
                .frame(height: 16)
            }
        }
    }
}

// MARK: - Active Program Card

struct ActiveProgramCard: View {
    let enrollment: ProgramEnrollment

    var body: some View {
        NavigationLink {
            ProgramDayView(enrollment: enrollment)
        } label: {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Continue Program")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                        Text(enrollment.program?.title ?? "")
                            .font(.headline)
                    }

                    Spacer()

                    Text("Day \(enrollment.currentDay)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(SupportTheme.accent)
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                            .fill(SupportTheme.separator)

                        RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                            .fill(SupportTheme.accent)
                            .frame(width: geo.size.width * enrollment.progressPercentage)
                    }
                }
                .frame(height: 8)

                HStack {
                    Spacer()
                    Text("\(enrollment.daysRemaining) days left")
                }
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
            }
            .supportCard()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Empty State

struct EmptyProgramsView: View {
    let hasFilter: Bool
    let clearFilter: () -> Void

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            Image(systemName: "book.closed")
                .font(.system(.largeTitle))
                .foregroundStyle(SupportTheme.textSecondary)

            Text(hasFilter ? "No programs in this category" : "No programs available")
                .font(.headline)

            if hasFilter {
                Button("Clear Filter", action: clearFilter)
                    .buttonStyle(.supportSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, SupportTheme.Spacing.xl)
    }
}

#Preview {
    ProgramsLibraryView()
        .environmentObject(AppState())
        .environmentObject(DependencyContainer())
}
