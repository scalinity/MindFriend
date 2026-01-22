//
//  ValueCardView.swift
//  MindFriendApp
//
//  Reusable value card component with selection state and rank badge
//

import SwiftUI

struct ValueCardView: View {
    let card: ValueCard
    let isSelected: Bool
    let rank: Int? // 1-5 for ranked cards
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                // Icon and rank badge
                HStack {
                    Image(systemName: card.icon)
                        .font(.system(size: 32))
                        .foregroundStyle(categoryColor)
                        .frame(width: 40, height: 40)

                    Spacer()

                    if let rank = rank {
                        Text("\(rank)")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(categoryColor))
                    }
                }

                // Value name
                Text(card.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

                // Description
                Text(card.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                // Category badge
                HStack {
                    Image(systemName: card.category.icon)
                        .font(.caption2)
                    Text(card.category.displayName)
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.1), radius: isSelected ? 8 : 4, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? categoryColor : Color.clear, lineWidth: 3)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.3), value: isSelected)
    }

    private var categoryColor: Color {
        switch card.category {
        case .personal:
            return .blue
        case .relationships:
            return .pink
        case .work:
            return .orange
        case .growth:
            return .green
        }
    }
}

#Preview("Unselected Card") {
    ValueCardView(
        card: ValueCard(
            id: "1",
            valueKey: "growth",
            displayName: "Growth",
            description: "Continuous learning, self-improvement, and personal evolution.",
            category: .personal,
            icon: "chart.line.uptrend.xyaxis",
            questions: ["What areas do you want to grow in?"],
            examples: ["Taking courses", "Seeking feedback"]
        ),
        isSelected: false,
        rank: nil,
        onTap: {}
    )
    .padding()
}

#Preview("Selected Card") {
    ValueCardView(
        card: ValueCard(
            id: "2",
            valueKey: "connection",
            displayName: "Connection",
            description: "Deep, meaningful bonds with others; feeling understood and valued.",
            category: .relationships,
            icon: "person.2",
            questions: ["Who do you feel most connected to?"],
            examples: ["Heart-to-heart conversations"]
        ),
        isSelected: true,
        rank: nil,
        onTap: {}
    )
    .padding()
}

#Preview("Ranked Card") {
    ValueCardView(
        card: ValueCard(
            id: "3",
            valueKey: "purpose",
            displayName: "Purpose",
            description: "Doing work that feels meaningful and aligned with your values.",
            category: .work,
            icon: "target",
            questions: ["What gives your work meaning?"],
            examples: ["Helping people improve their lives"]
        ),
        isSelected: true,
        rank: 1,
        onTap: {}
    )
    .padding()
}
