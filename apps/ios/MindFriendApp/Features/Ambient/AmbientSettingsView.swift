// MARK: - Ambient Settings View
// User interface for configuring ambient themes and background preferences

import SwiftUI

/// Settings screen for configuring ambient themes, background types, and auto-adjust.
struct AmbientSettingsView: View {
    // MARK: - Environment

    @EnvironmentObject private var ambientService: AmbientThemeService
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var showError = false
    @State private var errorMessage = ""

    // MARK: - Body

    var body: some View {
        Form {
            // Preview Section
            previewSection

            // Auto-Adjust Toggle
            autoAdjustSection

            // Theme Selection
            themeSection

            // Background Type
            backgroundTypeSection

            // Accessibility Info
            accessibilitySection
        }
        .navigationTitle("Ambient Themes")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Preview Section

    @ViewBuilder
    private var previewSection: some View {
        Section {
            DynamicBackgroundView(
                theme: ambientService.currentTheme,
                backgroundType: ambientService.backgroundType
            )
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
        } header: {
            Text("Preview")
        }
    }

    // MARK: - Auto-Adjust Section

    @ViewBuilder
    private var autoAdjustSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { ambientService.isAutoAdjustEnabled },
                set: { ambientService.setAutoAdjust($0) }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Auto-Adjust by Time")
                        .font(.body)
                    Text("Automatically switch between dawn, day, dusk, and night themes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Theme Section

    @ViewBuilder
    private var themeSection: some View {
        Section {
            // Time-based themes
            VStack(alignment: .leading, spacing: 12) {
                Text("Time-Based Themes")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(AmbientTheme.timeBasedThemes) { theme in
                        ThemePreviewTile(
                            theme: theme,
                            isSelected: isThemeSelected(theme),
                            showAutoBadge: ambientService.isAutoAdjustEnabled,
                            onTap: { selectTheme(theme) }
                        )
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))

            // Manual themes
            VStack(alignment: .leading, spacing: 12) {
                Text("Manual Themes")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(AmbientTheme.manualThemes) { theme in
                        ThemePreviewTile(
                            theme: theme,
                            isSelected: isThemeSelected(theme),
                            showAutoBadge: false,
                            onTap: { selectTheme(theme) }
                        )
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        } header: {
            Text("Theme")
        }
    }

    // MARK: - Background Type Section

    @ViewBuilder
    private var backgroundTypeSection: some View {
        Section {
            Picker("Background Style", selection: Binding(
                get: { ambientService.backgroundType },
                set: { ambientService.setBackgroundType($0) }
            )) {
                ForEach(BackgroundType.allCases) { type in
                    HStack {
                        Image(systemName: type.icon)
                        Text(type.displayName)
                    }
                    .tag(type)
                }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))

            // Description for selected type
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                Text(ambientService.backgroundType.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("Background Style")
        }
    }

    // MARK: - Accessibility Section

    @ViewBuilder
    private var accessibilitySection: some View {
        Section {
            HStack {
                Image(systemName: "accessibility")
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Accessibility")
                        .font(.body)
                    Text("Animations automatically respect your device's Reduce Motion setting")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Helper Methods

    private func isThemeSelected(_ theme: AmbientTheme) -> Bool {
        if ambientService.isAutoAdjustEnabled {
            return ambientService.currentTheme == theme
        } else {
            return ambientService.selectedTheme == theme
        }
    }

    private func selectTheme(_ theme: AmbientTheme) {
        ambientService.setTheme(theme)
    }
}

// MARK: - Theme Preview Tile

private struct ThemePreviewTile: View {
    let theme: AmbientTheme
    let isSelected: Bool
    let showAutoBadge: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                // Gradient preview
                ZStack {
                    LinearGradient.forTheme(theme)
                        .frame(height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Auto badge for time-based themes
                    if showAutoBadge && theme.isAutoAdjustable && theme != .auto {
                        VStack {
                            HStack {
                                Spacer()
                                Text("AUTO")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .padding(4)
                            }
                            Spacer()
                        }
                    }

                    // Selection checkmark
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                    }
                }

                // Theme name and icon
                HStack(spacing: 4) {
                    Image(systemName: theme.icon)
                        .font(.caption)
                    Text(theme.displayName)
                        .font(.caption)
                        .fontWeight(isSelected ? .semibold : .regular)
                }
                .foregroundColor(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.displayName) theme\(isSelected ? ", currently selected" : "")")
        .accessibilityHint(theme.themeDescription)
    }
}

// MARK: - Preview

#if DEBUG
struct AmbientSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            AmbientSettingsView()
                .environmentObject(AmbientThemeService.preview)
        }
    }
}
#endif
