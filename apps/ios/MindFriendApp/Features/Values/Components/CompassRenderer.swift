//
//  CompassRenderer.swift
//  MindFriendApp
//
//  Canvas-based values compass visualization with 4 quadrants
//

import SwiftUI

struct CompassRenderer: View {
    let values: [RankedValue]
    let showCategories: Bool

    init(values: [RankedValue], showCategories: Bool = true) {
        self.values = values
        self.showCategories = showCategories
    }

    struct RankedValue: Identifiable {
        let id: String
        let displayName: String
        let category: ValueCategory
        let rank: Int // 1-5
    }

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: size / 2, y: size / 2)
            let radius = size * 0.35

            Canvas { context, canvasSize in
                // Draw quadrant backgrounds
                drawQuadrants(context: &context, center: center, radius: radius)

                // Draw category labels
                if showCategories {
                    drawCategoryLabels(context: &context, center: center, radius: radius)
                }

                // Draw values as circles
                drawValues(context: &context, center: center, radius: radius)
            }
            .frame(width: size, height: size)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func drawQuadrants(context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        let quadrants: [(ValueCategory, Color)] = [
            (.personal, .blue.opacity(0.1)),
            (.relationships, .pink.opacity(0.1)),
            (.work, .orange.opacity(0.1)),
            (.growth, .green.opacity(0.1))
        ]

        for (index, (_, color)) in quadrants.enumerated() {
            let startAngle = Angle(degrees: Double(index) * 90 - 45)
            let endAngle = Angle(degrees: Double(index + 1) * 90 - 45)

            var path = Path()
            path.move(to: center)
            path.addArc(
                center: center,
                radius: radius,
                startAngle: startAngle,
                endAngle: endAngle,
                clockwise: false
            )
            path.closeSubpath()

            context.fill(path, with: .color(color))
        }
    }

    private func drawCategoryLabels(context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        let labels: [(ValueCategory, Angle)] = [
            (.personal, .degrees(0)),
            (.relationships, .degrees(90)),
            (.work, .degrees(180)),
            (.growth, .degrees(270))
        ]

        for (category, angle) in labels {
            let labelRadius = radius * 0.7
            let x = center.x + cos(angle.radians) * labelRadius
            let y = center.y + sin(angle.radians) * labelRadius

            context.draw(
                Text(category.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(categoryColor(for: category)),
                at: CGPoint(x: x, y: y)
            )
        }
    }

    private func drawValues(context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        // Group values by category
        let groupedValues = Dictionary(grouping: values, by: { $0.category })

        for (category, categoryValues) in groupedValues {
            let baseAngle = angleForCategory(category)
            let spreadAngle = 60.0 // Degrees to spread values within category

            for (index, value) in categoryValues.enumerated() {
                let offset = Double(index) - Double(categoryValues.count - 1) / 2.0
                let angle = Angle(degrees: baseAngle + (offset * spreadAngle / Double(max(categoryValues.count - 1, 1))))

                let valueRadius = radius * (0.5 + 0.3 * (1.0 - Double(value.rank - 1) / 4.0))
                let _ = center.x + cos(angle.radians) * valueRadius
                let _ = center.y + sin(angle.radians) * valueRadius

                // Draw circle
                let circleSize = 40.0 - Double(value.rank - 1) * 5.0
                let _ = Circle()
                    .fill(categoryColor(for: value.category))
                    .frame(width: circleSize, height: circleSize)

                // TODO: Fix GraphicsContext.draw API - shape drawing needs to be converted to proper graphics context operations
                // context.draw(circle, at: CGPoint(x: x, y: y))

                // Draw rank
                // TODO: Fix GraphicsContext.draw API - text drawing needs conversion
                // context.draw(
                //     Text("\(value.rank)")
                //         .font(.system(size: 14, weight: .bold))
                //         .foregroundStyle(.white),
                //     at: CGPoint(x: x, y: y)
                // )

                // Draw label below
                // TODO: Fix GraphicsContext.draw API - text drawing needs conversion
                // context.draw(
                //     Text(value.displayName)
                //         .font(.system(size: 10))
                //         .foregroundStyle(.primary),
                //     at: CGPoint(x: x, y: y + circleSize / 2 + 12)
                // )
            }
        }
    }

    private func categoryColor(for category: ValueCategory) -> Color {
        switch category {
        case .personal: return .blue
        case .relationships: return .pink
        case .work: return .orange
        case .growth: return .green
        }
    }

    private func angleForCategory(_ category: ValueCategory) -> Double {
        switch category {
        case .personal: return 0
        case .relationships: return 90
        case .work: return 180
        case .growth: return 270
        }
    }

    // MARK: - Export

    @MainActor
    func snapshot() -> UIImage {
        let renderer = ImageRenderer(content: self.frame(width: 1080, height: 1080))
        renderer.scale = 3.0
        return renderer.uiImage ?? UIImage()
    }
}

#Preview {
    CompassRenderer(
        values: [
            CompassRenderer.RankedValue(id: "1", displayName: "Growth", category: .personal, rank: 1),
            CompassRenderer.RankedValue(id: "2", displayName: "Connection", category: .relationships, rank: 2),
            CompassRenderer.RankedValue(id: "3", displayName: "Purpose", category: .work, rank: 3),
            CompassRenderer.RankedValue(id: "4", displayName: "Learning", category: .growth, rank: 4),
            CompassRenderer.RankedValue(id: "5", displayName: "Autonomy", category: .personal, rank: 5)
        ]
    )
    .padding()
    .frame(height: 400)
}
