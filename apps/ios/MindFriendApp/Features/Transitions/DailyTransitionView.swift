import SwiftUI

struct DailyTransitionView: View {
    @EnvironmentObject var container: DependencyContainer
    let userPathway: UserPathway
    let content: DailyPathwayContent
    @Environment(\.dismiss) var dismiss

    @State private var mood: Double = 5
    @State private var energy: Double = 5
    @State private var notes = ""
    @State private var journalEntry = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.l) {
                themeSection
                checkInSection
                journalSection
                affirmationSection
                submitButton
            }
            .padding(SupportTheme.Spacing.m)
        }
        .supportScreen()
        .navigationTitle("Day \(content.dayNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Submit") {
                    submitCheckIn()
                }
                .disabled(isSubmitting)
            }
        }
        .overlay {
            if isSubmitting {
                ProgressView("Saving check-in...")
                    .supportCard()
                    .shadow(radius: 10)
            }
        }
        .safeAreaInset(edge: .bottom) {
                if showError {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                    Text(errorMessage ?? "Unknown error occurred")

                    Button("OK", role: .cancel) { showError = false; }
                }
                    .foregroundStyle(SupportTheme.textSecondary)
                    .buttonStyle(.supportSecondary)
                    .supportCard()
                    .padding(SupportTheme.Spacing.m)
                }
            }
        .onAppear {
            // ✅ Load encrypted journal draft via service layer (proper encapsulation)
            do {
                if let draft = try container.transitionService.getJournalDraft(for: userPathway.id) {
                    journalEntry = draft
                }
            } catch {
                // ✅ SECURITY FIX: Don't log error details (may contain decrypted PHI)
                print("⚠️ Failed to load journal draft for pathway \(userPathway.id.uuidString)")
            }
        }
        .onChange(of: journalEntry) {
            // ✅ Save encrypted journal draft via service layer (proper encapsulation)
            do {
                try container.transitionService.saveJournalDraft(journalEntry, for: userPathway.id)
            } catch {
                // ✅ SECURITY FIX: Don't log error details (may contain PHI)
                print("⚠️ Failed to save journal draft for pathway \(userPathway.id.uuidString)")
            }
        }
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            Text(content.theme.title)
                .font(.title2.weight(.bold))
            Text(content.theme.message)
                .font(.body)
                .foregroundColor(SupportTheme.textSecondary)
        }
        .padding(SupportTheme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SupportTheme.separator)
        .cornerRadius(SupportTheme.controlRadius)
    }

    private var checkInSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
            Text("Daily Check-In")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Text(content.checkInPrompt)
                .font(.subheadline)
                .foregroundColor(SupportTheme.textSecondary)

            VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                Text("How are you feeling?")
                    .font(.headline)

                VStack(alignment: .leading) {
                    Text("Mood: \(Int(mood))/10")
                    Slider(value: $mood, in: 1...10, step: 1)
                }

                VStack(alignment: .leading) {
                    Text("Energy: \(Int(energy))/10")
                    Slider(value: $energy, in: 1...10, step: 1)
                }
            }
        }
        .supportCard()
    }

    @ViewBuilder
    private var journalSection: some View {
        if let journalPrompt = content.journalPrompt {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                Text("Journal Prompt")
                    .font(.headline)
                Text(journalPrompt)
                    .font(.subheadline)
                    .foregroundColor(SupportTheme.textSecondary)
                TextEditor(text: $journalEntry)
                    .frame(minHeight: 120)
                    .padding(SupportTheme.Spacing.xxs)
                    .background(SupportTheme.canvas)
                    .cornerRadius(SupportTheme.controlRadius)
            }
            .supportCard()
        }
    }

    private var affirmationSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            Text("Today's Affirmation")
                .font(.headline)
            Text(content.affirmation)
                .font(.body.italic())
                .foregroundColor(SupportTheme.textSecondary)
        }
        .supportCard()
    }

    private var submitButton: some View {
        Button(action: { submitCheckIn() }) {
            Text(isSubmitting ? "Submitting..." : "Complete Check-In")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(SupportTheme.Spacing.m)
                .background(SupportTheme.accent)
                .foregroundColor(SupportTheme.onAccent)
                .cornerRadius(SupportTheme.controlRadius)
        }
        .disabled(isSubmitting)
    }

    func submitCheckIn() {
        isSubmitting = true

        Task {
            let checkInData = CheckInData(
                mood: Int(mood),
                energy: Int(energy),
                notes: notes.isEmpty ? nil : notes,
                responses: nil
            )

            do {
                let response = try await container.transitionService.completeCheckIn(
                    userPathwayId: userPathway.id,
                    checkInData: checkInData,
                    journalEntry: journalEntry.isEmpty ? nil : journalEntry
                )
                print("[CheckIn] Success! newDay=\(response.newDay) phaseAdvanced=\(response.phaseAdvanced)")
                // Clear encrypted draft on success via service layer
                container.transitionService.clearJournalDraft(for: userPathway.id)
                isSubmitting = false
                dismiss()
            } catch {
                isSubmitting = false
                print("[CheckIn] Error: \(error)")
                errorMessage = "\(error)"
                showError = true
            }
        }
    }
}
