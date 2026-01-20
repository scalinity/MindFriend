import SwiftUI

/// 6-character code entry field with individual boxes
struct CodeEntryField: View {
    @Binding var code: String
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            // Hidden text field for input
            TextField("", text: $code)
                .keyboardType(.asciiCapable)
                .textContentType(.oneTimeCode)
                .autocapitalization(.allCharacters)
                .disableAutocorrection(true)
                .focused($isFocused)
                .opacity(0)
                .onChange(of: code) { _, newValue in
                    // Limit to 6 characters, uppercase only
                    let filtered = newValue
                        .uppercased()
                        .filter { $0.isLetter || $0.isNumber }
                        .prefix(6)
                    if code != String(filtered) {
                        code = String(filtered)
                    }
                }

            // Visual display
            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { index in
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
        .accessibilityHint("Enter the 6-character code from your partner")
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
        .frame(width: 44, height: 52)
    }
}

#Preview {
    VStack(spacing: 32) {
        CodeEntryField(code: .constant(""))
        CodeEntryField(code: .constant("AB7"))
        CodeEntryField(code: .constant("AB7X2Q"))
    }
    .padding()
}
