import SwiftUI

/// Accessible entry for an eight-character, case-sensitive partner code.
struct CodeEntryField: View {
    @Binding var code: String
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Partner code", text: $code)
            .font(.body.monospaced())
            .supportField()
            .keyboardType(.asciiCapable)
            .textContentType(.oneTimeCode)
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            .focused($isFocused)
            .onChange(of: code) { _, newValue in
                // Partner codes are case-sensitive Base58 values.
                let filtered = newValue
                    .filter { "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".contains($0) }
                    .prefix(8)
                if code != String(filtered) {
                    code = String(filtered)
                }
            }
            .accessibilityLabel("Partner code entry")
            .accessibilityValue(code.isEmpty ? "Empty" : code.map { String($0) }.joined(separator: ", "))
            .accessibilityHint("Enter the 8-character code from your partner")
    }
}

#Preview {
    VStack(spacing: SupportTheme.Spacing.xl) {
        CodeEntryField(code: .constant(""))
        CodeEntryField(code: .constant("AB7"))
        CodeEntryField(code: .constant("Ab7x2Qp9"))
    }
    .padding()
}
