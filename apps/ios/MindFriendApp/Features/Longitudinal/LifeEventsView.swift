import SwiftUI

// MARK: - Life Events View

struct LifeEventsView: View {
    @EnvironmentObject private var container: DependencyContainer
    @StateObject private var viewModel = LifeEventsViewModel()
    @State private var showingAddSheet = false
    @State private var selectedFilter: EventType?

    var body: some View {
        ScrollView {
            VStack(spacing: SupportTheme.Spacing.l) {
                if viewModel.isLoading {
                    loadingView
                } else if viewModel.events.isEmpty {
                    emptyStateView
                } else {
                    // Filter chips
                    filterSection

                    // Timeline
                    timelineSection
                }
            }
            .padding()
        }
        .supportScreen()
        .foregroundStyle(SupportTheme.textPrimary)
        .navigationTitle("Life Events")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                .accessibilityLabel("Add")
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddLifeEventSheet(viewModel: viewModel)
        }
        .task {
            viewModel.setService(container.longitudinalService)
            await viewModel.loadEvents()
        }
    }

    // MARK: - Filter Section

    private var filterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SupportTheme.Spacing.xs) {
                LongitudinalFilterChip(
                    title: "All",
                    isSelected: selectedFilter == nil
                ) {
                    selectedFilter = nil
                }

                ForEach(EventType.allCases, id: \.self) { type in
                    LongitudinalFilterChip(
                        title: type.displayName,
                        isSelected: selectedFilter == type
                    ) {
                        selectedFilter = type
                    }
                }
            }
        }
    }

    // MARK: - Timeline Section

    private var timelineSection: some View {
        VStack(spacing: 0) {
            ForEach(Array(filteredEvents.enumerated()), id: \.element.id) { index, event in
                LifeEventTimelineItem(
                    event: event,
                    isFirst: index == 0,
                    isLast: index == filteredEvents.count - 1,
                    onDelete: {
                        Task {
                            await viewModel.deleteEvent(event)
                        }
                    }
                )
            }
        }
    }

    private var filteredEvents: [LifeEvent] {
        if let filter = selectedFilter {
            return viewModel.events.filter { $0.eventType == filter }
        }
        return viewModel.events
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            ProgressView()
            Text("Loading events...")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(SupportTheme.accent)
            Text("Track Your Life Events")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("Log significant life events to understand how they impact your wellness journey.")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                showingAddSheet = true
            } label: {
                Text("Add Your First Event")
            }
            .buttonStyle(.supportPrimary)
        }
        .padding(SupportTheme.Spacing.xl)
    }
}

// MARK: - View Model

@MainActor
final class LifeEventsViewModel: ObservableObject {
    @Published var events: [LifeEvent] = []
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var error: String?

    private var service: LongitudinalService?

    func setService(_ service: LongitudinalService) {
        self.service = service
    }

