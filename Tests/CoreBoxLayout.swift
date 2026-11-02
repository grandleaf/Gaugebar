//
//  CoreBoxLayout.swift
//  Tests
//

import XCTest
@testable import Kit

class CompactSpeedTests: XCTestCase {
    func testDropsThePerSecondSuffix() {
        XCTAssertEqual(Units(bytes: 2_000).getCompactSpeed(), "2 KB")
        XCTAssertEqual(Units(bytes: 2_300_000).getCompactSpeed(), "2.3 MB")
        XCTAssertEqual(Units(bytes: 2_300_000_000).getCompactSpeed(), "2.3 GB")
    }
    
    func testShowsPlainBytesBelowOneKilobyte() {
        XCTAssertEqual(Units(bytes: 0).getCompactSpeed(), "0 B")
        XCTAssertEqual(Units(bytes: 512).getCompactSpeed(), "512 B")
        XCTAssertEqual(Units(bytes: 999).getCompactSpeed(), "999 B")
    }
    
    func testBitsUseALowerCaseUnit() {
        XCTAssertEqual(Units(bytes: 100).getCompactSpeed(base: .bit), "800 b")
        XCTAssertEqual(Units(bytes: 2_000).getCompactSpeed(base: .bit), "16 Kb")
    }
    
    func testOmittingUnitsLeavesTheNumber() {
        XCTAssertEqual(Units(bytes: 512).getCompactSpeed(omitUnits: true), "512")
    }
    
    func testOtherViewsKeepThePerSecondSuffix() {
        XCTAssertEqual(Units(bytes: 2_000).getReadableSpeed(), "2 KB/s")
    }
}

class MiniGaugeTests: XCTestCase {
    private func render(value: Double, scale: CGFloat) -> NSBitmapImageRep {
        let gauge = MiniGauge(title: "GaugeRenderTest", config: nil)
        gauge.renderScale = scale
        gauge.setFrameSize(NSSize(width: 30, height: CoreBoxLayout.boxHeight))
        gauge._value = value
        
        let size = gauge.frame.size
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
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
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
            gauge.draw(NSRect(origin: .zero, size: size))
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
    
    func testUsesItsOwnWidgetTypeAndTheCoreBoxHeight() {
        let gauge = MiniGauge(title: "GaugeRenderTest", config: nil)
        XCTAssertEqual(gauge.type, .gauge)
        XCTAssertEqual(gauge.frame.height, CoreBoxLayout.boxHeight)
        XCTAssertEqual(Mini(title: "GaugeRenderTest", config: nil).type, .mini)
    }
    
    func testFillsFromTheBottomBehindAFaintOutline() {
        for scale: CGFloat in [1, 2] {
            let rep = render(value: 0.5, scale: scale)
            let alpha: (Int, Int) -> CGFloat = { rep.colorAt(x: $0, y: $1)?.alphaComponent ?? 0 }
            let x = Int(scale)
            
            XCTAssertEqual(alpha(0, rep.pixelsHigh / 2), 0.18, accuracy: 0.02, "outline at \(scale)x")
            XCTAssertEqual(alpha(x, rep.pixelsHigh - Int(3 * scale)), 0.3, accuracy: 0.03, "fill at the bottom at \(scale)x")
            XCTAssertEqual(alpha(x, Int(3 * scale)), 0, accuracy: 0.02, "empty at the top at \(scale)x")
        }
    }
    
    func testZeroHasNoFillAndFullFillsTheBox() {
        let empty = render(value: 0, scale: 2)
        XCTAssertEqual(empty.colorAt(x: 2, y: empty.pixelsHigh - 6)!.alphaComponent, 0, accuracy: 0.02)
        let full = render(value: 1, scale: 2)
        XCTAssertEqual(full.colorAt(x: 2, y: 6)!.alphaComponent, 0.3, accuracy: 0.03)
    }
    
    func testVerySmallValuesStillShowOnePixel() {
        let rep = render(value: 0.001, scale: 2)
        XCTAssertEqual(rep.colorAt(x: 2, y: rep.pixelsHigh - 3)!.alphaComponent, 0.3, accuracy: 0.03)
    }
}

class CoreBoxLayoutTests: XCTestCase {
    private func layout(_ groups: [Int], bar: CGFloat = 9, gap: CGFloat = 0, cluster: CGFloat = 11, max: CGFloat = 300, scale: CGFloat = 2) -> CoreBoxLayout {
        CoreBoxLayout(groups: groups, barWidth: bar, gap: gap, clusterGap: cluster, maxWidth: max, height: 18, scale: scale)
    }

    func testDefaultsForThisMac() {
        let l = layout([4, 12])
        XCTAssertEqual(l.boxes.count, 16)
        XCTAssertEqual(l.width, 141)
        XCTAssertEqual(l.boxes[1].minX, l.boxes[0].maxX - CoreBoxLayout.outlineWidth, "shares one outline")
        XCTAssertEqual(l.boxes[4].minX - l.boxes[3].maxX, 11, "clusters stay apart")
    }

