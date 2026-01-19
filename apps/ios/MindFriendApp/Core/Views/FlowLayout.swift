//
//  FlowLayout.swift
//  MindFriendApp
//
//  Created by Claude Code on 2026-01-18.
//  Copyright © 2026 MindFriend. All rights reserved.
//

import SwiftUI

/// A layout that arranges its children in a flowing row-based pattern.
/// When a row fills up horizontally, children wrap to the next row.
/// Commonly used for tag clouds, filter chips, and flexible content grids.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }

        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0

        for size in sizes {
            if lineWidth + size.width > (proposal.width ?? 0) {
                totalHeight += lineHeight + spacing
                lineWidth = size.width
                lineHeight = size.height
            } else {
                lineWidth += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }

            totalWidth = max(totalWidth, lineWidth)
        }

        totalHeight += lineHeight

        return CGSize(width: totalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }

        var lineX = bounds.minX
        var lineY = bounds.minY
        var lineHeight: CGFloat = 0

        for index in subviews.indices {
            let size = sizes[index]

            if lineX + size.width > bounds.maxX && lineX > bounds.minX {
                // Move to next line
                lineY += lineHeight + spacing
                lineHeight = 0
                lineX = bounds.minX
            }

            let position = CGPoint(
                x: lineX + size.width / 2,
                y: lineY + size.height / 2
            )

            subviews[index].place(
                at: position,
                anchor: .center,
                proposal: ProposedViewSize(size)
            )

            lineHeight = max(lineHeight, size.height)
            lineX += size.width + spacing
        }
    }
}

// MARK: - Convenience Initializer

extension FlowLayout {
    /// Creates a FlowLayout with the specified spacing between items.
    /// - Parameter spacing: The spacing between items (default: 8)
    init(spacing: CGFloat = 8, @ViewBuilder content: () -> some View) {
        self.spacing = spacing
    }
}
