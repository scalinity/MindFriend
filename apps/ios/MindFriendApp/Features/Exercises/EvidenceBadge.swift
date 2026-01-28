import SwiftUI

/// A badge that displays the evidence basis for an exercise
struct EvidenceBadge: View {
    let basis: EvidenceBasis
    let isReviewed: Bool
    var showInfo: Bool = true

    @State private var showingInfo = false

    var body: some View {
        HStack(spacing: 4) {
            Text(basis.shortLabel)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(basis.color)
                .lineLimit(1)

            if isReviewed {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption2)
                    .foregroundColor(.green)
                    .accessibilityLabel("Therapist reviewed")
            }

            if showInfo {
                Button {
                    showingInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .accessibilityLabel("More information about \(basis.displayName)")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(basis.color.opacity(0.1))
        .cornerRadius(6)
        .sheet(isPresented: $showingInfo) {
            MethodologyInfoSheet(basis: basis)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        var description = "Based on \(basis.displayName)"
        if isReviewed {
            description += ", reviewed by mental health professionals"
        }
        return description
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        EvidenceBadge(basis: .CBT, isReviewed: true)
        EvidenceBadge(basis: .Mindfulness, isReviewed: true)
        EvidenceBadge(basis: .Breathwork, isReviewed: false)
        EvidenceBadge(basis: .Somatic, isReviewed: true, showInfo: false)
    }
    .padding()
}
