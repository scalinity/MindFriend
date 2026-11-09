import SwiftUI

/// Quick check-in sheet for mood, energy, gratitude, and intention logging
struct QuickCheckInSheet: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            VStack(spacing: SupportTheme.Spacing.xl) {
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
                        .padding(SupportTheme.Spacing.m)
                        .background(canSave ? SupportTheme.accent : SupportTheme.textSecondary)
                        .foregroundStyle(SupportTheme.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                }
                .disabled(!canSave)
            }
            .padding(SupportTheme.Spacing.m)
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
        HStack(spacing: SupportTheme.Spacing.m) {
            ForEach(Array(moodEmojis.enumerated()), id: \.offset) { index, emoji in
                Button {
                    selectedEmoji = emoji
                    selectedValue = index + 1
                } label: {
                    Text(emoji)
                        .font(.system(.largeTitle))
                        .opacity(selectedEmoji == emoji ? 1 : 0.4)
                        .scaleEffect(reduceMotion ? 1 : (selectedEmoji == emoji ? 1.2 : 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(moodAccessibilityLabel(for: index))
                .accessibilityAddTraits(selectedEmoji == emoji ? .isSelected : [])
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.3), value: selectedEmoji)
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
        VStack(spacing: SupportTheme.Spacing.m) {
            HStack(spacing: SupportTheme.Spacing.xs) {
                ForEach(1...5, id: \.self) { value in
                    Button {
                        selectedValue = value
                    } label: {
                        Image(systemName: value <= selectedValue ? "bolt.fill" : "bolt")
                            .font(.title)
                            .foregroundStyle(value <= selectedValue ? .yellow : SupportTheme.textSecondary)
                            .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Energy level \(value)")
                    .accessibilityAddTraits(value == selectedValue ? .isSelected : [])
                }
            }

            Text(energyLabel)
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
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
            .supportField()
            .submitLabel(.done)
            .onSubmit {
                if canSave {
                    saveCheckIn()
                }
            }
    }

    // MARK: - Intention Input

    private var intentionInput: some View {
        VStack(spacing: SupportTheme.Spacing.s) {
            TextField("One word", text: $textValue)
                .supportField()
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
                .foregroundStyle(SupportTheme.textSecondary)
        }
    }

    // MARK: - Stress Selector

    private var stressSelector: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            HStack(spacing: SupportTheme.Spacing.xs) {
                ForEach(1...5, id: \.self) { value in
                    Button {
                        selectedValue = value
                    } label: {
                        Circle()
                            .fill(stressColor(for: value))
                            .frame(width: 44, height: 44)
                            .opacity(value == selectedValue ? 1 : 0.4)
                            .scaleEffect(reduceMotion ? 1 : (value == selectedValue ? 1.2 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stress level \(value): \(stressAccessibilityLabel(for: value))")
                    .accessibilityAddTraits(value == selectedValue ? .isSelected : [])
                }
            }

            Text(stressLabel)
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.3), value: selectedValue)
    }

    private func stressColor(for value: Int) -> Color {
        switch value {
        case 1: return SupportTheme.accent
        case 2: return SupportTheme.accent
        case 3: return SupportTheme.accent
        case 4: return SupportTheme.accent
        case 5: return .red
        default: return SupportTheme.accent
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
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            Text("Context (optional)")
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)

            FlowLayout(spacing: SupportTheme.Spacing.xs) {
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
                            .padding(.horizontal, SupportTheme.Spacing.s)
                            .padding(.vertical, SupportTheme.Spacing.xxs)
                            .background(selectedTags.contains(tag) ? SupportTheme.accent : SupportTheme.surface)
                            .foregroundStyle(selectedTags.contains(tag) ? SupportTheme.onAccent : SupportTheme.textPrimary)
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

// MARK: - Preview

#Preview {
    QuickCheckInSheet(type: .mood) { _ in }
}
