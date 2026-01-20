import SwiftUI

/// Card component for controlling a single sound layer in the mixer
struct SoundscapeLayerCard: View {
    let layer: SoundLayerState
    let onVolumeChange: (Float) -> Void
    let onRemove: () -> Void

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Main card content
            HStack(spacing: 12) {
                // Sound icon
                ZStack {
                    Circle()
                        .fill(layer.isLoaded ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.2))
                        .frame(width: 44, height: 44)

                    if layer.isLoaded {
                        Image(systemName: layer.sound.sfSymbol)
                            .font(.system(size: 20))
                            .foregroundStyle(Color.accentColor)
                    } else {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }

                // Sound info
                VStack(alignment: .leading, spacing: 2) {
                    Text(layer.sound.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Text(layer.sound.category.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Volume indicator
                VStack(spacing: 2) {
                    Text("\(layer.volumePercentage)%")
                        .font(.caption)
                        .fontWeight(.medium)
                        .monospacedDigit()

                    // Mini volume bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.secondary.opacity(0.2))

                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: geo.size.width * CGFloat(layer.volume))
                        }
                    }
                    .frame(width: 40, height: 4)
                }
                .frame(width: 50)

                // Expand/collapse button
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Expanded controls
            if isExpanded {
                Divider()
                    .padding(.horizontal, 16)

                VStack(spacing: 16) {
                    // Volume slider
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Volume")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text("\(layer.volumePercentage)%")
                                .font(.caption)
                                .fontWeight(.medium)
                                .monospacedDigit()
                        }

                        Slider(
                            value: Binding(
                                get: { Double(layer.volume) },
                                set: { onVolumeChange(Float($0)) }
                            ),
                            in: 0...1
                        )
                        .tint(.accentColor)
                    }

                    // Remove button
                    Button(role: .destructive) {
                        onRemove()
                    } label: {
                        HStack {
                            Image(systemName: "minus.circle")
                            Text("Remove from Mix")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.red)
                    }
                }
                .padding(16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Error state
            if let error = layer.loadError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Empty slot card for adding a new layer
struct EmptyLayerSlot: View {
    let slotNumber: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [4]))
                        .frame(width: 44, height: 44)

                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Add Sound")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    Text("Layer \(slotNumber)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [6]))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("Layer Card") {
    let sampleSound = SoundscapeSound(
        id: "1",
        title: "Rain",
        category: .nature,
        audioUrl: "https://example.com/rain.m4a",
        thumbnailUrl: nil,
        iconName: "cloud.rain.fill",
        isPremium: false,
        durationSeconds: nil,
        sortOrder: 1,
        createdAt: Date()
    )

    let layer = SoundLayerState(
        sound: sampleSound,
        volume: 0.75,
        pan: 0.0
    )

    VStack(spacing: 16) {
        SoundscapeLayerCard(
            layer: SoundLayerState(
                id: layer.id,
                sound: layer.sound,
                volume: layer.volume,
                pan: layer.pan,
                isLoaded: true,
                isPlaying: true,
                loadError: nil
            ),
            onVolumeChange: { _ in },
            onRemove: {}
        )

        EmptyLayerSlot(slotNumber: 2, onTap: {})
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
