import SwiftUI

struct WatchMoodView: View {
    @State private var selectedMood: String?
    @State private var saveError: String?
    @ObservedObject private var connectivity = WatchConnectivityManager.shared

    /// Moods ordered low→high (stressed=1 to great=5) for consistent UX with iOS
    private var moods: [(String, String)] {
        MoodEmojiMapper.moodsLowToHigh.map { ($0.name, $0.emoji) }
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("How are you?")
                .font(.headline)

            if let status = saveError ?? connectivity.actionStatus {
                Text(status).font(.caption2).multilineTextAlignment(.center)
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(moods, id: \.0) { mood, emoji in
                        Button {
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

        do {
            try connectivity.sendMoodToPhone(mood, score: score)
            selectedMood = mood
            saveError = nil
            HapticManager.shared.playSuccess()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
