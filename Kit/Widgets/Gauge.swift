//
//  Gauge.swift
//  Kit
//
//  The mini widget's text on top of a level that fills from the left.
//

import Cocoa

public class MiniGauge: Mini {
    internal var renderScale: CGFloat? = nil
    
    private static let fillAlpha: CGFloat = 0.3
    private static let cornerRadius: CGFloat = 4
    
    private var temperatureSupported: Bool = false
    private var temperatureState: Bool = true
    private var _temperature: String? = nil
    
    public var temperatureEnabled: Bool { self.temperatureSupported && self.temperatureState }
    
    override internal var sidePadding: CGFloat { 2 }
    override internal var defaultAlignment: String { "center" }
    // Sized to leave a margin between the text and the outline.
    override internal var valueSize: CGFloat { self.labelState ? 11 : 14 }
    override internal var valueBaseline: CGFloat { self.labelState ? 2.5 : 4.5 }
    override internal var labelBaseline: CGFloat { 11.5 }
    override internal var leadingWidth: CGFloat {
        self.queue.sync { self._temperature }.map { MeterTemperature.width($0) } ?? 0
    }
    
    private var scale: CGFloat {
        max(self.renderScale ?? self.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1, 1)
    }
    
    public init(title: String, config: NSDictionary?, preview: Bool = false) {
        super.init(title: title, config: config, preview: preview, type: .gauge)
        self.temperatureSupported = config?["Temperature"] as? Bool ?? false
        self.temperatureState = Store.shared.bool(key: "\(self.title)_\(self.type.rawValue)_temperature", defaultValue: self.temperatureState)
        if preview && self.temperatureEnabled {
            self._temperature = MeterTemperature.text(52)
        }
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
        let (value, temperature) = self.queue.sync { (self._value, self._temperature) }
        let dark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let line = CoreBoxLayout.outlineWidth
        
        var origin: CGFloat = 0
        if let temperature {
            origin = MeterTemperature.draw(temperature, at: 0, height: self.frame.height, dark: dark, scale: self.scale)
        }
        // The frame catches up after this draw, so size the box from its contents.
        let box = NSRect(x: origin, y: 0, width: self.meterWidth, height: self.frame.height)
        let inner = box.insetBy(dx: line, dy: line)
        let radius = Self.cornerRadius
        
        let pixel = 1 / self.scale
        var width = (inner.width * CGFloat(min(max(value, 0), 1)) / pixel).rounded() * pixel
        if value > 0 {
            width = max(width, pixel)
        }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: inner, xRadius: radius - line, yRadius: radius - line).addClip()
        NSColor.controlAccentColor.withAlphaComponent(Self.fillAlpha).setFill()
        NSBezierPath(rect: NSRect(x: inner.minX, y: inner.minY, width: width, height: inner.height)).fill()
        NSGraphicsContext.restoreGraphicsState()
        
        (dark ? NSColor.white : NSColor.black).withAlphaComponent(CoreBoxLayout.outlineAlpha).setStroke()
        let outline = NSBezierPath(roundedRect: box.insetBy(dx: line/2, dy: line/2), xRadius: radius - line/2, yRadius: radius - line/2)
        outline.lineWidth = line
        outline.stroke()
        
        NSGraphicsContext.saveGraphicsState()
        let shift = NSAffineTransform()
        shift.translateX(by: origin, yBy: 0)
        shift.concat()
        super.draw(dirtyRect)
        NSGraphicsContext.restoreGraphicsState()
    }
    
    public func setTemperature(_ newValue: Double?) {
        let text = newValue.map { MeterTemperature.text($0) }
        let updated = self.queue.sync { () -> Bool in
            guard self._temperature != text else { return false }
            self._temperature = text
            return true
        }
        if updated {
            self.redraw()
        }
    }
    
    // MARK: - Settings
    
    public override func settings() -> NSView {
        let view = super.settings()
        if self.temperatureSupported, let container = view as? SettingsContainerView {
            container.addArrangedSubview(PreferencesSection([
                PreferencesRow(localizedString("Temperature"), component: switchView(
                    action: #selector(self.toggleTemperature),
                    state: self.temperatureState
                ))
            ]))
        }
        return view
    }
    
    @objc private func toggleTemperature(_ sender: NSControl) {
        self.temperatureState = controlState(sender)
        Store.shared.set(key: "\(self.title)_\(self.type.rawValue)_temperature", value: self.temperatureState)
        if !self.temperatureState {
            self.setTemperature(nil)
        }
    }
}
