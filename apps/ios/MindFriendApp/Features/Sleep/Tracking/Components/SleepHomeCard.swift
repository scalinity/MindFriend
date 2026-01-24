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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "moon.zzz.fill")
                    .font(.title2)
                    .foregroundColor(.indigo)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Sleep Tracking")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("Track your sleep quality")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

#Preview {
    SleepHomeCard()
        .padding()
}
