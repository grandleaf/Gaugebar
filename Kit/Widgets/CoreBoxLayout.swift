//
//  CoreBoxLayout.swift
//  Kit
//
//  Geometry for the per-core box style of the bar chart widget.
//

import Foundation

public struct CoreBoxLayout {
    public static let boxHeight: CGFloat = 19
    public static let outlineWidth: CGFloat = 1
    public static let outlineAlpha: CGFloat = 0.42
    public static let dividerAlpha: CGFloat = 0.18
    public static let separatorSize: CGFloat = 3
    public static let separatorAlpha: CGFloat = 0.4
    public static let minimumBarWidth: CGFloat = 3
    public static let minimumGap: CGFloat = 1

    public let boxes: [CGRect]
    /// Rectangles to outline: one per box, or one per cluster when boxes share outlines.
    public let outlines: [CGRect]
    /// The edges shared by neighbouring boxes.
    public let dividers: [CGRect]
    /// Dots between clusters, where the gap has room for one.
    public let separators: [CGRect]
    public let width: CGFloat

    /// - Parameters:
    ///   - groups: number of boxes in each cluster, in drawing order.
    ///   - barWidth: width of one box, including its outline.
    ///   - gap: space between neighbouring boxes. At zero they overlap by one outline, so they share it.
    ///   - clusterGap: extra space between clusters.
    ///   - maxWidth: boxes shrink to fit this, down to the minimum readable size.
    ///   - scale: backing scale of the display. Positions land on whole device pixels.
    public init(groups: [Int], barWidth: CGFloat, gap: CGFloat, clusterGap: CGFloat, maxWidth: CGFloat, height: CGFloat, scale: CGFloat) {
        let groups = groups.filter { $0 > 0 }
        let count = groups.reduce(0, +)
        guard count > 0 else {
            self.boxes = []
            self.outlines = []
            self.dividers = []
            self.separators = []
            self.width = 0
            return
        }

        let pixels = max(scale, 1)
        let snap: (CGFloat) -> CGFloat = { ($0 * pixels).rounded() / pixels }
        let snapDown: (CGFloat) -> CGFloat = { ($0 * pixels).rounded(.down) / pixels }
        let gaps = CGFloat(count - 1)
        let clusterGaps = CGFloat(groups.count - 1)
        let sharesOutlines = gap <= 0
        let overlap = sharesOutlines ? Self.outlineWidth : 0
        let overlaps = (gaps - clusterGaps) * overlap
        let smallestGap = sharesOutlines ? 0 : Self.minimumGap

        var bar = max(snap(barWidth), Self.minimumBarWidth)
        var space = max(snap(gap), smallestGap)
        var extra = max(snap(clusterGap), 0)

        let total: (CGFloat, CGFloat, CGFloat) -> CGFloat = { bar, space, extra in
            CGFloat(count) * bar + gaps * space + clusterGaps * extra - overlaps
        }

        if total(bar, space, extra) > maxWidth {
            let ratio = maxWidth / total(bar, space, extra)
            bar = max(snapDown(bar * ratio), Self.minimumBarWidth)
            space = max(snapDown(space * ratio), smallestGap)
            extra = max(snapDown(extra * ratio), 0)

            // Boxes stopped at their minimum, so the gaps have to give up the rest.
            if total(bar, space, extra) > maxWidth && gaps > 0 {
                let room = maxWidth - total(bar, 0, extra)
                space = max(snapDown(room / gaps), smallestGap)
            }

            // Rounding down can leave room to spare, so give it back to the boxes.
            let step = 1 / pixels
            while total(bar + step, space, extra) <= maxWidth {
                bar += step
            }
        }

        var rects: [CGRect] = []
        rects.reserveCapacity(count)
        var x: CGFloat = 0
        for (index, size) in groups.enumerated() {
            if index != 0 {
                x += extra + overlap
            }
            for _ in 0..<size {
                rects.append(CGRect(x: x, y: 0, width: bar, height: height))
                x += bar + space - overlap
            }
        }

        var outlines: [CGRect] = []
        var dividers: [CGRect] = []
        var separators: [CGRect] = []
        var start = 0
        for size in groups {
            let cluster = rects[start..<(start + size)]
            if sharesOutlines, let first = cluster.first, let last = cluster.last {
                outlines.append(first.union(last))
                dividers += cluster.dropFirst().map {
                    CGRect(x: $0.minX, y: Self.outlineWidth, width: Self.outlineWidth, height: height - 2 * Self.outlineWidth)
                }
            } else {
                outlines += cluster
            }

            let next = start + size
            if next < rects.count {
                let left = rects[next - 1].maxX
                let room = rects[next].minX - left
                let dot = Self.separatorSize
                if room >= dot + 2 {
                    separators.append(CGRect(x: snap(left + (room - dot) / 2), y: snap((height - dot) / 2), width: dot, height: dot))
                }
            }
            start = next
        }

        self.boxes = rects
        self.outlines = outlines
        self.dividers = dividers
        self.separators = separators
        self.width = x - space + overlap
    }
}
