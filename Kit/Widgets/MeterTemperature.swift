//
//  MeterTemperature.swift
//  Kit
//
//  A temperature and a dot on the left of a meter, so they read as one unit.
//

import Cocoa

internal enum MeterTemperature {
    private static let gap: CGFloat = 4
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    
    static func text(_ value: Double) -> String {
        temperature(value, fractionDigits: 1)
    }
    
    // Always room for four digits, so going from 99.9° to 100.0° doesn't move the meter.
    static func textWidth(_ text: String) -> CGFloat {
        let sample = "0000" + text.filter { !$0.isNumber }
        return NSAttributedString(string: sample, attributes: [.font: self.font]).size().width.rounded(.up)
    }
    
    /// Space taken on the left of the meter.
    static func width(_ text: String) -> CGFloat {
        self.textWidth(text) + self.gap + CoreBoxLayout.separatorSize + self.gap
    }
    
    /// Returns where the meter starts.
    static func draw(_ text: String, at x: CGFloat, height: CGFloat, dark: Bool, scale: CGFloat) -> CGFloat {
        let string = NSAttributedString(string: text, attributes: [
            .font: self.font,
            .foregroundColor: dark ? NSColor.white : NSColor.textColor
        ])
        
        let pixels = max(scale, 1)
        let snap: (CGFloat) -> CGFloat = { ($0 * pixels).rounded() / pixels }
        let textEnd = x + self.textWidth(text)
        let bottom = (height - self.font.capHeight) / 2 + self.font.descender
        string.draw(at: NSPoint(x: snap(textEnd - string.size().width), y: snap(bottom)))
        
        let dot = CoreBoxLayout.separatorSize
        (dark ? NSColor.white : NSColor.black).withAlphaComponent(CoreBoxLayout.separatorAlpha).setFill()
        NSBezierPath(ovalIn: NSRect(x: snap(textEnd + self.gap), y: snap((height - dot) / 2), width: dot, height: dot)).fill()
        
        return x + self.width(text)
    }
}
