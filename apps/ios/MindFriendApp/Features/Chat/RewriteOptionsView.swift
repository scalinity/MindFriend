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
                    VStack(spacing: 16) {
                        originalMessageSection
                        rewriteOptionsSection
                    }
                    .padding()
                }
            }
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Original")
                .font(.caption)
                .foregroundColor(.secondary)

            Text(originalMessage)
                .font(.body)
                .foregroundColor(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .cornerRadius(12)
        }
    }

    private var rewriteOptionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
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
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onTap) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .blue : .gray)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(option.text)
                            .font(.body)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)

                        if isExpanded {
                            Text(option.explanation)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                        }
                    }

                    Spacer()
                }
                .padding(12)
                .background(isSelected ? Color.blue.opacity(0.1) : Color(.systemBackground))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())

            if isSelected {
                HStack {
                    Button(action: onApply) {
                        Text("Apply")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                }
                .padding(.horizontal, 4)
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
