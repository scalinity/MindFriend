// ContentTypePickerView.swift
// Smart Personalization: Content type preference picker

import SwiftUI

struct ContentTypePickerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selectedTypes: Set<PersonalizationContentType>

    var body: some View {
        List {
            ForEach(PersonalizationContentType.allCases, id: \.self) { type in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if selectedTypes.contains(type) {
                            selectedTypes.remove(type)
                        } else {
                            selectedTypes.insert(type)
                        }
                    }
                } label: {
                    HStack(spacing: SupportTheme.Spacing.s) {
                        Image(systemName: type.icon)
                            .font(.title3)
                            .foregroundStyle(selectedTypes.contains(type) ? .blue : SupportTheme.textSecondary)
                            .frame(width: 30)

                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                            Text(type.displayName)
                                .foregroundStyle(SupportTheme.textPrimary)
                            Text(typeDescription(type))
                                .font(.caption)
                                .foregroundStyle(SupportTheme.textSecondary)
                        }

                        Spacer()

                        if selectedTypes.contains(type) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(SupportTheme.accent)
                                .fontWeight(.semibold)
                        }
                    }
                }
                .accessibilityAddTraits(selectedTypes.contains(type) ? .isSelected : [])
                .accessibilityLabel("\(type.displayName), \(typeDescription(type))")
            }
        }
        .supportScreen()
        .navigationTitle("Content Types")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func typeDescription(_ type: PersonalizationContentType) -> String {
        switch type {
        case .audio: return "Guided sessions, music, soundscapes"
        case .visual: return "Videos, animations, imagery"
        case .text: return "Articles, prompts, journaling"
        case .interactive: return "Games, exercises, quizzes"
        }
    }
}

#Preview {
    NavigationStack {
        ContentTypePickerView(selectedTypes: .constant([.audio, .visual]))
    }
}
