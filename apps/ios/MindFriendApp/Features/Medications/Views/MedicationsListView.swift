import SwiftUI

struct MedicationsListView: View {
    @StateObject private var viewModel: MedicationListViewModel
    @State private var showAddMedication = false

    init(viewModel: MedicationListViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if viewModel.isLoading {
                    ProgressView()
                } else if viewModel.medications.isEmpty {
                    VStack(spacing: SupportTheme.Spacing.m) {
                        Image(systemName: "pills")
                            .font(.system(size: 48))
                            .foregroundColor(SupportTheme.textSecondary)

                        Text("No medications yet")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)

                        Text("Start tracking your medications to monitor adherence and mood correlation")
                            .font(.caption)
                            .foregroundColor(SupportTheme.textSecondary)
                            .multilineTextAlignment(.center)

                        Button(action: { showAddMedication = true }) {
                            Label("Add Medication", systemImage: "plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.supportPrimary)
                    }
                    .padding()
                } else {
                    List {
                        // Today's Schedule Section
                        if !viewModel.todaySchedule.isEmpty {
                            Section("Today's Schedule") {
                                ForEach(viewModel.todaySchedule) { item in
                                    MedicationScheduleRow(item: item)
                                }
                            }
                            .listRowBackground(SupportTheme.surface)
                        }

                        // Adherence Section
                        Section("Adherence") {
                            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                                HStack {
                                    Text("This Month")
                                    Spacer()
                                    Text(String(format: "%.0f%%", viewModel.adherenceRate * 100))
                                        .font(.headline)
                                        .accessibilityAddTraits(.isHeader)
                                }

                                ProgressView(value: viewModel.adherenceRate)
                                    .tint(SupportTheme.accent)
                            }
                            .padding(.vertical, SupportTheme.Spacing.xs)
                        }

                        .listRowBackground(SupportTheme.surface)

                        // My Medications Section
                        Section("My Medications") {
                            ForEach(viewModel.medications) { medication in
                                NavigationLink(destination: MedicationDetailView(medication: medication)) {
                                    HStack {
                                        Image(systemName: medication.icon.systemImage)
                                            .frame(width: 32, height: 32)
                                            .background(SupportTheme.surface)
                                            .cornerRadius(SupportTheme.controlRadius)

                                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                                            Text(medication.name)
                                                .font(.headline)
                                                .accessibilityAddTraits(.isHeader)

                                            if let dosage = medication.dosage {
                                                Text(dosage)
                                                    .font(.caption)
                                                    .foregroundColor(SupportTheme.textSecondary)
                                            }

                                            Text(medication.frequency.description)
                                                .font(.caption)
                                                .foregroundColor(SupportTheme.textSecondary)
                                        }

                                        Spacer()
                                    }
                                }
                            }
                        }

                        .listRowBackground(SupportTheme.surface)
                    }
                }
            }
            .supportScreen()
            .foregroundStyle(SupportTheme.textPrimary)
            .navigationTitle("Medications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showAddMedication = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddMedication) {
                AddMedicationView(isPresented: $showAddMedication)
            }
            .alert(
                isPresented: Binding(
                    get: { !viewModel.errorMessage.isEmpty }, set: { if !$0 { viewModel.errorMessage = "" } })
            ) {
                Alert(
                    title: Text("Error"),
                    message: Text(viewModel.errorMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .task {
            await viewModel.loadMedications()
            await viewModel.loadTodaySchedule()
            await viewModel.calculateAdherence()
        }
    }
}

struct MedicationScheduleRow: View {
    let item: ScheduledMedication

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(item.scheduledAt.formatted(date: .omitted, time: .shortened))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                Text(item.medication.name)
                    .font(.caption)
                    .foregroundColor(SupportTheme.textSecondary)
            }

            Spacer()

            Image(systemName: statusIcon)
                .foregroundColor(statusColor)
        }
        .contentShape(Rectangle())
    }

    private var statusIcon: String {
        switch item.status {
        case .taken: return "checkmark.circle.fill"
        case .skipped: return "xmark.circle.fill"
        case .late: return "clock.fill"
        case .pending: return "circle"
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .taken: return SupportTheme.accent
        case .skipped: return .red
        case .late: return SupportTheme.accent
        case .pending: return SupportTheme.textSecondary
        }
    }
}

#Preview {
    // TODO: Medications feature needs proper service setup in DependencyContainer
    // MedicationsListView(viewModel: MedicationListViewModel(service: MockMedicationService()))
    Text("Medications feature preview temporarily disabled")
}

// Mock for preview
class MockMedicationService: MedicationService {
    override init(
        medicationRepository: MedicationRepository,
        logRepository: MedicationLogRepository,
        notificationScheduler: NotificationScheduler,
        adherenceCalculator: AdherenceCalculator
    ) {
        super.init(
            medicationRepository: medicationRepository,
            logRepository: logRepository,
            notificationScheduler: notificationScheduler,
            adherenceCalculator: adherenceCalculator
        )
    }
}
