import SwiftUI

/// Displays streak shield icons showing remaining and used shields
struct StreakShieldIndicator: View {
    let shieldsRemaining: Int
    let shieldsMax: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<shieldsMax, id: \.self) { index in
                Image(systemName: index < shieldsRemaining ? "shield.fill" : "shield")
                    .font(.caption)
                    .foregroundStyle(index < shieldsRemaining ? .blue : .gray.opacity(0.4))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(shieldsRemaining) of \(shieldsMax) streak shields remaining")
    }
}

#Preview {
    VStack(spacing: 20) {
        StreakShieldIndicator(shieldsRemaining: 3, shieldsMax: 3)
        StreakShieldIndicator(shieldsRemaining: 2, shieldsMax: 3)
        StreakShieldIndicator(shieldsRemaining: 1, shieldsMax: 3)
        StreakShieldIndicator(shieldsRemaining: 0, shieldsMax: 3)
        StreakShieldIndicator(shieldsRemaining: 1, shieldsMax: 1)
        StreakShieldIndicator(shieldsRemaining: 0, shieldsMax: 1)
    }
    .padding()
}
