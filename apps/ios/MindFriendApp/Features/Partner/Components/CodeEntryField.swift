import SwiftUI

/// 8-character code entry field with individual boxes
struct CodeEntryField: View {
    @Binding var code: String
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            // Hidden text field for input
            TextField("", text: $code)
                .keyboardType(.asciiCapable)
                .textContentType(.oneTimeCode)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .focused($isFocused)
                .opacity(0)
                .onChange(of: code) { _, newValue in
                    // Partner codes are case-sensitive Base58 values.
                    let filtered = newValue
                        .filter { "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".contains($0) }
                        .prefix(8)
                    if code != String(filtered) {
                        code = String(filtered)
                    }
                }

            // Visual display
            HStack(spacing: 6) {
                ForEach(0..<8, id: \.self) { index in
                    CodeBox(
                        character: character(at: index),
                        isActive: index == code.count && isFocused
                    )
                }
            }
            .onTapGesture {
                isFocused = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Partner code entry")
        .accessibilityValue(code.isEmpty ? "Empty" : code.map { String($0) }.joined(separator: ", "))
        .accessibilityHint("Enter the 8-character code from your partner")
    }

    private func character(at index: Int) -> Character? {
        guard index < code.count else { return nil }
        return code[code.index(code.startIndex, offsetBy: index)]
    }
}

// MARK: - Code Box

private struct CodeBox: View {
    let character: Character?
    let isActive: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isActive ? 2 : 1)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.secondarySystemBackground))
                )

            if let character = character {
                Text(String(character))
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
            } else if isActive {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 2, height: 24)
                    .opacity(0.8)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 48)
    }
}

#Preview {
    VStack(spacing: 32) {
        CodeEntryField(code: .constant(""))
        CodeEntryField(code: .constant("AB7"))
        CodeEntryField(code: .constant("Ab7x2Qp9"))
    }
    .padding()
}
