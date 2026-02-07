import SwiftUI

/// View for managing manual difficulty overrides
struct DifficultySettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var difficultyService: DifficultyService
    @State private var selectedOverride: CapacityOverride.OverrideLevel?
    @State private var isApplying = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationView {
            List {
                Section {
                    // Current capacity display
                    if let capacity = difficultyService.currentCapacity {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Current Capacity")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text(capacity.level.displayName)
                                    .font(.headline)
                                    .foregroundColor(capacity.level.color)
                            }

                            Spacer()

                            ZStack {
                                Circle()
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 3)
                                    .frame(width: 36, height: 36)

                                Circle()
                                    .trim(from: 0, to: CGFloat(capacity.score) / 100)
                                    .stroke(capacity.level.color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                    .frame(width: 36, height: 36)
                                    .rotationEffect(.degrees(-90))

                                Text("\(capacity.score)")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(capacity.level.color)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Automatic Calculation")
                }

                Section {
                    ForEach([
                        CapacityOverride.OverrideLevel.rest,
                        CapacityOverride.OverrideLevel.normal,
                        CapacityOverride.OverrideLevel.challenge
                    ], id: \.self) { level in
                        Button {
                            selectedOverride = level
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: level.icon)
                                    .font(.title3)
                                    .foregroundColor(iconColor(for: level))
                                    .frame(width: 32)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(level.displayName)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)

                                    Text(description(for: level))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if isActiveOverride(level) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Manual Override")
                } footer: {
                    if difficultyService.activeOverride != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 4) {
                                Image(systemName: "info.circle.fill")
                                    .font(.caption2)
                                Text("Override active until midnight")
                                    .font(.caption)
                            }
                            .foregroundColor(.orange)

                            Button("Clear Override") {
                                Task {
                                    isApplying = true
                                    defer { isApplying = false }

                                    do {
                                        try await difficultyService.clearOverride()
                                        selectedOverride = nil
                                    } catch {
                                        errorMessage = error.localizedDescription
                                        showError = true
                                    }
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.red)
                        }
                    } else {
                        Text("Manually adjust today's difficulty level. Resets at midnight.")
                            .font(.caption)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        DifficultyInfoRow(
                            icon: "leaf.fill",
                            title: "Rest Mode",
                            description: "Shorter, gentler activities",
                            color: .blue
                        )

                        DifficultyInfoRow(
                            icon: "circle.grid.2x2.fill",
                            title: "Normal Mode",
                            description: "Standard difficulty and duration",
                            color: .green
                        )

                        DifficultyInfoRow(
                            icon: "flame.fill",
                            title: "Challenge Mode",
                            description: "Longer, more intensive activities",
                            color: .orange
                        )
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("About Difficulty Levels")
                }
            }
            .navigationTitle("Difficulty Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isApplying {
                        ProgressView()
                    } else {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
            .onChange(of: selectedOverride) {
                if let level = selectedOverride {
                    applyOverride(level)
                }
            }
        }
    }

    private func applyOverride(_ level: CapacityOverride.OverrideLevel) {
        Task {
            isApplying = true
            defer { isApplying = false }

            do {
                try await difficultyService.setManualOverride(level)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                selectedOverride = nil
            }
        }
    }

    private func isActiveOverride(_ level: CapacityOverride.OverrideLevel) -> Bool {
        guard let override = difficultyService.activeOverride else {
            return false
        }
        return override.overrideLevel == level && override.isCurrentlyActive
    }

    private func iconColor(for level: CapacityOverride.OverrideLevel) -> Color {
        switch level {
        case .rest:
            return .blue
        case .normal:
            return .green
        case .challenge:
            return .orange
        }
    }

    private func description(for level: CapacityOverride.OverrideLevel) -> String {
        switch level {
        case .rest:
            return "Take it easy today"
        case .normal:
            return "Standard pace"
        case .challenge:
            return "Push yourself today"
        }
    }
}

struct DifficultyInfoRow: View {
    let icon: String
    let title: String
    let description: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    DifficultySettingsView()
        .environmentObject({
            let service = DifficultyService(supabase: supabase)
            return service
        }())
}
