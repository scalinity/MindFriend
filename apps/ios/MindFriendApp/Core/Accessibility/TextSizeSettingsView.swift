// Spec 14: Text Size Settings
// Font size and text style adjustments

import SwiftUI

struct TextSizeSettingsView: View {
    @State private var fontSizePreference: FontSizePreference = .system
    @State private var lineSpacing: Double = 1.0
    @State private var letterSpacing: Double = 0.0

    private var adjustedLineSpacing: Double { lineSpacing - 1 }

    var body: some View {
        Form {
            Section("Text Size") {
                Picker("Size", selection: $fontSizePreference) {
                    Text("System Default").tag(FontSizePreference.system)
                    Text("Small").tag(FontSizePreference.small)
                    Text("Medium").tag(FontSizePreference.medium)
                    Text("Large").tag(FontSizePreference.large)
                    Text("Extra Large").tag(FontSizePreference.xlarge)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Text Size")
                .accessibilityHint("Choose a text size preference")
            }

            Section("Spacing") {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Line Spacing: \(String(format: "%.1f", lineSpacing))x", systemImage: "line.3.horizontal")
                    Slider(value: $lineSpacing, in: 0.8...2.0, step: 0.1)
                        .accessibilityLabel("Line Spacing")
                        .accessibilityValue("\(String(format: "%.1f", lineSpacing))x")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("Letter Spacing: \(String(format: "%.1f", letterSpacing))pt", systemImage: "character")
                    Slider(value: $letterSpacing, in: -1...3, step: 0.5)
                        .accessibilityLabel("Letter Spacing")
                        .accessibilityValue("\(String(format: "%.1f", letterSpacing))pt")
                }
            }

            Section("Preview") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Heading")
                        .font(.title2)
                        .fontWeight(.bold)
                        .lineSpacing(adjustedLineSpacing)
                        .tracking(letterSpacing)

                    Text("Body text preview. This is how your content will appear with the current text size and spacing settings applied.")
                        .font(.body)
                        .lineSpacing(adjustedLineSpacing)
                        .tracking(letterSpacing)

                    Text("Caption text")
                        .font(.caption)
                        .lineSpacing(adjustedLineSpacing)
                        .tracking(letterSpacing)
                }
                .padding(.vertical, 8)
            }
        }
        .navigationTitle("Text Size")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        TextSizeSettingsView()
    }
}
