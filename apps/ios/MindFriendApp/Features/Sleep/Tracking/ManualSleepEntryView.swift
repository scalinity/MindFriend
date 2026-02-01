import SwiftUI

/// View for manually logging sleep entries
struct ManualSleepEntryView: View {
    @EnvironmentObject private var container: DependencyContainer
    @Binding var isPresented: Bool
    var onSave: (() -> Void)?

    @State private var sleepStart = Calendar.current.date(byAdding: .hour, value: -8, to: Date()) ?? Date()
    @State private var sleepEnd = Date()
    @State private var quality: Int = 3
    @State private var notes = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Sleep Time") {
                    DatePicker(
                        "Went to bed",
                        selection: $sleepStart,
                        displayedComponents: [.date, .hourAndMinute]
                    )

                    DatePicker(
                        "Woke up",
                        selection: $sleepEnd,
                        in: sleepStart...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                Section("Sleep Quality") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How well did you sleep?")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        HStack(spacing: 16) {
                            ForEach(1...5, id: \.self) { rating in
                                Button {
                                    quality = rating
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: rating <= quality ? "star.fill" : "star")
                                            .font(.title2)
                                            .foregroundColor(rating <= quality ? .yellow : .gray)

                                        Text(qualityLabel(rating))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 8)
                }

                Section("Duration") {
                    HStack {
                        Image(systemName: "clock.fill")
                            .foregroundColor(.blue)

                        Text(durationFormatted)
                            .font(.headline)
                    }
                }

                Section("Notes (Optional)") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                        .onChange(of: notes) { _, newValue in
                            if newValue.count > 2000 {
                                notes = String(newValue.prefix(2000))
                            }
                        }
                }
            }
            .navigationTitle("Log Sleep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveSleep() }
                    }
                    .disabled(isSaving || !isValidEntry)
                }
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Computed Properties

    private var durationFormatted: String {
        let duration = sleepEnd.timeIntervalSince(sleepStart)
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }

    private var isValidEntry: Bool {
        sleepEnd > sleepStart && sleepEnd.timeIntervalSince(sleepStart) >= 1800 // At least 30 min
    }

    private func qualityLabel(_ rating: Int) -> String {
        switch rating {
        case 1: return "Poor"
        case 2: return "Fair"
        case 3: return "Good"
        case 4: return "Great"
        case 5: return "Best"
        default: return ""
        }
    }

    // MARK: - Save

    private func saveSleep() async {
        isSaving = true
        defer { isSaving = false }

        do {
            guard let userId = container.supabaseAuthService.currentUser?.id else {
                errorMessage = "You must be signed in to log sleep"
                return
            }

            // Fetch goals for score calculation
            let goals = try await container.sleepTrackingService.fetchGoals()
            
            // Calculate duration
            let durationMinutes = Int(sleepEnd.timeIntervalSince(sleepStart) / 60)
            let date = Calendar.current.startOfDay(for: sleepEnd)

            // Create a SleepEntry for manual entry
            let entry = SleepEntry(
                id: UUID(),
                userId: userId,
                date: date,
                source: .manual,
                bedtime: sleepStart,
                wakeTime: sleepEnd,
                timeInBedMinutes: durationMinutes,
                timeAsleepMinutes: durationMinutes, // For manual, assume all time was asleep
                deepSleepMinutes: nil,
                remSleepMinutes: nil,
                lightSleepMinutes: nil,
                awakeMinutes: nil,
                sleepEfficiency: 100.0, // Manual entries don't have this data
                heartRateAvg: nil,
                heartRateMin: nil,
                hrvAvg: nil,
                respiratoryRate: nil,
                userRating: quality,
                dreamNotes: nil,
                notes: notes.isEmpty ? nil : notes,
                sleepScore: nil, // Will be calculated by service
                scoreBreakdown: nil,
                createdAt: Date(),
                updatedAt: Date()
            )

            // Use the tracking service to create the entry (handles score calculation)
            _ = try await container.sleepTrackingService.createEntry(entry, goals: goals)

            onSave?()
            isPresented = false
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }
}

#Preview {
    ManualSleepEntryView(isPresented: .constant(true), onSave: nil)
        .environmentObject(DependencyContainer.preview)
}
