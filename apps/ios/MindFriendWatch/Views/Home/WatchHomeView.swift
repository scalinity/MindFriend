import SwiftUI

struct WatchHomeView: View {
    @StateObject private var viewModel = WatchHomeViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Streak Badge
                VStack(spacing: 4) {
                    HStack {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.orange)
                        Text("\(viewModel.streak)")
                            .font(.headline)
                    }
                    Text("Day Streak")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Quick Actions
                HStack(spacing: 8) {
                    Button {
                        viewModel.showBreathing = true
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "wind")
                                .font(.title3)
                            Text("Breathe")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    Button {
                        viewModel.showFocus = true
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "circle.dotted")
                                .font(.title3)
                            Text("Focus")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                // Today's Progress
                VStack(spacing: 6) {
                    HStack {
                        Text("Today")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(viewModel.completedToday)/\(viewModel.dailyGoal)")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }

                    let progress = viewModel.dailyGoal > 0 ? Double(viewModel.completedToday) / Double(viewModel.dailyGoal) : 0
                    ProgressView(value: min(progress, 1.0))
                        .tint(.green)
                }
                .padding()
                .background(Color.gray.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding()
        }
        .navigationTitle("MindFriend")
        .sheet(isPresented: $viewModel.showBreathing) {
            WatchBreathingView()
        }
        .sheet(isPresented: $viewModel.showFocus) {
            WatchFocusView()
        }
    }
}
