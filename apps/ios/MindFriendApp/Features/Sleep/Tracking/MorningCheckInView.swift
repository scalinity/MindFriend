import SwiftUI

/// Morning check-in modal for rating sleep quality and adding notes
struct MorningCheckInView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dependencies: DependencyContainer
    @StateObject private var viewModel: MorningCheckInViewModel

    init(entry: SleepEntry) {
        _viewModel = StateObject(wrappedValue: MorningCheckInViewModel(entry: entry))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection

                    // Sleep Duration
                    durationSection

                    // Rating
                    ratingSection

                    // Dream Notes
                    dreamNotesSection

                    // Additional Notes
                    notesSection

                    // Save Button
                    saveButton
                }
                .padding()
            }
            .navigationTitle("Morning Check-In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Skip") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "sun.horizon.fill")
                .font(.system(size: 50))
                .foregroundColor(.orange)

            Text("Good Morning!")
                .font(.title2)
                .fontWeight(.semibold)

            Text("How did you sleep last night?")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Duration

    @ViewBuilder
    private var durationSection: some View {
        VStack(spacing: 8) {
            Text("Sleep Duration")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.entry.durationFormatted)
                        .font(.title)
                        .fontWeight(.bold)

                    if let score = viewModel.entry.sleepScore {
                        Text("Score: \(score)/100")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if let _ = viewModel.entry.scoreBreakdown {
                    SleepScoreRing(score: viewModel.entry.sleepScore ?? 0, size: 80)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }

    // MARK: - Rating

    @ViewBuilder
    private var ratingSection: some View {
        VStack(spacing: 12) {
            Text("Rate Your Sleep")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 16) {
                ForEach(1...5, id: \.self) { rating in
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            viewModel.rating = rating
                        }
                    } label: {
                        Image(systemName: rating <= viewModel.rating ? "star.fill" : "star")
                            .font(.title)
                            .foregroundColor(rating <= viewModel.rating ? .yellow : .gray)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)

            // Rating labels
            HStack {
                Text("Poor")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("Excellent")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Dream Notes

    @ViewBuilder
    private var dreamNotesSection: some View {
        VStack(spacing: 8) {
            Text("Dream Notes (Optional)")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextEditor(text: $viewModel.dreamNotes)
                .frame(height: 100)
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if viewModel.dreamNotes.isEmpty {
                        Text("Anything memorable from your dreams?")
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    // MARK: - Notes

    @ViewBuilder
    private var notesSection: some View {
        VStack(spacing: 8) {
            Text("Additional Notes (Optional)")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextEditor(text: $viewModel.notes)
                .frame(height: 80)
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if viewModel.notes.isEmpty {
                        Text("Any factors that affected your sleep?")
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    // MARK: - Save Button

    @ViewBuilder
    private var saveButton: some View {
        Button {
            Task {
                await viewModel.save(trackingService: dependencies.sleepTrackingService)
                dismiss()
            }
        } label: {
            if viewModel.isSaving {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor.opacity(0.6))
                    .cornerRadius(12)
            } else {
                Text("Save Check-In")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.canSave ? Color.accentColor : Color.gray)
                    .cornerRadius(12)
            }
        }
        .disabled(!viewModel.canSave || viewModel.isSaving)
    }
}

// MARK: - View Model

@MainActor
final class MorningCheckInViewModel: ObservableObject {
    let entry: SleepEntry

    @Published var rating: Int = 0
    @Published var dreamNotes: String = ""
    @Published var notes: String = ""
    @Published var isSaving = false

    var canSave: Bool {
        rating > 0
    }

    init(entry: SleepEntry) {
        self.entry = entry
        self.rating = entry.userRating ?? 0
        self.dreamNotes = entry.dreamNotes ?? ""
        self.notes = entry.notes ?? ""
    }

    func save(trackingService: SleepTrackingService) async {
        guard canSave else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            try await trackingService.updateEntry(
                id: entry.id,
                rating: rating,
                dreamNotes: dreamNotes.isEmpty ? nil : dreamNotes,
                notes: notes.isEmpty ? nil : notes
            )
        } catch {
            print("Failed to save check-in: \(error)")
        }
    }
}

#Preview {
    let entry = SleepEntry(
        id: UUID(),
        userId: UUID(),
        date: Date(),
        source: .healthkit,
        bedtime: Calendar.current.date(byAdding: .hour, value: -8, to: Date())!,
        wakeTime: Date(),
        timeInBedMinutes: 480,
        timeAsleepMinutes: 420,
        deepSleepMinutes: 90,
        remSleepMinutes: 105,
        lightSleepMinutes: 225,
        awakeMinutes: 30,
        sleepEfficiency: 87.5,
        heartRateAvg: 58,
        heartRateMin: 48,
        hrvAvg: 65.3,
        respiratoryRate: 14.2,
        userRating: nil,
        dreamNotes: nil,
        notes: nil,
        sleepScore: 82,
        scoreBreakdown: SleepScoreBreakdown(
            duration: 22,
            efficiency: 23,
            timing: 18,
            stages: 15,
            restfulness: 4
        ),
        createdAt: Date(),
        updatedAt: Date()
    )

    return MorningCheckInView(entry: entry)
        .environmentObject(DependencyContainer.preview)
}
