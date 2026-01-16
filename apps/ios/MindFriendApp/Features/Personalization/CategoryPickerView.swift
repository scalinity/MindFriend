// CategoryPickerView.swift
// Smart Personalization: Category preference picker

import SwiftUI

struct CategoryPickerView: View {
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
                        withAnimation {
                            if selectedCategories.contains(category.name) {
                                selectedCategories.remove(category.name)
                            } else {
                                selectedCategories.insert(category.name)
                            }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: category.icon)
                                .font(.body)
                                .foregroundStyle(selectedCategories.contains(category.name) ? .blue : .secondary)
                                .frame(width: 24)

                            Text(category.name)
                                .foregroundStyle(.primary)

                            Spacer()

                            if selectedCategories.contains(category.name) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
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
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !selectedCategories.isEmpty {
                    Button("Clear All") {
                        withAnimation {
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
