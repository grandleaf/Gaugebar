//
//  Gauge.swift
//  Kit
//
//  The mini widget's text on top of a level that fills from the bottom.
//

import Cocoa

public class MiniGauge: Mini {
    internal var renderScale: CGFloat? = nil
    
    private static let fillAlpha: CGFloat = 0.3
    private static let outlineAlpha: CGFloat = 0.18
    
    override internal var sidePadding: CGFloat { 2 }
    override internal var defaultAlignment: String { "center" }
    
    private var scale: CGFloat {
        max(self.renderScale ?? self.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1, 1)
    }
    
    public init(title: String, config: NSDictionary?, preview: Bool = false) {
        super.init(title: title, config: config, preview: preview, type: .gauge)
        self.updateFrame()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // Same height and position as the CPU boxes, so they line up.
    private func updateFrame() {
        let height = CoreBoxLayout.boxHeight
        let y = (((Constants.Widget.height - height) / 2) * self.scale).rounded() / self.scale
        if self.frame.height != height || self.frame.origin.y != y {
            self.frame = NSRect(x: self.frame.origin.x, y: y, width: self.frame.width, height: height)
        }
    }
    
    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        self.updateFrame()
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        let value = self.queue.sync { self._value }
        let dark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let line = CoreBoxLayout.outlineWidth
        let box = NSRect(origin: .zero, size: self.frame.size)
        let inner = box.insetBy(dx: line, dy: line)
        
        let pixel = 1 / self.scale
        var height = (inner.height * CGFloat(min(max(value, 0), 1)) / pixel).rounded() * pixel
        if value > 0 {
            height = max(height, pixel)
        }
        NSColor.controlAccentColor.withAlphaComponent(Self.fillAlpha).setFill()
        NSBezierPath(rect: NSRect(x: inner.minX, y: inner.minY, width: inner.width, height: height)).fill()
        
        (dark ? NSColor.white : NSColor.black).withAlphaComponent(Self.outlineAlpha).setStroke()
        let outline = NSBezierPath(rect: box.insetBy(dx: line/2, dy: line/2))
        outline.lineWidth = line
        outline.stroke()
        
        // The text is laid out for the shorter mini frame, so keep it where that frame would put it.
        NSGraphicsContext.saveGraphicsState()
        let shift = NSAffineTransform()
        shift.translateX(by: 0, yBy: Constants.Widget.margin.y - self.frame.origin.y)
        shift.concat()
        super.draw(dirtyRect)
        NSGraphicsContext.restoreGraphicsState()
    }
}