    func loadEvents() async {
        guard let service else { return }

        isLoading = true

        do {
            events = try await service.fetchLifeEvents()
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func addEvent(type: EventType, date: Date, notes: String?) async {
        guard let service else { return }

        isSaving = true

        do {
            let input = LifeEventInput(eventType: type, eventDate: date, notes: notes)
            let newEvent = try await service.addLifeEvent(input)
            events.insert(newEvent, at: 0)
        } catch {
            self.error = error.localizedDescription
        }

        isSaving = false
    }

    func deleteEvent(_ event: LifeEvent) async {
        guard let service else { return }

        do {
            try await service.deleteLifeEvent(id: event.id)
            events.removeAll { $0.id == event.id }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Timeline Item

struct LifeEventTimelineItem: View {
    let event: LifeEvent
    let isFirst: Bool
    let isLast: Bool
    let onDelete: () -> Void

    @State private var showingDeleteConfirmation = false

    var body: some View {
        HStack(alignment: .top, spacing: SupportTheme.Spacing.m) {
            // Timeline line and dot
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? .clear : SupportTheme.field)
                    .frame(width: 2, height: 20)

                Circle()
                    .fill(impactColor)
                    .frame(width: 12, height: 12)

                Rectangle()
                    .fill(isLast ? .clear : SupportTheme.field)
                    .frame(width: 2)
            }
            .frame(width: 12)

            // Event card
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                HStack {
                    Image(systemName: event.eventType.icon)
                        .foregroundStyle(impactColor)
                    Text(event.eventType.displayName)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Text(event.formattedDate)
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }

                if let impact = event.impactScore {
                    HStack(spacing: SupportTheme.Spacing.xxs) {
                        Image(systemName: event.impactIcon)
                            .font(.caption)
                        Text(impactDescription(impact))
                            .font(.caption)
                    }
                    .foregroundStyle(impactColor)
                }

                if let notes = event.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)
                        .lineLimit(3)
                }

                // Metrics comparison
                if let before = event.beforeMetrics,
                    let after = event.afterMetrics
                {
                    HStack(spacing: SupportTheme.Spacing.m) {
                        MetricComparison(
                            label: "Mood",
                            before: before.avgMood,
                            after: after.avgMood
                        )
                        if let recovery = event.recoveryDays {
                            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                                Text("Recovery")
                                    .font(.caption2)
                                    .foregroundStyle(SupportTheme.textSecondary)
                                Text("\(recovery) days")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                        }
                    }
                    .padding(.top, SupportTheme.Spacing.xxs)
                }

                if event.isOngoing {
                    Label("Ongoing", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.accent)
                        .padding(.top, SupportTheme.Spacing.xxs)
                }
            }
            .supportCard()
            .shadow(color: SupportTheme.canvas.opacity(0.05), radius: 4, y: 2)
            .contextMenu {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .confirmationDialog(
                "Delete this life event?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive, action: onDelete)
                Button("Cancel", role: .cancel) {}
            }
        }
        .padding(.vertical, SupportTheme.Spacing.xs)
    }

    private var impactColor: Color {
        guard let score = event.impactScore else { return SupportTheme.textSecondary }
        if score > 0 { return SupportTheme.accent }
        if score < 0 { return .red }
        return SupportTheme.textSecondary
    }

    private func impactDescription(_ score: Double) -> String {
        if score > 0.5 { return "Positive impact" }
        if score < -0.5 { return "Challenging impact" }
        return "Neutral impact"
    }
}

// MARK: - Add Life Event Sheet

struct AddLifeEventSheet: View {
    @ObservedObject var viewModel: LifeEventsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: EventType = .other
    @State private var eventDate = Date()
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Event Type") {
                    Picker("Type", selection: $selectedType) {
                        ForEach(EventType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .listRowBackground(SupportTheme.surface)

                Section("When") {
                    DatePicker(
                        "Date",
                        selection: $eventDate,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                }

                .listRowBackground(SupportTheme.surface)

                Section("Notes (Optional)") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }

                .listRowBackground(SupportTheme.surface)
            }
            .supportScreen()
            .foregroundStyle(SupportTheme.textPrimary)
            .navigationTitle("Log Life Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await viewModel.addEvent(
                                type: selectedType,
                                date: eventDate,
                                notes: notes.isEmpty ? nil : notes
                            )
                            dismiss()
                        }
                    }
                    .disabled(viewModel.isSaving)
                }
            }
        }
    }
}

// MARK: - Metric Comparison

struct MetricComparison: View {
    let label: String
    let before: Double
    let after: Double

    var delta: Double {
        after - before
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(SupportTheme.textSecondary)

            HStack(spacing: SupportTheme.Spacing.xxs) {
                Text(String(format: "%.1f", before))
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
                Image(systemName: delta >= 0 ? "arrow.right" : "arrow.right")
                    .font(.caption2)
                Text(String(format: "%.1f", after))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(delta >= 0 ? SupportTheme.accent : .red)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
    struct LifeEventsView_Previews: PreviewProvider {
        static var previews: some View {
            NavigationStack {
                LifeEventsView()
                    .environmentObject(DependencyContainer.preview)
            }
        }
    }
#endif
