import SwiftUI

/// Quick check-in sheet for mood, energy, gratitude, and intention logging
struct QuickCheckInSheet: View {
    let type: CheckInType
    let onSave: (QuickCheckInData) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedValue: Int = 3
    @State private var selectedEmoji: String = ""
    @State private var textValue: String = ""
    @State private var selectedTags: Set<String> = []

    private let moodEmojis = ["😢", "😔", "😐", "🙂", "😊"]
    private let contextTags = ["Work", "Family", "Health", "Social", "Personal"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                // Title
                Text(titleForType)
                    .font(.title2)
                    .fontWeight(.semibold)

                // Input based on type
                inputView

                // Optional context tags
                if type == .mood || type == .energy {
                    contextTagsSelector
                }

                Spacer()

                // Save button
                Button {
                    saveCheckIn()
                } label: {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canSave ? Color.blue : Color.gray)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!canSave)
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private var inputView: some View {
        switch type {
        case .mood:
            moodSelector
        case .energy:
            energySelector
        case .gratitude:
            gratitudeInput
        case .intention:
            intentionInput
        case .stressLevel:
            stressSelector
        }
    }

    private var titleForType: String {
        switch type {
        case .mood: return "How are you feeling?"
        case .energy: return "Energy level?"
        case .gratitude: return "One thing you're grateful for"
        case .intention: return "One word for today"
        case .stressLevel: return "Stress level?"
        }
    }

    private var canSave: Bool {
        switch type {
        case .mood: return !selectedEmoji.isEmpty
        case .energy, .stressLevel: return true
        case .gratitude, .intention: return !textValue.isEmpty
        }
    }

    // MARK: - Mood Selector

    private var moodSelector: some View {
        HStack(spacing: 16) {
            ForEach(Array(moodEmojis.enumerated()), id: \.offset) { index, emoji in
                Button {
                    selectedEmoji = emoji
                    selectedValue = index + 1
                } label: {
                    Text(emoji)
                        .font(.system(size: 44))
                        .opacity(selectedEmoji == emoji ? 1 : 0.4)
                        .scaleEffect(selectedEmoji == emoji ? 1.2 : 1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(moodAccessibilityLabel(for: index))
                .accessibilityAddTraits(selectedEmoji == emoji ? .isSelected : [])
            }
        }
        .animation(.spring(response: 0.3), value: selectedEmoji)
    }

    private func moodAccessibilityLabel(for index: Int) -> String {
        switch index {
        case 0: return "Very sad"
        case 1: return "Sad"
        case 2: return "Neutral"
        case 3: return "Happy"
        case 4: return "Very happy"
        default: return ""
        }
    }

    // MARK: - Energy Selector

    private var energySelector: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { value in
                    Button {
                        selectedValue = value
                    } label: {
                        Image(systemName: value <= selectedValue ? "bolt.fill" : "bolt")
                            .font(.title)
                            .foregroundStyle(value <= selectedValue ? .yellow : .gray)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Energy level \(value)")
                    .accessibilityAddTraits(value == selectedValue ? .isSelected : [])
                }
            }

            Text(energyLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var energyLabel: String {
        switch selectedValue {
        case 1: return "Very low"
        case 2: return "Low"
        case 3: return "Moderate"
        case 4: return "Good"
        case 5: return "High"
        default: return ""
        }
    }

    // MARK: - Gratitude Input

    private var gratitudeInput: some View {
        TextField("I'm grateful for...", text: $textValue)
            .textFieldStyle(.roundedBorder)
            .submitLabel(.done)
            .onSubmit {
                if canSave {
                    saveCheckIn()
                }
            }
    }

    // MARK: - Intention Input

    private var intentionInput: some View {
        VStack(spacing: 12) {
            TextField("One word", text: $textValue)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .font(.title2)
                .submitLabel(.done)
                .onSubmit {
                    if canSave {
                        saveCheckIn()
                    }
                }

            Text("e.g., Focus, Patience, Joy, Growth")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Stress Selector

    private var stressSelector: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { value in
                    Button {
                        selectedValue = value
                    } label: {
                        Circle()
                            .fill(stressColor(for: value))
                            .frame(width: 44, height: 44)
                            .opacity(value == selectedValue ? 1 : 0.4)
                            .scaleEffect(value == selectedValue ? 1.2 : 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stress level \(value): \(stressAccessibilityLabel(for: value))")
                    .accessibilityAddTraits(value == selectedValue ? .isSelected : [])
                }
            }

            Text(stressLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .animation(.spring(response: 0.3), value: selectedValue)
    }

    private func stressColor(for value: Int) -> Color {
        switch value {
        case 1: return .green
        case 2: return .mint
        case 3: return .yellow
        case 4: return .orange
        case 5: return .red
        default: return .gray
        }
    }

    private var stressLabel: String {
        switch selectedValue {
        case 1: return "Very calm"
        case 2: return "Calm"
        case 3: return "Moderate"
        case 4: return "Stressed"
        case 5: return "Very stressed"
        default: return ""
        }
    }

    private func stressAccessibilityLabel(for value: Int) -> String {
        switch value {
        case 1: return "Very calm"
        case 2: return "Calm"
        case 3: return "Moderate"
        case 4: return "Stressed"
        case 5: return "Very stressed"
        default: return ""
        }
    }

    // MARK: - Context Tags

    private var contextTagsSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Context (optional)")
                .font(.caption)
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 8) {
                ForEach(contextTags, id: \.self) { tag in
                    Button {
                        if selectedTags.contains(tag) {
                            selectedTags.remove(tag)
                        } else {
                            selectedTags.insert(tag)
                        }
                    } label: {
                        Text(tag)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedTags.contains(tag) ? Color.blue : Color(.secondarySystemBackground))
                            .foregroundStyle(selectedTags.contains(tag) ? .white : .primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedTags.contains(tag) ? .isSelected : [])
                }
            }
        }
    }

    // MARK: - Save

    private func saveCheckIn() {
        let checkIn = QuickCheckInData(
            type: type,
            valueNumeric: (type == .mood || type == .energy || type == .stressLevel) ? selectedValue : nil,
            valueEmoji: selectedEmoji.isEmpty ? nil : selectedEmoji,
            valueText: textValue.isEmpty ? nil : textValue,
            contextTags: Array(selectedTags)
        )
        onSave(checkIn)
        dismiss()
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(
                    x: bounds.minX + result.positions[index].x,
                    y: bounds.minY + result.positions[index].y
                ),
                proposal: .unspecified
            )
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: maxWidth, height: y + rowHeight)
        }
    }
}

// MARK: - Preview

#Preview {
    QuickCheckInSheet(type: .mood) { _ in }
}
