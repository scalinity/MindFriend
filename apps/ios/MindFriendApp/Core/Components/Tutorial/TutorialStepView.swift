//
//  TutorialStepView.swift
//  MindFriendApp
//
//  Reusable tutorial step layout component
//  Used across all feature tutorials for consistent UX
//

import SwiftUI

/// Standard layout for tutorial steps with icon, headlines, custom content, and actions
struct TutorialStepView<Content: View>: View {
    let icon: String
    let iconColor: Color
    let headline: String
    let subheadline: String
    let content: Content
    let primaryAction: () -> Void
    let primaryLabel: String
    let skipAction: (() -> Void)?

    init(
        icon: String,
        iconColor: Color = .blue,
        headline: String,
        subheadline: String,
        primaryLabel: String = "Next",
        primaryAction: @escaping () -> Void,
        skipAction: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.headline = headline
        self.subheadline = subheadline
        self.primaryLabel = primaryLabel
        self.primaryAction = primaryAction
        self.skipAction = skipAction
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 8)

            // Icon
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(iconColor)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)

            // Headlines
            VStack(spacing: 6) {
                Text(headline)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text(subheadline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal)
            }

            // Custom content
            content
                .padding(.vertical, 8)

            Spacer(minLength: 8)

            // Actions
            VStack(spacing: 10) {
                Button(action: primaryAction) {
                    Text(primaryLabel)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityHint("Proceed to the next step")

                if let skipAction = skipAction {
                    Button(action: skipAction) {
                        Text("Skip tutorial")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityHint("Skip the remaining tutorial steps")
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .padding(.horizontal)
    }
}

/// Empty content version for simple text-only tutorial steps
extension TutorialStepView where Content == EmptyView {
    init(
        icon: String,
        iconColor: Color = .blue,
        headline: String,
        subheadline: String,
        primaryLabel: String = "Next",
        primaryAction: @escaping () -> Void,
        skipAction: (() -> Void)? = nil
    ) {
        self.init(
            icon: icon,
            iconColor: iconColor,
            headline: headline,
            subheadline: subheadline,
            primaryLabel: primaryLabel,
            primaryAction: primaryAction,
            skipAction: skipAction
        ) {
            EmptyView()
        }
    }
}

#Preview {
    TutorialStepView(
        icon: "star.fill",
        iconColor: .yellow,
        headline: "Welcome!",
        subheadline: "This is a preview of the tutorial step layout.",
        primaryAction: {},
        skipAction: {}
    ) {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Custom content here")
            }
        }
    }
}
