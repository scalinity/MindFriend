import SwiftUI

/// Reusable plan selector card with pricing information
struct PlanCard: View {
    @Environment(\.dynamicTypeSize) private var typeSize
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
            (typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: SupportTheme.Spacing.s))
                : AnyLayout(HStackLayout(spacing: SupportTheme.Spacing.s))) {
                    // Left side: Plan name and badge
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                        HStack(spacing: SupportTheme.Spacing.xs) {
                            Text(plan.name)
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                                .foregroundStyle(SupportTheme.textPrimary)

                            if isBestValue {
                                Text("Best Value")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, SupportTheme.Spacing.xs)
                                    .padding(.vertical, SupportTheme.Spacing.xxs)
                                    .background(SupportTheme.field)
                                    .foregroundStyle(SupportTheme.accent)
                                    .cornerRadius(SupportTheme.controlRadius)
                            }

                            if let discount = discount, discount > 0 {
                                Text("\(discount)% off")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, SupportTheme.Spacing.xs)
                                    .padding(.vertical, SupportTheme.Spacing.xxs)
                                    .background(SupportTheme.field)
                                    .foregroundStyle(SupportTheme.accent)
                                    .cornerRadius(SupportTheme.controlRadius)
                            }
                        }

                        if let description = plan.description {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(SupportTheme.textSecondary)
                        }
                    }

                    Spacer()

                    // Right side: Price information
                    VStack(alignment: .trailing, spacing: SupportTheme.Spacing.xxs) {
                        Text(displayPrice)
                            .font(.title3)
                            .accessibilityAddTraits(.isHeader)
                            .fontWeight(.bold)
                            .foregroundStyle(SupportTheme.textPrimary)

                        if let monthly = monthlyEquivalent {
                            Text(monthly)
                                .font(.caption)
                                .foregroundStyle(SupportTheme.textSecondary)
                        } else {
                            Text(plan.billingPeriod.displayName)
                                .font(.caption)
                                .foregroundStyle(SupportTheme.textSecondary)
                        }
                    }
                }
                .padding()
                .background(
                    isSelected
                        ? SupportTheme.elevated
                        : SupportTheme.surface
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SupportTheme.cardRadius)
                        .stroke(
                            isSelected
                                ? SupportTheme.accent
                                : Color.clear,
                            lineWidth: 2
                        )
                )
                .cornerRadius(SupportTheme.controlRadius)
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
    VStack(spacing: SupportTheme.Spacing.m) {
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
