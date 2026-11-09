import SwiftUI

/// Sheet for selecting background sounds during meditation/sleep content
struct BackgroundSoundsSheet: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var selectedSound: BackgroundSoundType?
    @Binding var volume: Float
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: SupportTheme.Spacing.l) {
                // Sound selection grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: dynamicTypeSize.isAccessibilitySize ? 1 : 3), spacing: SupportTheme.Spacing.m) {
                    ForEach(BackgroundSoundType.availableSounds) { sound in
                        soundButton(for: sound)
                    }
                }
                .padding(.horizontal, SupportTheme.Spacing.m)

                // Note if only silence is available (no audio files bundled)
                if BackgroundSoundType.availableSounds.count == 1 {
                    Text("Background sound files not yet installed")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                        .padding(.top, SupportTheme.Spacing.xs)
                }

                // Volume slider (only if sound selected)
                if selectedSound != nil && selectedSound != .silence {
                    VStack(spacing: SupportTheme.Spacing.xs) {
                        HStack {
                            Image(systemName: "speaker.wave.1")
                                .foregroundStyle(SupportTheme.textSecondary)

                            Slider(value: Binding(
                                get: { Double(volume) },
                                set: { volume = Float($0) }
                            ), in: 0...1)

                            Image(systemName: "speaker.wave.3")
                                .foregroundStyle(SupportTheme.textSecondary)
                        }

                        Text("\(Int(volume * 100))%")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                    .padding(.horizontal, SupportTheme.Spacing.m)
                }

                Spacer()
            }
            .padding(.top, SupportTheme.Spacing.m)
            .supportScreen()
            .navigationTitle("Background Sounds")
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

    private func soundButton(for sound: BackgroundSoundType) -> some View {
        Button {
            if sound == .silence {
                selectedSound = nil
            } else {
                selectedSound = sound
            }
        } label: {
            VStack(spacing: SupportTheme.Spacing.xs) {
                ZStack {
                    RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                        .fill(isSelected(sound) ? SupportTheme.accent.opacity(0.2) : SupportTheme.surface)
                        .frame(width: 64, height: 64)

                    Image(systemName: sound.icon)
                        .font(.title2)
                        .foregroundStyle(isSelected(sound) ? .blue : SupportTheme.textPrimary)
                }

                Text(sound.displayName)
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.plain)
    }

    private func isSelected(_ sound: BackgroundSoundType) -> Bool {
        if sound == .silence {
            return selectedSound == nil
        }
        return selectedSound == sound
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    BackgroundSoundsSheet(
        selectedSound: .constant(.rain),
        volume: .constant(0.3)
    )
}
#endif
