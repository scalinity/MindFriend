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
                    VStack(spacing: 16) {
                        Image(systemName: "pills")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)

                        Text("No medications yet")
                            .font(.headline)

                        Text("Start tracking your medications to monitor adherence and mood correlation")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button(action: { showAddMedication = true }) {
                            Label("Add Medication", systemImage: "plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
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
                        }

                        // Adherence Section
                        Section("Adherence") {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("This Month")
                                    Spacer()
                                    Text(String(format: "%.0f%%", viewModel.adherenceRate * 100))
                                        .font(.headline)
                                }

                                ProgressView(value: viewModel.adherenceRate)
                                    .tint(.green)
                            }
                            .padding(.vertical, 8)
                        }

                        // My Medications Section
                        Section("My Medications") {
                            ForEach(viewModel.medications) { medication in
                                NavigationLink(destination: MedicationDetailView(medication: medication)) {
                                    HStack {
                                        Image(systemName: medication.icon.systemImage)
                                            .frame(width: 32, height: 32)
                                            .background(Color.blue.opacity(0.1))
                                            .cornerRadius(8)

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(medication.name)
                                                .font(.headline)

                                            if let dosage = medication.dosage {
                                                Text(dosage)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }

                                            Text(medication.frequency.description)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer()
                                    }
                                }
                            }
                        }
                    }
                }
            }
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
            .alert(isPresented: Binding(get: { !viewModel.errorMessage.isEmpty }, set: { if !$0 { viewModel.errorMessage = "" } })) {
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
            VStack(alignment: .leading, spacing: 4) {
                Text(item.scheduledAt.formatted(date: .omitted, time: .shortened))
                    .font(.headline)

                Text(item.medication.name)
                    .font(.caption)
                    .foregroundColor(.secondary)
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
        case .taken: return .green
        case .skipped: return .red
        case .late: return .orange
        case .pending: return .gray
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
