//
//  Icon.swift
//  Stats
//
//  Created by Serhiy Mytrovtsiy on 05/10/2026.
//  Using Swift 6.0.
//  Running on macOS 27.0.
//
//  Copyright © 2026 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa

/// One fan's reading, with the limits the SMC reports for it.
public struct FanSpeed {
    public let rpm: Double
    public let min: Double
    public let max: Double

    public init(rpm: Double, min: Double, max: Double) {
        self.rpm = rpm
        self.min = min
        self.max = max
    }

    /// Blades to fill: 0 while the fan is stopped, then 1 at its slowest up to 4 at `fullAt` of its maximum.
    /// macOS rarely runs the fans near their maximum, so "full" is a chosen share of it.
    public func blades(fullAt: Double) -> Int {
        // Lower readings are a fan winding down, not spinning.
        guard self.rpm >= 100 else { return 0 }
        let full = self.max * fullAt
        let slowest = Swift.max(self.min, 0)
        guard full > slowest else { return 4 }
        let share = (self.rpm - slowest) / (full - slowest)
        if share >= 1 { return 4 }
        return 1 + Swift.min(2, Swift.max(0, Int(share * 3)))
    }
}

public class IconWidget: WidgetWrapper {
    private let fanAnimation: Bool
    private var animationState: Bool = true
    private var fanLevelState: Bool = true
    // At 100% CPU, an M3 Max runs its fans at about 64% of their maximum, so that counts as full.
    private var fullSpeedState: Int = 60

    private var fans: [FanSpeed] = []
    private let imageView: NSImageView = NSImageView(frame: .zero)
    private var fanView: FanBladesView? = nil

    private static let fullSpeedOptions: [Int] = [40, 50, 60, 70, 80, 90, 100]

