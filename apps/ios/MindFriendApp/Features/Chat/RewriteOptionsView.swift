import SwiftUI

struct RewriteOptionsView: View {
    let originalMessage: String
    let options: [RewriteOption]
    let rewriteType: RewriteType
    let onSelect: (RewriteOption) -> Void
    let onCancel: () -> Void

    @State private var selectedOption: RewriteOption?
    @State private var expandedExplanations: Set<String> = []

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Divider()

                ScrollView {
                    VStack(spacing: SupportTheme.Spacing.m) {
                        originalMessageSection
                        rewriteOptionsSection
                    }
                    .padding()
                }
            }
            .foregroundStyle(SupportTheme.textPrimary)
            .supportScreen()
            .navigationTitle("Rewrite Your Thought")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }

    private var originalMessageSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            Text("Original")
                .font(.caption)
                .foregroundColor(SupportTheme.textSecondary)

            Text(originalMessage)
                .font(.body)
                .foregroundColor(SupportTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .supportCard()
    }

    private var rewriteOptionsSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text(" alternatives")
                .font(.headline)

            ForEach(options) { option in
                RewriteOptionCard(
                    option: option,
                    isSelected: selectedOption?.id == option.id,
                    isExpanded: expandedExplanations.contains(option.id),
                    onTap: {
                        if selectedOption == option {
                            if expandedExplanations.contains(option.id) {
                                expandedExplanations.remove(option.id)
                            } else {
                                expandedExplanations.insert(option.id)
                            }
                        } else {
                            selectedOption = option
                            expandedExplanations.insert(option.id)
                        }
                    },
                    onApply: {
                        onSelect(option)
                    }
                )
            }
        }
    }
}

struct RewriteOptionCard: View {
    let option: RewriteOption
    let isSelected: Bool
    let isExpanded: Bool
    let onTap: () -> Void
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            Button(action: onTap) {
                HStack(alignment: .top, spacing: SupportTheme.Spacing.s) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? SupportTheme.accent : SupportTheme.textSecondary)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                        Text(option.text)
                            .font(.body)
                            .foregroundColor(SupportTheme.textPrimary)
                            .multilineTextAlignment(.leading)

                        if isExpanded {
                            Text(option.explanation)
                                .font(.caption)
                                .foregroundColor(SupportTheme.textSecondary)
                                .padding(.top, SupportTheme.Spacing.xxs)
                        }
                    }

                    Spacer()
                }
                .padding(SupportTheme.Spacing.s)
                .background(isSelected ? SupportTheme.accent.opacity(0.1) : SupportTheme.canvas)
                .cornerRadius(SupportTheme.controlRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                        .stroke(isSelected ? SupportTheme.accent : SupportTheme.border, lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())

            if isSelected {
                HStack {
                    Button(action: onApply) {
                        Text("Apply")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.supportPrimary)
                }
                .padding(.horizontal, SupportTheme.Spacing.xxs)
            }
        }
    }
}

#Preview {
    RewriteOptionsView(
        originalMessage: "I always mess everything up.",
        options: [
            RewriteOption(id: "1", text: "Some things haven't worked out lately.", explanation: "This is more balanced."),
            RewriteOption(id: "2", text: "I want to improve. What can I do differently?", explanation: "This focuses on action."),
            RewriteOption(id: "3", text: "I'm struggling right now, but that doesn't define my worth.", explanation: "This is more compassionate.")
        ],
        rewriteType: .lessCatastrophic,
        onSelect: { _ in },
        onCancel: {}
    )
}
