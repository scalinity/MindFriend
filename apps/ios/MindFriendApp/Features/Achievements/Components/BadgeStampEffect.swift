import SwiftUI

struct BadgeStampEffect: View {
    let tierColor: Color
    let sfSymbol: String
    let onImpact: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(tierColor: Color, sfSymbol: String, onImpact: (() -> Void)? = nil) {
        self.tierColor = tierColor
        self.sfSymbol = sfSymbol
        self.onImpact = onImpact
    }

    var body: some View {
        CelebrationEmblem(.symbol(sfSymbol), tint: SupportTheme.Celebration.gold, diameter: 120)
            .task {
                if !reduceMotion {
                    try? await Task.sleep(for: .milliseconds(200))
                    guard !Task.isCancelled else { return }
                    HapticManager.badgeStamp()
                }
                onImpact?()
            }
    }
}

struct HexagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let centerX = rect.midX
        let centerY = rect.midY

        // Flat-top hexagon
        let radius = min(width, height) / 2
        var path = Path()

        for i in 0..<6 {
            let angle = CGFloat(i) * .pi / 3 - .pi / 6
            let x = centerX + radius * cos(angle)
            let y = centerY + radius * sin(angle)

            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()

        return path
    }
}
