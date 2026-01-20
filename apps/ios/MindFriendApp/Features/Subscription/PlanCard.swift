import SwiftUI

/// Reusable plan selector card with pricing information
struct PlanCard: View {
    let plan: SubscriptionPlan
    let isSelected: Bool
    let onSelect: () -> Void
    var discount: Int?

    private var isBestValue: Bool {
        plan.billingPeriod == .yearly
    }

    private var displayPrice: String {
        plan.displayPrice
    }

    private var monthlyEquivalent: String? {
        guard let pricePerMonth = plan.pricePerMonth else { return nil }
        return pricePerMonth + "/month"
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Left side: Plan name and badge
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(plan.name)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if isBestValue {
                            Text("Best Value")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .foregroundStyle(.white)
                                .cornerRadius(4)
                        }

                        if let discount = discount, discount > 0 {
                            Text("\(discount)% off")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.orange)
                                .foregroundStyle(.white)
                                .cornerRadius(4)
                        }
                    }

                    if let description = plan.description {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Right side: Price information
                VStack(alignment: .trailing, spacing: 4) {
                    Text(displayPrice)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)

                    if let monthly = monthlyEquivalent {
                        Text(monthly)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(plan.billingPeriod.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.1)
                    : Color(.secondarySystemBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected
                            ? Color.accentColor
                            : Color.clear,
                        lineWidth: 2
                    )
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(plan.name), \(displayPrice)"
                + (isBestValue ? ", Best Value" : "")
                + (discount ?? 0 > 0 ? ", \(discount ?? 0)% discount" : "")
        )
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Double tap to select this plan")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// TODO: Re-enable preview once BusinessModels.swift is added to project
/*
#Preview {
    VStack(spacing: 16) {
        PlanCard(
            plan: .premiumMonthly,
            isSelected: false,
            onSelect: {},
            discount: nil
        )

        PlanCard(
            plan: .premiumAnnual,
            isSelected: true,
            onSelect: {},
            discount: 50
        )

        PlanCard(
            plan: .familyAnnual,
            isSelected: false,
            onSelect: {},
            discount: nil
        )
    }
    .padding()
}
*/
