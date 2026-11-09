//
//  SleepHomeCard.swift
//  MindFriendApp
//
//  Home screen card for sleep tracking feature
//

import SwiftUI

/// Compact card for home screen linking to sleep dashboard
struct SleepHomeCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            HStack {
                Image(systemName: "moon.zzz.fill")
                    .font(.title2)
                    .foregroundColor(SupportTheme.accent)

                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text("Sleep Tracking")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                        .foregroundColor(SupportTheme.textPrimary)

                    Text("Track your sleep quality")
                        .font(.caption)
                        .foregroundColor(SupportTheme.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.body)
                    .foregroundColor(SupportTheme.textSecondary)
            }
        }
        .padding()
        .background(SupportTheme.field)
        .cornerRadius(SupportTheme.controlRadius)
    }
}

#Preview {
    SleepHomeCard()
        .padding()
}
