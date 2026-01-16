// Spec 14: Language Settings
// Language and region selection for localization

import SwiftUI

struct LanguageSettingsView: View {
    @State private var selectedLanguage = "en"
    @State private var selectedRegion = "US"

    let languages = [
        ("en", "English"),
        ("es", "Español"),
        ("fr", "Français"),
        ("de", "Deutsch"),
        ("it", "Italiano"),
        ("ja", "日本語"),
        ("zh", "中文"),
        ("ar", "العربية")
    ]

    let regions = [
        ("US", "United States"),
        ("GB", "United Kingdom"),
        ("CA", "Canada"),
        ("AU", "Australia"),
        ("MX", "Mexico"),
        ("ES", "Spain"),
        ("FR", "France"),
        ("DE", "Germany")
    ]

    var body: some View {
        Form {
            Section("Language") {
                Picker("Language", selection: $selectedLanguage) {
                    ForEach(languages, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Region") {
                Picker("Region", selection: $selectedRegion) {
                    ForEach(regions, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Current Setting") {
                Label("Language Code", systemImage: "globe")
                Text("\(selectedLanguage)_\(selectedRegion)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Section("Features") {
                Toggle("Date Format: \(DateFormatter().locale?.identifier ?? "Auto")", isOn: .constant(true))
                Toggle("Time Format: 24h", isOn: .constant(true))
                Toggle("Number Format: Regional", isOn: .constant(true))
            }
        }
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        LanguageSettingsView()
    }
}
