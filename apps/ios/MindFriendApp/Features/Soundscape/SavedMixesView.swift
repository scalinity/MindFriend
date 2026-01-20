import SwiftUI

/// View for displaying user's saved soundscape mixes
struct SavedMixesView: View {
    @EnvironmentObject private var mixerService: SoundscapeMixerService
    @Environment(\.dismiss) private var dismiss

    @State private var isLoading = false
    @State private var showDeleteConfirmation = false
    @State private var mixToDelete: SavedMix?

    var body: some View {
        NavigationStack {
            Group {
                if mixerService.savedMixes.isEmpty {
                    emptyState
                } else {
                    mixesList
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Saved Mixes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadMixes()
            }
            .confirmationDialog(
                "Delete Mix",
                isPresented: $showDeleteConfirmation,
                presenting: mixToDelete
            ) { mix in
                Button("Delete \"\(mix.name)\"", role: .destructive) {
                    Task {
                        await deleteMix(mix)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { mix in
                Text("Are you sure you want to delete \"\(mix.name)\"? This action cannot be undone.")
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)

            VStack(spacing: 8) {
                Text("No Saved Mixes")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Create a mix in the mixer and tap \"Save\" to save it here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Mixes List

    private var mixesList: some View {
        List {
            ForEach(mixerService.savedMixes) { mix in
                SavedMixRow(mix: mix) {
                    await loadMix(mix)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        mixToDelete = mix
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Actions

    private func loadMixes() async {
        isLoading = true
        do {
            try await mixerService.fetchSavedMixes()
        } catch {
            Log.media.error("Failed to load saved mixes", error: error)
        }
        isLoading = false
    }

    private func loadMix(_ mix: SavedMix) async {
        do {
            try await mixerService.loadMix(mix)
            dismiss()
        } catch {
            Log.media.error("Failed to load mix", error: error)
        }
    }

    private func deleteMix(_ mix: SavedMix) async {
        do {
            try await mixerService.deleteMix(id: mix.id)
        } catch {
            Log.media.error("Failed to delete mix", error: error)
        }
    }
}

// MARK: - Saved Mix Row

private struct SavedMixRow: View {
    let mix: SavedMix
    let onLoad: () async -> Void

    @State private var isLoading = false

    var body: some View {
        Button {
            isLoading = true
            Task {
                await onLoad()
                isLoading = false
            }
        } label: {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 48, height: 48)

                    if isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.accentColor)
                    }
                }

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(mix.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    HStack(spacing: 8) {
                        Label("\(mix.soundCount) sounds", systemImage: "waveform")

                        Text("•")

                        Text(mix.formattedDate)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

// MARK: - Preview

#Preview {
    SavedMixesView()
        .environmentObject(SoundscapeMixerService(supabase: supabase))
}
