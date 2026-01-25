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
            VStack(alignment: .leading, spacing: 24) {
                themeSection
                checkInSection
                journalSection
                affirmationSection
                submitButton
            }
            .padding()
        }
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
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(10)
                    .shadow(radius: 10)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Unknown error occurred")
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
        .onChange(of: journalEntry) { newValue in
            // ✅ Save encrypted journal draft via service layer (proper encapsulation)
            do {
                try container.transitionService.saveJournalDraft(newValue, for: userPathway.id)
            } catch {
                // ✅ SECURITY FIX: Don't log error details (may contain PHI)
                print("⚠️ Failed to save journal draft for pathway \(userPathway.id.uuidString)")
            }
        }
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(content.theme.title)
                .font(.title2.weight(.bold))
            Text(content.theme.message)
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var checkInSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Daily Check-In")
                .font(.headline)

            Text(content.checkInPrompt)
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 12) {
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
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    @ViewBuilder
    private var journalSection: some View {
        if let journalPrompt = content.journalPrompt {
            VStack(alignment: .leading, spacing: 12) {
                Text("Journal Prompt")
                    .font(.headline)
                Text(journalPrompt)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextEditor(text: $journalEntry)
                    .frame(minHeight: 120)
                    .padding(4)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }

    private var affirmationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today's Affirmation")
                .font(.headline)
            Text(content.affirmation)
                .font(.body.italic())
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }

    private var submitButton: some View {
        Button(action: { submitCheckIn() }) {
            Text(isSubmitting ? "Submitting..." : "Complete Check-In")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
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
                _ = try await container.transitionService.completeCheckIn(
                    userPathwayId: userPathway.id,
                    checkInData: checkInData,
                    journalEntry: journalEntry.isEmpty ? nil : journalEntry
                )
                // ✅ Clear encrypted draft on success via service layer
                container.transitionService.clearJournalDraft(for: userPathway.id)
                isSubmitting = false
                dismiss()
            } catch {
                isSubmitting = false
                errorMessage = "Failed to save your check-in. Please try again."
                showError = true
            }
        }
    }
}
