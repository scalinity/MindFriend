import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage(AppTheme.storageKey) private var selectedTheme: AppTheme = .system

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
        }
        .navigationTitle("Appearance")
    }
}

#Preview {
    NavigationStack {
        AppearanceSettingsView()
    }
}
