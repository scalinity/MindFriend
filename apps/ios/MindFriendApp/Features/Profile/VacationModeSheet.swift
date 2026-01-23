import SwiftUI

/// Sheet for activating or managing vacation mode (streak freeze)
struct VacationModeSheet: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss

    @State private var startDate = Date()
    @State private var endDate = Date().addingTimeInterval(7 * 24 * 60 * 60) // Default 7 days
    @State private var reason = ""
    @State private var isActivating = false
    @State private var errorMessage: String?
    @State private var showSuccess = false

    var body: some View {
        NavigationStack {
            Form {
                vacationPeriodSection
                reasonSection
                infoSection
                activateButton
            }
            .navigationTitle("Vacation Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                }
            }
            .alert("Vacation Mode Activated", isPresented: $showSuccess) {
                Button("Done") { dismiss() }
            } message: {
                Text("Your streak is frozen for \(dayCount) days")
            }
            .disabled(isActivating)
        }
    }

    // MARK: - Sections

    private var vacationPeriodSection: some View {
        Section {
            DatePicker("Start Date", selection: $startDate, in: Date()..., displayedComponents: .date)
            DatePicker("End Date", selection: $endDate, in: startDate..., displayedComponents: .date)

            HStack {
                Text("Duration")
                Spacer()
                Text("\(dayCount) days")
                    .foregroundStyle(dayCount > 14 ? .red : .secondary)
            }
        } header: {
            Text("Vacation Period")
        } footer: {
            if dayCount > 14 {
                Text("Maximum vacation duration is 14 days")
                    .foregroundStyle(.red)
            } else {
                Text("Your streak will be frozen during this period")
            }
        }
    }

    private var reasonSection: some View {
        Section("Reason (Optional)") {
            TextField("e.g., Family vacation, work trip", text: $reason, axis: .vertical)
                .lineLimit(2...4)
        }
    }

    private var infoSection: some View {
        Section {
            Label("Your streak won't be affected during vacation mode", systemImage: "shield.fill")
                .foregroundStyle(.secondary)
                .font(.caption)

            Label("You can still complete quests if you want", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
                .font(.caption)

            Label("Free tier: 1 vacation per month", systemImage: "info.circle.fill")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    private var activateButton: some View {
        Section {
            Button {
                Task { await activateVacation() }
            } label: {
                HStack {
                    if isActivating {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isActivating ? "Activating..." : "Activate Vacation Mode")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(isActivating || !isValid)
            .listRowBackground(isValid ? Color.blue : Color.gray.opacity(0.3))
            .foregroundStyle(.white)
        }
    }

    // MARK: - Computed Properties

    private var dayCount: Int {
        Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
    }

    private var isValid: Bool {
        dayCount >= 0 && dayCount <= 14
    }

    // MARK: - Actions

    private func activateVacation() async {
        isActivating = true
        defer { isActivating = false }

        do {
            let service = StreakShieldService(supabase: container.supabase)
            _ = try await service.toggleVacation(
                action: .activate,
                startDate: startDate,
                endDate: endDate,
                reason: reason.isEmpty ? nil : reason
            )
            showSuccess = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Preview

#Preview {
    VacationModeSheet()
        .environmentObject(DependencyContainer.shared)
}
