import SwiftUI

/// View for selecting sleep timer duration with fade-out
struct SleepTimerView: View {
    @Binding var selectedMinutes: Int?
    @Environment(\.dismiss) private var dismiss
    
    /// Available timer presets in minutes
    private let presets: [Int?] = [nil, 15, 30, 45, 60, 90]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Audio will fade out gently over the last 30 seconds")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // Timer options
                VStack(spacing: 12) {
                    ForEach(presets, id: \.self) { minutes in
                        timerOption(for: minutes)
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding(.top)
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
                    .foregroundStyle(isSelected(minutes) ? .blue : .secondary)
                
                Text(displayText(for: minutes))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                if isSelected(minutes) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                }
            }
            .padding()
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
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
    SleepTimerView(selectedMinutes: .constant(30))
}
#endif