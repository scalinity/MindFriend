import SwiftUI

struct MoodCheckInView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) var dismiss

    var existingMood: MoodEntry?

    @State private var moodScore: Double = 3
    @State private var anxietyScore: Double = 3
    @State private var energyScore: Double = 3
    @State private var note: String = ""
    @State private var showAdvanced = false
    @State private var isSaving = false

    private let moodEmojis = ["😢", "😔", "😐", "🙂", "😊"]
    private let anxietyLabels = ["Very Low", "Low", "Moderate", "High", "Very High"]
    private let energyLabels = ["Exhausted", "Tired", "Okay", "Energetic", "Very High"]

    init(existingMood: MoodEntry? = nil) {
        self.existingMood = existingMood
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Mood slider with emoji
                    VStack(spacing: 16) {
                        Text("How are you feeling?")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text(moodEmojis[Int(moodScore) - 1])
                            .font(.system(size: 80))

                        MoodSlider(value: $moodScore, labels: moodEmojis)
                    }

                    // Advanced options toggle
                    Button {
                        withAnimation {
                            showAdvanced.toggle()
                        }
                    } label: {
                        HStack {
                            Text("More details")
                            Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }

                    if showAdvanced {
                        VStack(spacing: 24) {
                            // Anxiety
                            VStack(spacing: 8) {
                                HStack {
                                    Text("Anxiety Level")
                                        .font(.headline)
                                    Spacer()
                                    Text(anxietyLabels[Int(anxietyScore) - 1])
                                        .foregroundStyle(.secondary)
                                }
                                Slider(value: $anxietyScore, in: 1...5, step: 1)
                            }

                            // Energy
                            VStack(spacing: 8) {
                                HStack {
                                    Text("Energy Level")
                                        .font(.headline)
                                    Spacer()
                                    Text(energyLabels[Int(energyScore) - 1])
                                        .foregroundStyle(.secondary)
                                }
                                Slider(value: $energyScore, in: 1...5, step: 1)
                            }

                            // Note
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Notes (optional)")
                                    .font(.headline)

                                TextField("What's on your mind?", text: $note, axis: .vertical)
                                    .textFieldStyle(.roundedBorder)
                                    .lineLimit(3...6)
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Spacer(minLength: 32)

                    // Save button
                    Button {
                        saveMood()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Save Mood")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                    .disabled(isSaving)
                }
                .padding()
            }
            .navigationTitle("Mood Check-In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let mood = existingMood {
                    moodScore = Double(mood.moodScore)
                    if let anxiety = mood.anxietyScore {
                        anxietyScore = Double(anxiety)
                        showAdvanced = true
                    }
                    if let energy = mood.energyScore {
                        energyScore = Double(energy)
                        showAdvanced = true
                    }
                    if let existingNote = mood.note {
                        note = existingNote
                        showAdvanced = true
                    }
                }
            }
        }
    }

    private func saveMood() {
        isSaving = true

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let localDate = formatter.string(from: Date())

        let mood = MoodEntry(
            id: existingMood?.id ?? UUID().uuidString,
            localDate: localDate,
            moodScore: Int(moodScore),
            anxietyScore: showAdvanced ? Int(anxietyScore) : nil,
            energyScore: showAdvanced ? Int(energyScore) : nil,
            note: showAdvanced && !note.isEmpty ? note : nil,
            source: .manual,
            createdAt: Date()
        )

        Task {
            do {
                let savedMood = try await container.moodService.createMood(mood)
                await MainActor.run {
                    appState.todayMood = savedMood
                    dismiss()
                }
            } catch {
                appState.showError(.apiError(error.localizedDescription))
            }
            isSaving = false
        }
    }
}

struct MoodSlider: View {
    @Binding var value: Double
    let labels: [String]

    var body: some View {
        VStack(spacing: 8) {
            Slider(value: $value, in: 1...5, step: 1)
                .tint(Color.accentColor)

            HStack {
                ForEach(0..<labels.count, id: \.self) { index in
                    Text(labels[index])
                        .font(.title3)
                        .frame(maxWidth: .infinity)
                        .opacity(Int(value) == index + 1 ? 1 : 0.3)
                }
            }
        }
        .padding(.horizontal)
    }
}

#Preview {
    MoodCheckInView()
        .environmentObject(AppState())
        .environmentObject(DependencyContainer())
}