    public init(title: String, config: NSDictionary, icon: NSImage?, preview: Bool = false) {
        self.fanAnimation = config["Fan animation"] as? Bool ?? false

        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let image = icon?.withSymbolConfiguration(configuration) ?? icon
        let width = ceil(image?.size.width ?? 16)

        super.init(.icon, title: title, frame: CGRect(
            x: 0,
            y: Constants.Widget.margin.y,
            width: width + (2*Constants.Widget.margin.x),
            height: Constants.Widget.height - (2*Constants.Widget.margin.y)
        ))

        if self.fanAnimation {
            let view = FanBladesView(frame: self.bounds, configuration: configuration)
            view.autoresizingMask = [.width, .height]
            self.addSubview(view)
            self.fanView = view
        } else {
            self.imageView.frame = self.bounds
            self.imageView.autoresizingMask = [.width, .height]
            self.imageView.image = image
            self.imageView.symbolConfiguration = configuration
            self.imageView.contentTintColor = .textColor
            self.imageView.imageScaling = .scaleNone
            self.imageView.imageAlignment = .alignCenter
            self.addSubview(self.imageView)
        }

        if !preview && self.fanAnimation {
            self.animationState = Store.shared.bool(key: "\(self.title)_\(self.type.rawValue)_animation", defaultValue: self.animationState)
            self.fanLevelState = Store.shared.bool(key: "\(self.title)_\(self.type.rawValue)_fanLevel", defaultValue: self.fanLevelState)
            self.fullSpeedState = Store.shared.int(key: "\(self.title)_\(self.type.rawValue)_fullSpeed", defaultValue: self.fullSpeedState)
        }
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The fastest fan decides, so one busy fan is enough to show it.
    internal var blades: Int? {
        guard !self.fans.isEmpty else { return nil }
        let fullAt = Double(self.fullSpeedState) / 100
        return self.fans.map { $0.blades(fullAt: fullAt) }.max()
    }

    public func setFans(_ fans: [FanSpeed]) {
        DispatchQueue.main.async(execute: {
            self.fans = fans
            self.update()
        })
    }

    private func update() {
        let blades = self.blades
        // Without fans, or with the level off, keep the plain filled fan.
        self.fanView?.filled = self.fanLevelState ? (blades ?? 4) : 4
        self.updateAnimation(blades: blades ?? 0)
    }

    // Faster fans turn the icon faster. A full turn takes this long, in seconds.
    // At 15 steps a second, the fastest turn moves a blade 15° per step, well under the 45° where a
    // fully filled fan would seem to turn backwards.
    private static func turnDuration(blades: Int) -> Double {
        [4.0, 3.0, 2.2, 1.6][Swift.min(Swift.max(blades, 1), 4) - 1]
    }
    
    // A timer turns the fan in steps. Core Animation's smooth 60 frames a second made
    // WindowServer redraw the menu bar constantly, adding about 8% of a core.
    private static let stepsPerSecond: Double = 15
    private var spinTimer: Timer? = nil
    private var spinStep: CGFloat = 0
    private var spinAngle: CGFloat = 0
    
    private func updateAnimation(blades: Int) {
        guard let view = self.fanView else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard self.animationState, blades > 0, !reduceMotion else {
            self.stopSpinning()
            return
        }
        
        view.wantsLayer = true
        self.spinStep = 360 / CGFloat(Self.turnDuration(blades: blades) * Self.stepsPerSecond)
        guard self.spinTimer == nil else { return }
        let timer = Timer(timeInterval: 1 / Self.stepsPerSecond, repeats: true) { [weak self] _ in
            self?.turn()
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        self.spinTimer = timer
    }
    
    deinit {
        self.spinTimer?.invalidate()
    }
    
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Taken out of the menu bar: stop, and pick up again on the next fan reading.
        if self.window == nil {
            self.stopSpinning()
        }
    }
    
    private func turn() {
        guard let layer = self.fanView?.layer else { return }
        // Nothing to turn while the menu bar is hidden or covered.
        guard self.window?.occlusionState.contains(.visible) == true else { return }
        // Clockwise, the way the blades sweep.
        self.spinAngle = (self.spinAngle - self.spinStep).truncatingRemainder(dividingBy: 360)
        self.setRotation(self.spinAngle, on: layer)
    }
    
    private func stopSpinning() {
        self.spinTimer?.invalidate()
        self.spinTimer = nil
        if self.spinAngle != 0, let layer = self.fanView?.layer {
            self.spinAngle = 0
            self.setRotation(0, on: layer)
        }
    }
    
    private func setRotation(_ degrees: CGFloat, on layer: CALayer) {
        // The view's layer turns around its corner, so shift to its center first.
        let x = layer.bounds.width * (0.5 - layer.anchorPoint.x)
        let y = layer.bounds.height * (0.5 - layer.anchorPoint.y)
        var transform = CATransform3DMakeTranslation(x, y, 0)
        transform = CATransform3DRotate(transform, degrees * .pi / 180, 0, 0, 1)
        transform = CATransform3DTranslate(transform, -x, -y, 0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = transform
        CATransaction.commit()
    }
    
    // MARK: - Settings

    public override func settings() -> NSView {
        guard self.fanAnimation else { return NSView() }
        let view = SettingsContainerView()

        view.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Fill blades by fan speed"), component: switchView(
                action: #selector(self.toggleFanLevel),
                state: self.fanLevelState
            )),
            PreferencesRow(localizedString("All blades filled at"), component: selectView(
                action: #selector(self.changeFullSpeed),
                items: Self.fullSpeedOptions.map { KeyValue_t(key: "\($0)", value: "\($0)% of max speed") },
                selected: "\(self.fullSpeedState)"
            )),
            PreferencesRow(localizedString("Animate icon"), component: switchView(
                action: #selector(self.toggleAnimation),
                state: self.animationState
            ))
        ]))

        return view
    }

    @objc private func toggleFanLevel(_ sender: NSControl) {
        self.fanLevelState = controlState(sender)
        Store.shared.set(key: "\(self.title)_\(self.type.rawValue)_fanLevel", value: self.fanLevelState)
        self.update()
    }

    @objc private func changeFullSpeed(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let value = Int(raw) else { return }
        self.fullSpeedState = value
        Store.shared.set(key: "\(self.title)_\(self.type.rawValue)_fullSpeed", value: value)
        self.update()
    }

    @objc private func toggleAnimation(_ sender: NSControl) {
        self.animationState = controlState(sender)
        Store.shared.set(key: "\(self.title)_\(self.type.rawValue)_animation", value: self.animationState)
        self.update()
    }
}

