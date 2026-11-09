import SwiftUI

/// A badge that displays the evidence basis for an exercise
struct EvidenceBadge: View {
    let basis: EvidenceBasis
    let isReviewed: Bool
    var showInfo: Bool = true

    @State private var showingInfo = false

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.xxs) {
            Text(basis.shortLabel)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(SupportTheme.accent)
                .fixedSize(horizontal: false, vertical: true)

            if isReviewed {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption2)
                    .foregroundColor(SupportTheme.accent)
                    .accessibilityLabel("Therapist reviewed")
            }

            if showInfo {
                Button {
                    showingInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundColor(SupportTheme.textSecondary)
                        .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                }
                .accessibilityLabel("More information about \(basis.displayName)")
            }
        }
        .padding(.horizontal, SupportTheme.Spacing.xxs)
        .padding(.vertical, SupportTheme.Spacing.xxs)
        .background(SupportTheme.surface)
        .cornerRadius(SupportTheme.controlRadius)
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
    VStack(spacing: SupportTheme.Spacing.m) {
        EvidenceBadge(basis: .CBT, isReviewed: true)
        EvidenceBadge(basis: .Mindfulness, isReviewed: true)
        EvidenceBadge(basis: .Breathwork, isReviewed: false)
        EvidenceBadge(basis: .Somatic, isReviewed: true, showInfo: false)
    }
    .padding(SupportTheme.Spacing.m)
}
