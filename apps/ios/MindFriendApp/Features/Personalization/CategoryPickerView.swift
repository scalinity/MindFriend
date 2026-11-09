// CategoryPickerView.swift
// Smart Personalization: Category preference picker

import SwiftUI

struct CategoryPickerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selectedCategories: Set<String>

    private let availableCategories: [(name: String, icon: String)] = [
        ("Meditation", "figure.mind.and.body"),
        ("Breathing", "wind"),
        ("Grounding", "leaf.fill"),
        ("Journaling", "book.fill"),
        ("Movement", "figure.walk"),
        ("Sleep", "moon.fill"),
        ("Focus", "target"),
        ("Stress Relief", "heart.fill"),
        ("Gratitude", "heart.text.square.fill"),
        ("Mindfulness", "brain.head.profile"),
        ("Relaxation", "cup.and.saucer.fill"),
        ("Energy", "bolt.fill"),
        ("Self-Compassion", "hands.clap.fill"),
        ("Anxiety Relief", "sparkles")
    ]

    var body: some View {
        List {
            Section {
                ForEach(availableCategories, id: \.name) { category in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if selectedCategories.contains(category.name) {
                                selectedCategories.remove(category.name)
                            } else {
                                selectedCategories.insert(category.name)
                            }
                        }
                    } label: {
                        HStack(spacing: SupportTheme.Spacing.s) {
                            Image(systemName: category.icon)
                                .font(.body)
                                .foregroundStyle(selectedCategories.contains(category.name) ? .blue : SupportTheme.textSecondary)
                                .frame(width: 24)

                            Text(category.name)
                                .foregroundStyle(SupportTheme.textPrimary)

                            Spacer()

                            if selectedCategories.contains(category.name) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(SupportTheme.accent)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    .accessibilityAddTraits(selectedCategories.contains(category.name) ? .isSelected : [])
                    .accessibilityLabel(category.name)
                }
            } footer: {
                Text("Select categories that interest you most. We'll prioritize content from these areas.")
            }
        }
        .supportScreen()
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !selectedCategories.isEmpty {
                    Button("Clear All") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedCategories.removeAll()
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        CategoryPickerView(selectedCategories: .constant(["Meditation", "Sleep"]))
    }
}