/// The fan symbol with some of its blades filled and the rest outlined.
internal final class FanBladesView: NSView {
    private let configuration: NSImage.SymbolConfiguration
    private var cache: (dark: Bool, outline: NSImage, fill: NSImage)? = nil

    /// Blades filled, 0 to 4: top right, then bottom left, so two filled blades sit opposite, then bottom right and top left.
    var filled: Int = 4 {
        didSet {
            if oldValue != self.filled { self.needsDisplay = true }
        }
    }

    // The symbol's blades each sit in one quarter, so a quarter-circle cut takes exactly one blade.
    // Quarters as start angles, counterclockwise from the right, in fill order. Two opposite blades
    // keep the fan balanced, so it doesn't look lopsided while it spins.
    private static let quarters: [CGFloat] = [0, 180, 270, 90]
    // Radius of the hub, as a share of the symbol's width.
    private static let hubShare: CGFloat = 0.2

    init(frame: NSRect, configuration: NSImage.SymbolConfiguration) {
        self.configuration = configuration
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func symbols(dark: Bool) -> (outline: NSImage, fill: NSImage)? {
        if let cache = self.cache, cache.dark == dark { return (cache.outline, cache.fill) }
        let color = dark ? NSColor.white : NSColor.black
        let configuration = self.configuration.applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let outline = NSImage(systemSymbolName: "fanblades", accessibilityDescription: nil)?.withSymbolConfiguration(configuration),
              let fill = NSImage(systemSymbolName: "fanblades.fill", accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else { return nil }
        self.cache = (dark, outline, fill)
        return (outline, fill)
    }

    override func draw(_ dirtyRect: NSRect) {
        let dark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        guard let (outline, fill) = self.symbols(dark: dark) else { return }

        let scale = max(self.window?.backingScaleFactor ?? 2, 1)
        let snap: (CGFloat) -> CGFloat = { ($0 * scale).rounded() / scale }
        let size = fill.size
        let rect = NSRect(x: snap((self.bounds.width - size.width) / 2), y: snap((self.bounds.height - size.height) / 2), width: size.width, height: size.height)

        let filled = min(max(self.filled, 0), 4)
        if filled == 4 {
            fill.draw(in: rect)
            return
        }
        let center = NSPoint(x: rect.midX, y: rect.midY)
        guard filled > 0 else {
            outline.draw(in: rect)
            return
        }

        // The hub would read as a broken ring if cut, so it comes whole from the filled fan.
        let hub = rect.width * Self.hubShare
        let hubRect = NSRect(x: center.x - hub, y: center.y - hub, width: hub * 2, height: hub * 2)
        NSGraphicsContext.saveGraphicsState()
        let aroundHub = NSBezierPath(rect: self.bounds)
        aroundHub.appendOval(in: hubRect)
        aroundHub.windingRule = .evenOdd
        aroundHub.addClip()
        outline.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        // A slight overlap hides the hairline where the hub meets a filled blade.
        NSBezierPath(ovalIn: hubRect.insetBy(dx: -0.5, dy: -0.5)).addClip()
        fill.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()

        let radius = max(rect.width, rect.height)
        for start in Self.quarters.prefix(filled) {
            NSGraphicsContext.saveGraphicsState()
            let wedge = NSBezierPath()
            wedge.move(to: center)
            wedge.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: start + 90, clockwise: false)
            wedge.close()
            wedge.addClip()
            aroundHub.addClip()
            fill.draw(in: rect)
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}
