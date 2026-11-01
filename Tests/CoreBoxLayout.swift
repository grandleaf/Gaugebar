//
//  CoreBoxLayout.swift
//  Tests
//

import XCTest
@testable import Kit

class CoreBoxLayoutTests: XCTestCase {
    private func layout(_ groups: [Int], bar: CGFloat = 9, gap: CGFloat = 4, cluster: CGFloat = 7, max: CGFloat = 300, scale: CGFloat = 2) -> CoreBoxLayout {
        CoreBoxLayout(groups: groups, barWidth: bar, gap: gap, clusterGap: cluster, maxWidth: max, height: 18, scale: scale)
    }

    func testDefaultsForThisMac() {
        let l = layout([4, 12])
        XCTAssertEqual(l.boxes.count, 16)
        XCTAssertEqual(l.width, 211)
        XCTAssertEqual(l.boxes[1].minX - l.boxes[0].minX, 13)
        XCTAssertEqual(l.boxes[4].minX - l.boxes[3].minX, 20)
    }

    func testEmptyAndSingle() {
        XCTAssertEqual(layout([]).width, 0)
        XCTAssertEqual(layout([0]).boxes.count, 0)
        let one = layout([1])
        XCTAssertEqual(one.boxes.count, 1)
        XCTAssertEqual(one.width, 9)
    }

    func testEveryCoreCountStaysSeparateAndOrdered() {
        for count in 1...64 {
            let split = count > 1 ? [count - count / 4, count / 4] : [count]
            for scale: CGFloat in [1, 2] {
                let l = layout(split, scale: scale)
                XCTAssertEqual(l.boxes.count, count)
                XCTAssertGreaterThanOrEqual(l.boxes[0].width, CoreBoxLayout.minimumBarWidth)
                for (a, b) in zip(l.boxes, l.boxes.dropFirst()) {
                    XCTAssertGreaterThanOrEqual(b.minX - a.maxX, CoreBoxLayout.minimumGap, "count \(count)")
                }
            }
        }
    }

    func testManyCoresFitTheLimit() {
        XCTAssertLessThanOrEqual(layout([24, 8]).width, 300)
        XCTAssertLessThanOrEqual(layout([48, 16]).width, 300)
    }

    func testReadableMinimumWinsOverTheLimit() {
        let l = layout([128], max: 100)
        XCTAssertEqual(l.boxes[0].width, CoreBoxLayout.minimumBarWidth)
        XCTAssertEqual(l.width, 128 * 3 + 127)
    }

    func testBoxesLandOnDevicePixels() {
        for scale: CGFloat in [1, 2, 3] {
            for box in layout([24, 8], bar: 7.3, gap: 2.6, cluster: 3.1, max: 260, scale: scale).boxes {
                XCTAssertEqual((box.minX * scale).rounded(), box.minX * scale, accuracy: 0.0001)
                XCTAssertEqual((box.width * scale).rounded(), box.width * scale, accuracy: 0.0001)
            }
        }
    }
    
    // MARK: - Rendering
    
    private func render(scale: CGFloat, appearance: NSAppearance.Name, values: [[ColorValue]]) -> NSBitmapImageRep {
        let chart = BarChart(title: "CoreBoxRenderTest", config: ["Core boxes": true])
        chart.renderScale = scale
        chart.setCoreGroups([1, 1])
        chart.setValue(values)
        
        let size = chart.frame.size
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(60 * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: scale, y: scale)
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
            chart.draw(NSRect(origin: .zero, size: size))
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
    
    func testCoreBoxesAreTallerOnlyWhileShown() {
        let chart = BarChart(title: "CoreBoxRenderTest", config: ["Core boxes": true])
        chart.renderScale = 2
        let plain = chart.frame
        
        chart.setCoreGroups([1, 1])
        XCTAssertEqual(chart.frame.height, CoreBoxLayout.boxHeight)
        XCTAssertEqual(chart.frame.midY, plain.midY, "stays centered")
        
        chart.setCoreGroups(nil)
        XCTAssertEqual(chart.frame, plain)
    }
    
    func testCoreFrameLandsOnDevicePixels() {
        for scale: CGFloat in [1, 2, 3] {
            let chart = BarChart(title: "CoreBoxRenderTest", config: ["Core boxes": true])
            chart.renderScale = scale
            chart.setCoreGroups([1, 1])
            let y = chart.frame.origin.y * scale
            XCTAssertEqual(y.rounded(), y, accuracy: 0.0001)
        }
    }
    
    func testOutlinesAreCrispAtOneAndTwoTimes() {
        for scale: CGFloat in [1, 2] {
            let rep = render(scale: scale, appearance: .aqua, values: [[ColorValue(0)], [ColorValue(0)]])
            let y = rep.pixelsHigh / 2
            let alpha: (Int) -> CGFloat = { rep.colorAt(x: $0, y: y)?.alphaComponent ?? 0 }
            let stroke = Int(scale)
            XCTAssertEqual(alpha(0), 0.8, accuracy: 0.02, "outline at \(scale)x")
            XCTAssertEqual(alpha(stroke - 1), 0.8, accuracy: 0.02, "outline at \(scale)x")
            XCTAssertEqual(alpha(stroke), 0, accuracy: 0.02, "inside the box at \(scale)x")
        }
    }
    
    func testIdleBoxIsVisibleInLightAndDark() {
        let y = 10
        let light = render(scale: 2, appearance: .aqua, values: [[ColorValue(0)], [ColorValue(0)]]).colorAt(x: 0, y: y)!
        let dark = render(scale: 2, appearance: .darkAqua, values: [[ColorValue(0)], [ColorValue(0)]]).colorAt(x: 0, y: y)!
        XCTAssertLessThan(light.usingColorSpace(.deviceRGB)!.redComponent, 0.05)
        XCTAssertGreaterThan(dark.usingColorSpace(.deviceRGB)!.redComponent, 0.95)
    }
    
    func testSegmentsStackFromTheBottom() {
        let values = [[ColorValue(0.25, color: .red), ColorValue(0.25, color: .blue)], [ColorValue(0)]]
        let rep = render(scale: 2, appearance: .aqua, values: values)
        let x = 10
        let color: (Int) -> NSColor = { rep.colorAt(x: x, y: rep.pixelsHigh - $0)!.usingColorSpace(.deviceRGB)! }
        let height = rep.pixelsHigh
        let inner = height - 4
        
        XCTAssertGreaterThan(color(4).redComponent, 0.9, "system at the bottom")
        XCTAssertGreaterThan(color(2 + inner * 3 / 8).blueComponent, 0.9, "user above it")
        XCTAssertEqual(color(2 + inner * 3 / 4).alphaComponent, 0, accuracy: 0.02, "empty above the fill")
    }
}
