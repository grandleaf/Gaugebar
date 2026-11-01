//
//  CoreBoxLayout.swift
//  Kit
//
//  Geometry for the per-core box style of the bar chart widget.
//

import Foundation

public struct CoreBoxLayout {
    public static let minimumBarWidth: CGFloat = 3
    public static let minimumGap: CGFloat = 1

    public let boxes: [CGRect]
    public let width: CGFloat

    /// - Parameters:
    ///   - groups: number of boxes in each cluster, in drawing order.
    ///   - barWidth: width of one box, including its outline.
    ///   - gap: space between neighbouring boxes.
    ///   - clusterGap: extra space between clusters.
    ///   - maxWidth: boxes shrink to fit this, down to the minimum readable size.
    ///   - scale: backing scale of the display. Positions land on whole device pixels.
    public init(groups: [Int], barWidth: CGFloat, gap: CGFloat, clusterGap: CGFloat, maxWidth: CGFloat, height: CGFloat, scale: CGFloat) {
        let groups = groups.filter { $0 > 0 }
        let count = groups.reduce(0, +)
        guard count > 0 else {
            self.boxes = []
            self.width = 0
            return
        }

        let pixels = max(scale, 1)
        let snap: (CGFloat) -> CGFloat = { ($0 * pixels).rounded() / pixels }
        let snapDown: (CGFloat) -> CGFloat = { ($0 * pixels).rounded(.down) / pixels }
        let gaps = CGFloat(count - 1)
        let clusterGaps = CGFloat(groups.count - 1)

        var bar = max(snap(barWidth), Self.minimumBarWidth)
        var space = max(snap(gap), Self.minimumGap)
        var extra = max(snap(clusterGap), 0)

        let total = CGFloat(count) * bar + gaps * space + clusterGaps * extra
        if total > maxWidth {
            let ratio = maxWidth / total
            bar = max(snapDown(bar * ratio), Self.minimumBarWidth)
            space = max(snapDown(space * ratio), Self.minimumGap)
            extra = max(snapDown(extra * ratio), 0)

            // Rounding down can leave room to spare, so give it back to the boxes.
            let step = 1 / pixels
            while CGFloat(count) * (bar + step) + gaps * space + clusterGaps * extra <= maxWidth {
                bar += step
            }
        }

        var rects: [CGRect] = []
        rects.reserveCapacity(count)
        var x: CGFloat = 0
        for (index, size) in groups.enumerated() {
            if index != 0 {
                x += extra
            }
            for _ in 0..<size {
                rects.append(CGRect(x: x, y: 0, width: bar, height: height))
                x += bar + space
            }
        }

        self.boxes = rects
        self.width = x - space
    }
}
