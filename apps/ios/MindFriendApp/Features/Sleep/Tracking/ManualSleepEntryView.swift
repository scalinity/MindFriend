import SwiftUI

/// View for manually logging sleep entries
struct ManualSleepEntryView: View {
    @EnvironmentObject private var container: DependencyContainer
    @Binding var isPresented: Bool

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

            struct SleepLogInsert: Encodable {
                let id: String
                let user_id: String
                let sleep_start: String
                let sleep_end: String
                let duration_minutes: Int
                let quality_rating: Int
                let notes: String?
                let source: String
            }

            let durationMinutes = Int(sleepEnd.timeIntervalSince(sleepStart) / 60)
            let formatter = ISO8601DateFormatter()

            let insert = SleepLogInsert(
                id: UUID().uuidString,
                user_id: userId.uuidString,
                sleep_start: formatter.string(from: sleepStart),
                sleep_end: formatter.string(from: sleepEnd),
                duration_minutes: durationMinutes,
                quality_rating: quality,
                notes: notes.isEmpty ? nil : notes,
                source: "manual"
            )

            try await container.supabase
                .from("sleep_logs")
                .insert(insert)
                .execute()

            isPresented = false
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }
}

#Preview {
    ManualSleepEntryView(isPresented: .constant(true))
        .environmentObject(DependencyContainer.preview)
}
