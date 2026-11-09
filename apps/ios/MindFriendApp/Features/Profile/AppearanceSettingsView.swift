import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage(AppTheme.storageKey) private var selectedTheme: AppTheme = .system
    @EnvironmentObject var container: DependencyContainer

    var body: some View {
        Form {
            Section {
                ForEach(AppTheme.allCases) { theme in
                    Button {
                        selectedTheme = theme
                    } label: {
                        HStack {
                            Image(systemName: theme.icon)
                                .foregroundStyle(SupportTheme.accent)
                                .frame(width: 24)

                            Text(theme.displayName)
                                .foregroundStyle(SupportTheme.textPrimary)

                            Spacer()

                            if selectedTheme == theme {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(SupportTheme.accent)
                            }
                        }
                    }
                    .accessibilityLabel("\(theme.displayName) theme")
                    .accessibilityHint(
                        theme == .system
                            ? "Follows your device's appearance setting"
                            : "Always use \(theme.displayName.lowercased()) mode"
                    )
                    .accessibilityAddTraits(selectedTheme == theme ? .isSelected : [])
                }
            } header: {
                Text("Theme")
            } footer: {
                Text("Choose how MindFriend appears. System uses your device's light or dark mode setting.")
            }
            .listRowBackground(SupportTheme.surface)

            // Ambient Themes Section
            Section {
                NavigationLink {
                    AmbientSettingsView()
                        .environmentObject(container.ambientThemeService)
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(SupportTheme.accent)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                            Text("Ambient Themes")
                            Text("Dynamic backgrounds & visual effects")
                                .font(.caption)
                                .foregroundStyle(SupportTheme.textSecondary)
                        }
                    }
                }
            } header: {
                Text("Visual Experience")
            } footer: {
                Text("Customize ambient backgrounds that adapt to your mood and time of day.")
            }

            .listRowBackground(SupportTheme.surface)
        }
        .supportScreen()
        .foregroundStyle(SupportTheme.textPrimary)
        .navigationTitle("Appearance")
    }
}

#Preview {
    NavigationStack {
        AppearanceSettingsView()
            .environmentObject(DependencyContainer())
    }
}
