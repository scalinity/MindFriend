import SwiftUI

struct WatchStatsView: View {
    @StateObject private var viewModel = WatchStatsViewModel()

    var body: some View {
        VStack(spacing: 12) {
            Text("This Week")
                .font(.headline)

            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { index in
                    VStack(spacing: 1) {
                        Text(viewModel.weekMoods[safe: index] ?? "·")
                            .font(.caption)
                        Text(viewModel.dayLabel(index))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Exercises Done")
                    Spacer()
                    Text("\(viewModel.exercisesDone)")
                }

                HStack {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                    Text("Moods Logged")
                    Spacer()
                    Text("\(viewModel.moodsLogged)")
                }
            }
            .font(.caption)
            .padding()
            .background(Color.gray.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Spacer()
        }
        .padding()
        .navigationTitle("Stats")
    }
}

// MARK: - Safe Array Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
