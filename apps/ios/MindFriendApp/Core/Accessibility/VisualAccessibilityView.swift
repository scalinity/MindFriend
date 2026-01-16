// Spec 14: Visual Accessibility Settings
// Color blind mode and contrast adjustments

import SwiftUI

struct VisualAccessibilityView: View {
    @State private var colorBlindMode: ColorBlindMode = .none
    @State private var increaseContrast = false
    @State private var reduceTransparency = false
    @State private var boldText = false

    var body: some View {
        Form {
            Section("Color Blind Mode") {
                Picker("Vision Type", selection: $colorBlindMode) {
                    Text("None").tag(ColorBlindMode.none)
                    Text("Protanopia (Red-Blind)").tag(ColorBlindMode.protanopia)
                    Text("Deuteranopia (Green-Blind)").tag(ColorBlindMode.deuteranopia)
                    Text("Tritanopia (Blue-Yellow)").tag(ColorBlindMode.tritanopia)
                    Text("Achromasia (Complete)").tag(ColorBlindMode.achromasia)
                }
                .pickerStyle(.menu)
            }

            Section("Contrast & Display") {
                Toggle("Increase Contrast", isOn: $increaseContrast)
                Toggle("Reduce Transparency", isOn: $reduceTransparency)
                Toggle("Bold Text", isOn: $boldText)
            }

            Section("Preview") {
                VStack(spacing: 12) {
                    // Primary button preview
                    Button(action: {}) {
                        Text("Primary Button")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.primary)

                    // Secondary button preview
                    Button(action: {}) {
                        Text("Secondary Button")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    // Color palette preview
                    HStack(spacing: 8) {
                        ForEach([Color.red, Color.green, Color.blue, Color.yellow], id: \.self) { color in
                            RoundedRectangle(cornerRadius: 8)
                                .fill(color)
                                .frame(height: 44)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .navigationTitle("Visual Accessibility")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        VisualAccessibilityView()
    }
}