    func testSharedOutlinesFrameEachCluster() {
        let l = layout([4, 12])
        XCTAssertEqual(l.outlines.count, 2)
        XCTAssertEqual(l.outlines[0].minX, l.boxes[0].minX)
        XCTAssertEqual(l.outlines[0].maxX, l.boxes[3].maxX)
        XCTAssertEqual(l.outlines[1].maxX, l.width)
        XCTAssertEqual(l.dividers.count, 14)
        XCTAssertEqual(l.dividers[0].minX, l.boxes[1].minX)
        XCTAssertEqual(l.dividers[0].height, 16, "stops at the outline")
    }
    
    func testSeparatorNeedsRoomInTheGap() {
        let wide = layout([4, 12])
        XCTAssertEqual(wide.separators.count, 1)
        XCTAssertEqual(wide.separators[0].midX, (wide.boxes[3].maxX + wide.boxes[4].minX) / 2)
        XCTAssertEqual(wide.separators[0].midY, 9)
        
        XCTAssertTrue(layout([4, 12], cluster: 4).separators.isEmpty)
        XCTAssertTrue(layout([16]).separators.isEmpty)
    }

    func testTotalBoxStandsApartFromTheClusters() {
        let l = layout([1, 4, 12])
        XCTAssertEqual(l.boxes.count, 17)
        XCTAssertEqual(l.width, 161)
        XCTAssertEqual(l.outlines.count, 3)
        XCTAssertEqual(l.outlines[0], l.boxes[0])
        XCTAssertEqual(l.dividers.count, 14)
        XCTAssertEqual(l.separators.count, 2)
        XCTAssertEqual(l.boxes[1].minX - l.boxes[0].maxX, 11)
        XCTAssertEqual(l.boxes[5].minX - l.boxes[4].maxX, 11)
    }
    
    func testPositiveGapKeepsBoxesApart() {
        let l = layout([4, 12], gap: 4, cluster: 7)
        XCTAssertEqual(l.width, 211)
        XCTAssertEqual(l.outlines.count, 16)
        XCTAssertTrue(l.dividers.isEmpty)
        XCTAssertEqual(l.boxes[1].minX - l.boxes[0].maxX, 4)
        XCTAssertEqual(l.boxes[4].minX - l.boxes[3].maxX, 11)
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
                let l = layout(split, gap: 4, scale: scale)
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
        let l = layout([128], gap: 4, max: 100)
        XCTAssertEqual(l.boxes[0].width, CoreBoxLayout.minimumBarWidth)
        XCTAssertEqual(l.width, 128 * 3 + 127)
    }

