import SwiftUI

struct WatchMoodView: View {
    @State private var selectedMood: String?

    /// Moods ordered low→high (stressed=1 to great=5) for consistent UX with iOS
    private var moods: [(String, String)] {
        MoodEmojiMapper.moodsLowToHigh.map { ($0.name, $0.emoji) }
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("How are you?")
                .font(.headline)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(moods, id: \.0) { mood, emoji in
                        Button {
                            selectedMood = mood
                            saveMood(mood)
                        } label: {
                            HStack {
                                Text(emoji)
                                    .font(.title)
                                Text(mood.capitalized)
                                    .font(.body)
                                Spacer()
                                if selectedMood == mood {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(selectedMood == mood ? Color.blue.opacity(0.2) : Color.gray.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
        .padding()
        .navigationTitle("Mood")
    }

    private func saveMood(_ mood: String) {
        let score = MoodEmojiMapper.score(for: mood)

        // Update mood history for stats (thread-safe)
        MoodHistoryManager.addMoodEntry(mood)

        // Sync mood to iOS app (this also stores locally via storeMoodLocally)
        WatchConnectivityManager.shared.sendMoodToPhone(mood, score: score)

        // Haptic confirmation
        HapticManager.shared.playSuccess()
    }
}
