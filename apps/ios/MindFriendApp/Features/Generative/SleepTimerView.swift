import SwiftUI

/// View for selecting sleep timer duration for the current playback mode
struct SleepTimerView: View {
    @Binding var selectedMinutes: Int?
    let usesBuiltInVoice: Bool
    @Environment(\.dismiss) private var dismiss

    /// Available timer presets in minutes
    private let presets: [Int?] = [nil, 15, 30, 45, 60, 90]

    var body: some View {
        NavigationStack {
            VStack(spacing: SupportTheme.Spacing.l) {
                Text(usesBuiltInVoice
                     ? "Built-in voice will pause when the timer ends"
                     : "Audio will fade out gently over the last 30 seconds")
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SupportTheme.Spacing.m)

                // Timer options
                VStack(spacing: SupportTheme.Spacing.s) {
                    ForEach(presets, id: \.self) { minutes in
                        timerOption(for: minutes)
                    }
                }
                .padding(.horizontal, SupportTheme.Spacing.m)

                Spacer()
            }
            .padding(.top, SupportTheme.Spacing.m)
            .supportScreen()
            .navigationTitle("Sleep Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func timerOption(for minutes: Int?) -> some View {
        Button {
            selectedMinutes = minutes
            dismiss()
        } label: {
            HStack {
                Image(systemName: minutes == nil ? "timer.slash" : "timer")
                    .foregroundStyle(isSelected(minutes) ? .blue : SupportTheme.textSecondary)

                Text(displayText(for: minutes))
                    .foregroundStyle(SupportTheme.textPrimary)

                Spacer()

                if isSelected(minutes) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(SupportTheme.accent)
                }
            }
            .supportCard()
        }
        .buttonStyle(.plain)
    }

    private func displayText(for minutes: Int?) -> String {
        guard let minutes = minutes else {
            return "Off"
        }
        if minutes >= 60 {
            let hours = minutes / 60
            let remaining = minutes % 60
            if remaining == 0 {
                return "\(hours) hour\(hours > 1 ? "s" : "")"
            }
            return "\(hours)h \(remaining)m"
        }
        return "\(minutes) minutes"
    }

    private func isSelected(_ minutes: Int?) -> Bool {
        selectedMinutes == minutes
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    SleepTimerView(selectedMinutes: .constant(30), usesBuiltInVoice: false)
}
#endif
