import SwiftUI

struct WatchBreathingView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = WatchBreathingViewModel()

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                // Outer breathing ring
                Circle()
                    .stroke(viewModel.phaseColor.opacity(0.3), lineWidth: 8)
                    .frame(width: 120, height: 120)

                // Animated breathing circle
                Circle()
                    .fill(viewModel.phaseColor.opacity(0.4))
                    .frame(width: viewModel.circleSize, height: viewModel.circleSize)
                    .animation(.easeInOut(duration: viewModel.currentPhaseDuration), value: viewModel.circleSize)

                VStack(spacing: 4) {
                    Text(viewModel.instruction)
                        .font(.headline)
                        .multilineTextAlignment(.center)

                    Text("\(viewModel.secondsRemaining)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()

                    if viewModel.isActive {
                        Text("Cycle \(viewModel.currentCycle)/\(viewModel.totalCycles)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !viewModel.isActive && !viewModel.isComplete {
                Button("Start") {
                    viewModel.startBreathing()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            } else if viewModel.isComplete {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.green)

                    Text("Great job!")
                        .font(.headline)

                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Button("Stop") {
                    viewModel.stop()
                    dismiss()
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding()
        .navigationTitle("4-7-8 Breathe")
        .onDisappear {
            viewModel.stop()
        }
    }
}
