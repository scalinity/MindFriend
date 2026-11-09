import SwiftUI

/// Morning check-in modal for rating sleep quality and adding notes
struct MorningCheckInView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dependencies: DependencyContainer
    @StateObject private var viewModel: MorningCheckInViewModel
    private let onSkip: () -> Void

    init(entry: SleepEntry, onSkip: @escaping () -> Void = {}) {
        self.onSkip = onSkip
        _viewModel = StateObject(wrappedValue: MorningCheckInViewModel(entry: entry))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SupportTheme.Spacing.l) {
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
            .supportScreen()
            .foregroundStyle(SupportTheme.textPrimary)
            .navigationTitle("Morning Check-In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Skip") {
                        onSkip()
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerSection: some View {
        VStack(spacing: SupportTheme.Spacing.s) {
            Image(systemName: "sun.horizon.fill")
                .font(.system(size: 50))
                .foregroundColor(SupportTheme.accent)

            Text("Good Morning!")
                .font(.title2)
                .accessibilityAddTraits(.isHeader)
                .fontWeight(.semibold)

            Text("How did you sleep last night?")
                .font(.subheadline)
                .foregroundColor(SupportTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SupportTheme.Spacing.l)
    }

    // MARK: - Duration

    @ViewBuilder
    private var durationSection: some View {
        VStack(spacing: SupportTheme.Spacing.xs) {
            Text("Sleep Duration")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text(viewModel.entry.durationFormatted)
                        .font(.title)
                        .accessibilityAddTraits(.isHeader)
                        .fontWeight(.bold)

                    if let score = viewModel.entry.sleepScore {
                        Text("Score: \(score)/100")
                            .font(.subheadline)
                            .foregroundColor(SupportTheme.textSecondary)
                    }
                }

                Spacer()

                if viewModel.entry.scoreBreakdown != nil {
                    SleepScoreRing(score: viewModel.entry.sleepScore ?? 0, size: 80)
                }
            }
            .padding()
            .background(SupportTheme.field)
            .cornerRadius(SupportTheme.controlRadius)
        }
    }

    // MARK: - Rating

    @ViewBuilder
    private var ratingSection: some View {
        VStack(spacing: SupportTheme.Spacing.s) {
            Text("Rate Your Sleep")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: SupportTheme.Spacing.m) {
                ForEach(1...5, id: \.self) { rating in
                    Button {
                        withAnimation(reduceMotion ? nil : (.spring(response: 0.3))) {
                            viewModel.rating = rating
                        }
                    } label: {
                        Image(systemName: rating <= viewModel.rating ? "star.fill" : "star")
                            .font(.title)
                            .foregroundColor(
                                rating <= viewModel.rating ? SupportTheme.Celebration.gold : SupportTheme.textSecondary)
                    }
                    .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                    .accessibilityLabel("Rate \(rating) out of 5")
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(SupportTheme.field)
            .cornerRadius(SupportTheme.controlRadius)

            // Rating labels
            HStack {
                Text("Poor")
                    .font(.caption)
                    .foregroundColor(SupportTheme.textSecondary)

                Spacer()

                Text("Excellent")
                    .font(.caption)
                    .foregroundColor(SupportTheme.textSecondary)
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Dream Notes

    @ViewBuilder
    private var dreamNotesSection: some View {
        VStack(spacing: SupportTheme.Spacing.xs) {
            Text("Dream Notes (Optional)")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextEditor(text: $viewModel.dreamNotes)
                .frame(height: 100)
                .padding(SupportTheme.Spacing.xs)
                .background(SupportTheme.field)
                .cornerRadius(SupportTheme.controlRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: SupportTheme.cardRadius)
                        .stroke(SupportTheme.field, lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if viewModel.dreamNotes.isEmpty {
                        Text("Anything memorable from your dreams?")
                            .foregroundColor(SupportTheme.textSecondary)
                            .padding(.horizontal, SupportTheme.Spacing.s)
                            .padding(.vertical, SupportTheme.Spacing.m)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    // MARK: - Notes

    @ViewBuilder
    private var notesSection: some View {
        VStack(spacing: SupportTheme.Spacing.xs) {
            Text("Additional Notes (Optional)")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextEditor(text: $viewModel.notes)
                .frame(height: 80)
                .padding(SupportTheme.Spacing.xs)
                .background(SupportTheme.field)
                .cornerRadius(SupportTheme.controlRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: SupportTheme.cardRadius)
                        .stroke(SupportTheme.field, lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if viewModel.notes.isEmpty {
                        Text("Any factors that affected your sleep?")
                            .foregroundColor(SupportTheme.textSecondary)
                            .padding(.horizontal, SupportTheme.Spacing.s)
                            .padding(.vertical, SupportTheme.Spacing.m)
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
                    .tint(SupportTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(SupportTheme.surface)
                    .cornerRadius(SupportTheme.controlRadius)
            } else {
                Text("Save Check-In")
                    .fontWeight(.semibold)
                    .foregroundColor(SupportTheme.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.canSave ? SupportTheme.accent : SupportTheme.textSecondary)
                    .cornerRadius(SupportTheme.controlRadius)
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
