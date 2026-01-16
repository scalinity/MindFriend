// ContentTypePickerView.swift
// Smart Personalization: Content type preference picker

import SwiftUI

struct ContentTypePickerView: View {
    @Binding var selectedTypes: Set<PersonalizationContentType>

    var body: some View {
        List {
            ForEach(PersonalizationContentType.allCases, id: \.self) { type in
                Button {
                    withAnimation {
                        if selectedTypes.contains(type) {
                            selectedTypes.remove(type)
                        } else {
                            selectedTypes.insert(type)
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: type.icon)
                            .font(.title3)
                            .foregroundStyle(selectedTypes.contains(type) ? .blue : .secondary)
                            .frame(width: 30)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(type.displayName)
                                .foregroundStyle(.primary)
                            Text(typeDescription(type))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if selectedTypes.contains(type) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                                .fontWeight(.semibold)
                        }
                    }
                }
                .accessibilityAddTraits(selectedTypes.contains(type) ? .isSelected : [])
                .accessibilityLabel("\(type.displayName), \(typeDescription(type))")
            }
        }
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
