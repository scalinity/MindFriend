// Spec 14: Captions Settings
// Audio caption settings and language preferences

import SwiftUI

struct CaptionsView: View {
    @State private var captionsEnabled = true
    @State private var captionLanguage = "en"
    @State private var captionSize: Double = 1.0
    @State private var captionBackground = true
    @State private var captionOpacity: Double = 0.8

    var body: some View {
        Form {
            Section("Captions") {
                Toggle("Enable Captions", isOn: $captionsEnabled)

                if captionsEnabled {
                    Picker("Language", selection: $captionLanguage) {
                        Text("English").tag("en")
                        Text("Spanish").tag("es")
                        Text("French").tag("fr")
                        Text("German").tag("de")
                    }
                    .pickerStyle(.menu)
                    .onChange(of: captionLanguage) { _, language in
                        Log.ui.info("Caption language changed to: \(language)")
                    }
                }
            }

            if captionsEnabled {
                Section("Appearance") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Size: \(String(format: "%.0f", captionSize * 100))%", systemImage: "textformat.size")
                        Slider(value: $captionSize, in: 0.75...1.5, step: 0.25)
                            .accessibilityLabel("Caption Size")
                            .accessibilityValue("\(String(format: "%.0f", captionSize * 100))%")
                            .onChange(of: captionSize) { _, size in
                                Log.ui.info("Caption size changed to: \(size)")
                            }
                    }

                    Toggle("Background", isOn: $captionBackground)
                        .accessibilityLabel("Caption Background")
                        .onChange(of: captionBackground) { _, enabled in
                            Log.ui.info("Caption background changed to: \(enabled)")
                        }

                    if captionBackground {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Background Opacity", systemImage: "square.fill.on.square")
                            Slider(value: $captionOpacity, in: 0.3...1.0, step: 0.1)
                                .accessibilityLabel("Background Opacity")
                                .accessibilityValue("\(String(format: "%.0f", captionOpacity * 100))%")
                                .onChange(of: captionOpacity) { _, opacity in
                                    Log.ui.info("Caption opacity changed to: \(opacity)")
                                }
                        }
                    }
                }

                Section("Preview") {
                    VStack(alignment: .leading, spacing: 12) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(captionBackground ? captionOpacity : 0))
                            .frame(height: 60)
                            .overlay {
                                Text("This is how your captions will appear")
                                    .font(.system(size: 14 * captionSize))
                                    .foregroundColor(.white)
                                    .padding(8)
                            }
                    }
                    .padding(.vertical, 8)
                }

                Section("Note") {
                    Label("Not all content has captions available", systemImage: "info.circle.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Captions")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        CaptionsView()
    }
}
