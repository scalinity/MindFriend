import SwiftUI

/// Sheet for selecting background sounds during meditation/sleep content
struct BackgroundSoundsSheet: View {
    @Binding var selectedSound: BackgroundSoundType?
    @Binding var volume: Float
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Sound selection grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    ForEach(BackgroundSoundType.availableSounds) { sound in
                        soundButton(for: sound)
                    }
                }
                .padding(.horizontal)

                // Note if only silence is available (no audio files bundled)
                if BackgroundSoundType.availableSounds.count == 1 {
                    Text("Background sound files not yet installed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                
                // Volume slider (only if sound selected)
                if selectedSound != nil && selectedSound != .silence {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "speaker.wave.1")
                                .foregroundStyle(.secondary)
                            
                            Slider(value: Binding(
                                get: { Double(volume) },
                                set: { volume = Float($0) }
                            ), in: 0...1)
                            
                            Image(systemName: "speaker.wave.3")
                                .foregroundStyle(.secondary)
                        }
                        
                        Text("\(Int(volume * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
            }
            .padding(.top)
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
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected(sound) ? Color.blue.opacity(0.2) : Color(uiColor: .secondarySystemBackground))
                        .frame(width: 64, height: 64)
                    
                    Image(systemName: sound.icon)
                        .font(.title2)
                        .foregroundStyle(isSelected(sound) ? .blue : .primary)
                }
                
                Text(sound.displayName)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
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