    func testSharedOutlinesFitTheLimitAndStayOrdered() {
        for count in 2...128 {
            let split = [count / 4, count - count / 4]
            for scale: CGFloat in [1, 2, 3] {
                let l = layout(split, max: 300, scale: scale)
                XCTAssertEqual(l.boxes.count, count)
                XCTAssertEqual(l.width, l.boxes.last!.maxX)
                for (a, b) in zip(l.boxes, l.boxes.dropFirst()) {
                    XCTAssertGreaterThan(b.minX, a.minX, "count \(count)")
                    XCTAssertGreaterThanOrEqual(b.minX - a.maxX, -CoreBoxLayout.outlineWidth - 0.0001, "count \(count)")
                }
                if count * 2 + 3 <= 300 {
                    XCTAssertLessThanOrEqual(l.width, 300, "count \(count)")
                }
            }
        }
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
    
    private func render(scale: CGFloat, appearance: NSAppearance.Name, values: [[ColorValue]], groups: [Int] = [1, 1], temperature: Double? = nil) -> NSBitmapImageRep {
        let chart = BarChart(title: "CoreBoxRenderTest", config: ["Core boxes": true])
        chart.renderScale = scale
        chart.setCoreGroups(groups)
        chart.setValue(values)
        chart.setCoreTemperature(temperature)
        
        let size = chart.frame.size
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(120 * scale),
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
    
    func testSharedDividerIsOneFaintLine() {
        for scale: CGFloat in [1, 2] {
            let rep = render(scale: scale, appearance: .aqua, values: [[ColorValue(0)], [ColorValue(0)]], groups: [2])
            let y = rep.pixelsHigh / 2
            let alpha: (Int) -> CGFloat = { rep.colorAt(x: $0, y: y)?.alphaComponent ?? 0 }
            let shared = Int(8 * scale)
            let stroke = Int(scale)
            
            XCTAssertEqual(alpha(shared - 1), 0, accuracy: 0.02, "inside the first box at \(scale)x")
            for x in shared..<(shared + stroke) {
                XCTAssertEqual(alpha(x), 0.18, accuracy: 0.02, "shared line at \(scale)x")
            }
            XCTAssertEqual(alpha(shared + stroke), 0, accuracy: 0.02, "inside the second box at \(scale)x")
        }
    }
    
    func testSeparatorDotIsCenteredBetweenClusters() {
        for scale: CGFloat in [1, 2] {
            let rep = render(scale: scale, appearance: .aqua, values: [[ColorValue(0)], [ColorValue(0)]])
            let alpha: (CGFloat, CGFloat) -> CGFloat = { x, y in
                rep.colorAt(x: Int(x * scale), y: Int(y * scale))?.alphaComponent ?? 0
            }
            XCTAssertEqual(alpha(14.5, 9.5), 0.4, accuracy: 0.02, "dot center at \(scale)x")
            XCTAssertEqual(alpha(14.5, 5), 0, accuracy: 0.02, "above the dot at \(scale)x")
            XCTAssertEqual(alpha(11, 9.5), 0, accuracy: 0.02, "left of the dot at \(scale)x")
        }
    }
    
    func testTemperatureTextDropsTheUnitLetter() {
        for value in [9.0, 49.4, 100.0] {
            let text = BarChart.coreTemperatureText(value)
            XCTAssertTrue(text.hasSuffix("°"), text)
            XCTAssertFalse(text.contains(where: { $0.isLetter }), text)
        }
    }
    
    func testTemperatureSpaceStaysTheSameForAnyDigits() {
        let width = BarChart.coreTemperatureWidth("100°")
        XCTAssertGreaterThan(width, 0)
        XCTAssertEqual(BarChart.coreTemperatureWidth("49°"), width)
        XCTAssertEqual(BarChart.coreTemperatureWidth("9°"), width)
    }
    
    func testTemperatureSitsLeftOfTheBoxes() {
        let idle = [[ColorValue(0)], [ColorValue(0)]]
        for scale: CGFloat in [1, 2] {
            let plain = render(scale: scale, appearance: .aqua, values: idle)
            let shown = render(scale: scale, appearance: .aqua, values: idle, temperature: 49)
            let y = plain.pixelsHigh / 2
            let width = BarChart.coreTemperatureWidth("49°")
            let boxStart = Int((width + BarChart.coreTemperatureGap) * scale)
            
            XCTAssertEqual(plain.colorAt(x: 0, y: y)!.alphaComponent, 0.8, accuracy: 0.02, "boxes start at the edge without it")
            XCTAssertEqual(shown.colorAt(x: boxStart, y: y)!.alphaComponent, 0.8, accuracy: 0.02, "boxes move right at \(scale)x")
            XCTAssertEqual(shown.colorAt(x: boxStart - 1, y: y)!.alphaComponent, 0, accuracy: 0.02, "gap before the boxes at \(scale)x")
            
            let ink = (0..<Int(width * scale)).flatMap { x in
                (0..<shown.pixelsHigh).map { shown.colorAt(x: x, y: $0)!.alphaComponent }
            }
            XCTAssertGreaterThan(ink.max() ?? 0, 0.5, "text drawn at \(scale)x")
        }
    }
    
    func testTemperatureTextFollowsTheMenuBarAppearance() {
        let idle = [[ColorValue(0)], [ColorValue(0)]]
        let darkest: (NSAppearance.Name) -> (red: CGFloat, alpha: CGFloat) = { appearance in
            let rep = self.render(scale: 2, appearance: appearance, values: idle, temperature: 49)
            let width = Int(BarChart.coreTemperatureWidth("49°") * 2)
            var best: (red: CGFloat, alpha: CGFloat) = (0, 0)
            for x in 0..<width {
                for y in 0..<rep.pixelsHigh {
                    if let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.alphaComponent > best.alpha {
                        best = (color.redComponent, color.alphaComponent)
                    }
                }
            }
            return best
        }
        XCTAssertLessThan(darkest(.aqua).red, 0.2)
        XCTAssertGreaterThan(darkest(.darkAqua).red, 0.8)
    }
    
    func testSingleBoxIsOutlinedWithAnEmptyTop() {
        let rep = render(scale: 2, appearance: .aqua, values: [[ColorValue(0.5, color: .blue)]], groups: [1])
        let x = 9
        XCTAssertEqual(rep.colorAt(x: x, y: 0)!.alphaComponent, 0.8, accuracy: 0.02, "outline")
        XCTAssertEqual(rep.colorAt(x: x, y: 8)!.alphaComponent, 0, accuracy: 0.02, "empty above the fill")
        XCTAssertGreaterThan(rep.colorAt(x: x, y: rep.pixelsHigh - 8)!.usingColorSpace(.deviceRGB)!.blueComponent, 0.9, "fill")
    }
    
    func testMiniKeepsTwoDigitRoomAndGrowsOnlyAtOneHundred() {
        let two = Mini.labelledWidth(value: "47%", label: "RAM")
        XCTAssertEqual(Mini.labelledWidth(value: "4%", label: "RAM"), two)
        XCTAssertEqual(Mini.labelledWidth(value: "88%", label: "RAM"), two)
        XCTAssertGreaterThan(Mini.labelledWidth(value: "100%", label: "RAM"), two)
        XCTAssertLessThan(two, 31)
    }
    
    func testMiniMakesRoomForALongLabelUpToTheOldLimit() {
        let long = String(repeating: "W", count: 40)
        XCTAssertEqual(Mini.labelledWidth(value: "4%", label: long), 31)
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
