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
                                .foregroundStyle(theme.iconColor)
                                .frame(width: 24)

                            Text(theme.displayName)
                                .foregroundStyle(.primary)

                            Spacer()

                            if selectedTheme == theme {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .accessibilityLabel("\(theme.displayName) theme")
                    .accessibilityHint(theme == .system ? "Follows your device's appearance setting" : "Always use \(theme.displayName.lowercased()) mode")
                    .accessibilityAddTraits(selectedTheme == theme ? .isSelected : [])
                }
            } header: {
                Text("Theme")
            } footer: {
                Text("Choose how MindFriend appears. System uses your device's light or dark mode setting.")
            }

            // Ambient Themes Section
            Section {
                NavigationLink {
                    AmbientSettingsView()
                        .environmentObject(container.ambientThemeService)
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.purple)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ambient Themes")
                            Text("Dynamic backgrounds & visual effects")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Visual Experience")
            } footer: {
                Text("Customize ambient backgrounds that adapt to your mood and time of day.")
            }
        }
        .navigationTitle("Appearance")
    }
}

#Preview {
    NavigationStack {
        AppearanceSettingsView()
            .environmentObject(DependencyContainer())
    }
}
