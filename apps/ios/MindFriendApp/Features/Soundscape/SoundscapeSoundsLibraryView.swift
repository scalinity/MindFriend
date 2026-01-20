import SwiftUI

/// View for browsing and selecting sounds to add to the mixer
struct SoundscapeSoundsLibraryView: View {
    @EnvironmentObject private var mixerService: SoundscapeMixerService
    @Environment(\.dismiss) private var dismiss

    let onSoundSelected: (SoundscapeSound) -> Void

    @State private var selectedCategory: SoundscapeCategory = .nature
    @State private var searchText: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category tabs
                categoryTabs

                // Sound list
                soundsList
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Add Sound")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search sounds")
        }
    }

    // MARK: - Category Tabs

    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SoundscapeCategory.allCases) { category in
                    CategoryTab(
                        category: category,
                        isSelected: selectedCategory == category,
                        onTap: { selectedCategory = category }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Sounds List

    private var soundsList: some View {
        let sounds = filteredSounds

        return ScrollView {
            if sounds.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(sounds) { sound in
                        SoundRow(
                            sound: sound,
                            onSelect: {
                                onSoundSelected(sound)
                                dismiss()
                            }
                        )
                    }
                }
                .padding(16)
            }
        }
    }

    private var filteredSounds: [SoundscapeSound] {
        var sounds = mixerService.getSounds(for: selectedCategory)

        if !searchText.isEmpty {
            sounds = sounds.filter { sound in
                sound.title.localizedCaseInsensitiveContains(searchText)
            }
        }

        return sounds
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("No sounds found")
                .font(.headline)
                .foregroundStyle(.secondary)

            if !searchText.isEmpty {
                Text("Try a different search term")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Category Tab

private struct CategoryTab: View {
    let category: SoundscapeCategory
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.system(size: 14))

                Text(category.displayName)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor : Color(.secondarySystemGroupedBackground))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sound Row

private struct SoundRow: View {
    let sound: SoundscapeSound
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 48, height: 48)

                    Image(systemName: sound.sfSymbol)
                        .font(.system(size: 20))
                        .foregroundStyle(Color.accentColor)
                }

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(sound.title)
                            .font(.body)
                            .fontWeight(.medium)

                        if sound.isPremium {
                            Image(systemName: "crown.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }

                    Text(sound.category.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Add indicator
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    SoundscapeSoundsLibraryView(onSoundSelected: { _ in })
        .environmentObject(SoundscapeMixerService(supabase: supabase))
}
