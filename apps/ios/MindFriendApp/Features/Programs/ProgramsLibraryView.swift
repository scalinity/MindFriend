import SwiftUI

// MARK: - Programs Library View

struct ProgramsLibraryView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer

    @State private var programs: [Program] = []
    @State private var activeEnrollment: ProgramEnrollment?
    @State private var isLoading = true
    @State private var selectedCategory: ProgramCategory?

    var filteredPrograms: [Program] {
        guard let category = selectedCategory else { return programs }
        return programs.filter { $0.category == category }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Active program card
                    if let enrollment = activeEnrollment {
                        ActiveProgramCard(enrollment: enrollment)
                            .padding(.horizontal)
                    }

                    // Category filter
                    CategoryFilterRow(selected: $selectedCategory)
                        .padding(.horizontal)

                    // Program grid
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else if filteredPrograms.isEmpty {
                        EmptyProgramsView(hasFilter: selectedCategory != nil) {
                            selectedCategory = nil
                        }
                    } else {
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 16) {
                            ForEach(filteredPrograms) { program in
                                NavigationLink {
                                    ProgramDetailView(program: program)
                                } label: {
                                    ProgramCard(program: program)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Programs")
            .task { await loadData() }
            .refreshable { await loadData() }
        }
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let programsTask = container.supabaseDataService.getPrograms()
            async let enrollmentTask = container.supabaseDataService.getActiveEnrollment()

            programs = try await programsTask
            activeEnrollment = try await enrollmentTask
        } catch {
            appState.showError(.apiError(error.localizedDescription))
        }
    }
}

// MARK: - Category Filter Row

struct CategoryFilterRow: View {
    @Binding var selected: ProgramCategory?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
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
                        color: category.color,
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
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(label)
                    .font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? color : Color(.secondarySystemBackground))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Program Card

struct ProgramCard: View {
    let program: Program

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover image or icon
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(program.category.color.gradient)

                Image(systemName: program.category.icon)
                    .font(.largeTitle)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .frame(height: 100)

            VStack(alignment: .leading, spacing: 4) {
                Text(program.title)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack {
                    Text(program.formattedDuration)
                    Text("•")
                    Text("\(program.estimatedDailyMinutes) min/day")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if program.premiumOnly {
                    Label("Premium", systemImage: "crown.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
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
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Continue Program")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(enrollment.program?.title ?? "")
                            .font(.headline)
                    }

                    Spacer()

                    Text("Day \(enrollment.currentDay)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(enrollment.program?.category.color ?? .blue)
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5))

                        RoundedRectangle(cornerRadius: 4)
                            .fill(enrollment.program?.category.color ?? .blue)
                            .frame(width: geo.size.width * enrollment.progressPercentage)
                    }
                }
                .frame(height: 8)

                HStack {
                    Label("\(enrollment.streakDays) day streak", systemImage: "flame")
                    Spacer()
                    Text("\(enrollment.daysRemaining) days left")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Empty State

struct EmptyProgramsView: View {
    let hasFilter: Bool
    let clearFilter: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(hasFilter ? "No programs in this category" : "No programs available")
                .font(.headline)

            if hasFilter {
                Button("Clear Filter", action: clearFilter)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

#Preview {
    ProgramsLibraryView()
        .environmentObject(AppState())
        .environmentObject(DependencyContainer())
}
