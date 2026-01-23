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
            if let error = validationError {
                Text(error)
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
                .onChange(of: reason) { _, newValue in
                    // Limit to 200 characters (server limit)
                    if newValue.count > 200 {
                        reason = String(newValue.prefix(200))
                    }
                }
        } footer: {
            HStack {
                Text("\(reason.count)/200")
                    .foregroundStyle(reason.count > 200 ? .red : .secondary)
                Spacer()
            }
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
        let days = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
        return days + 1  // +1 for inclusive counting (matching server logic)
    }
    
    private var validationError: String? {
        let today = Calendar.current.startOfDay(for: Date())
        let start = Calendar.current.startOfDay(for: startDate)
        
        // Check if start date is in the past
        if start < today {
            return "Start date cannot be in the past"
        }
        
        // Check day count range
        if dayCount < 1 {
            return "Vacation must be at least 1 day"
        }
        
        if dayCount > 14 {
            return "Maximum vacation duration is 14 days"
        }
        
        // Check reason length
        if reason.count > 200 {
            return "Reason must be 200 characters or less"
        }
        
        return nil
    }

    private var isValid: Bool {
        validationError == nil
    }

    // MARK: - Actions

    private func activateVacation() async {
        // Final validation check
        guard validationError == nil else {
            errorMessage = validationError
            return
        }
        
        isActivating = true
        defer { isActivating = false }

        do {
            // Sanitize reason (remove HTML/script tags)
            let sanitizedReason = reason
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "<", with: "")
                .replacingOccurrences(of: ">", with: "")
            
            let service = StreakShieldService(supabase: container.supabase)
            _ = try await service.toggleVacation(
                action: .activate,
                startDate: startDate,
                endDate: endDate,
                reason: sanitizedReason.isEmpty ? nil : sanitizedReason
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
