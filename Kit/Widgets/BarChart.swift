//
//  BarChart.swift
//  Kit
//
//  Created by Serhiy Mytrovtsiy on 26/04/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa

public class BarChart: WidgetWrapper {
    private var labelState: Bool = false
    private var boxState: Bool = true
    private var frameState: Bool = false
    public var colorState: SColor = .systemAccent
    private var colors: [SColor] = SColor.allCases
    
    private var _value: [[ColorValue]] = [[]]
    private var _pressureLevel: RAMPressure = .normal
    private var _colorZones: colorZones = (0.6, 0.8)
    
    private var boxSettingsView: NSSwitch? = nil
    private var frameSettingsView: NSSwitch? = nil
    
    private var coreBoxesSupported: Bool = false
    private var coreSettingsSupported: Bool = true
    private var coreBoxesState: Bool = true
    private var coreStackState: Bool = true
    private var coreTemperatureState: Bool = true
    private var coreBarWidth: Int = 9
    private var coreGap: Int = 0
    private var coreClusterGap: Int = 11
    private var coreMaxWidth: Int = 300
    private var _coreGroups: [Int]? = nil
    private var _coreTemperature: String? = nil
    internal var renderScale: CGFloat? = nil
    
    public var coreBoxesEnabled: Bool { self.coreBoxesSupported && self.coreBoxesState }
    public var coreStackEnabled: Bool { self.coreStackState }
    internal var showsCoreBoxes: Bool { self.queue.sync { self._coreGroups != nil } }
    public var coreTemperatureEnabled: Bool { self.coreTemperatureState }
    
    internal static let coreTemperatureGap: CGFloat = 4
    private static let coreTemperatureFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    
    public var NSLabelCharts: [NSAttributedString] = []
    
    public init(title: String, config: NSDictionary?, preview: Bool = false) {
        var widgetTitle: String = title
        var previewCoreGroups: [Int]? = nil
        
        if config != nil {
            var configuration = config!
            if let titleFromConfig = config!["Title"] as? String {
                widgetTitle = titleFromConfig
            }
            
            if preview {
                if let previewConfig = config!["Preview"] as? NSDictionary {
                    configuration = previewConfig
                    if let value = configuration["Value"] as? String {
                        self._value = value.split(separator: ",").map{ ([ColorValue(Double($0) ?? 0)]) }
                    }
                    if let groups = configuration["Core groups"] as? String {
                        previewCoreGroups = groups.split(separator: ",").compactMap { Int($0) }
                    }
                }
            }
            
            if let label = configuration["Label"] as? Bool {
                self.labelState = label
            }
            if let box = configuration["Box"] as? Bool {
                self.boxState = box
            }
            if let coreBoxes = config!["Core boxes"] as? Bool {
                self.coreBoxesSupported = coreBoxes
            }
            if let coreSettings = config!["Core settings"] as? Bool {
                self.coreSettingsSupported = coreSettings
            }
            if let unsupportedColors = configuration["Unsupported colors"] as? [String] {
                self.colors = self.colors.filter{ !unsupportedColors.contains($0.key) }
            }
            if let color = configuration["Color"] as? String {
                if let defaultColor = self.colors.first(where: { $0.key == color }) {
                    self.colorState = defaultColor
                }
            }
        }
        
        super.init(.barChart, title: widgetTitle, frame: CGRect(
            x: Constants.Widget.margin.x,
            y: Constants.Widget.margin.y,
            width: Constants.Widget.width + (2*Constants.Widget.margin.x),
            height: Constants.Widget.height - (2*Constants.Widget.margin.y)
        ))
        
        self.canDrawConcurrently = true
        
        self.boxState = Store.shared.bool(key: "\(self.title)_\(self.type.rawValue)_box", defaultValue: self.boxState)
        self.frameState = Store.shared.bool(key: "\(self.title)_\(self.type.rawValue)_frame", defaultValue: self.frameState)
        self.labelState = Store.shared.bool(key: "\(self.title)_\(self.type.rawValue)_label", defaultValue: self.labelState)
        self.colorState = SColor.fromString(Store.shared.string(key: "\(self.title)_\(self.type.rawValue)_color", defaultValue: self.colorState.key))
        self.coreBoxesState = Store.shared.bool(key: "\(self.title)_\(self.type.rawValue)_coreBoxes", defaultValue: self.coreBoxesState)
        self.coreStackState = Store.shared.bool(key: "\(self.title)_\(self.type.rawValue)_coreStack", defaultValue: self.coreStackState)
        self.coreTemperatureState = Store.shared.bool(key: "\(self.title)_\(self.type.rawValue)_coreTemperature", defaultValue: self.coreTemperatureState)
        self.coreBarWidth = Store.shared.int(key: "\(self.title)_\(self.type.rawValue)_coreBarWidth", defaultValue: self.coreBarWidth)
        self.coreGap = Store.shared.int(key: "\(self.title)_\(self.type.rawValue)_coreGap", defaultValue: self.coreGap)
        self.coreClusterGap = Store.shared.int(key: "\(self.title)_\(self.type.rawValue)_coreClusterGap", defaultValue: self.coreClusterGap)
        self.coreMaxWidth = Store.shared.int(key: "\(self.title)_\(self.type.rawValue)_coreMaxWidth", defaultValue: self.coreMaxWidth)
        
        if preview {
            if let previewCoreGroups, self.coreBoxesEnabled {
                self.showCorePreview(groups: previewCoreGroups)
            } else {
                if self._value.isEmpty {
                    self._value = [[ColorValue(0.72)], [ColorValue(0.38)]]
                }
                self.setFrameSize(NSSize(width: 36, height: self.frame.size.height))
                self.invalidateIntrinsicContentSize()
                self.display()
            }
        }
        
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let stringAttributes = [
            NSAttributedString.Key.font: NSFont.systemFont(ofSize: 7, weight: .regular),
            NSAttributedString.Key.foregroundColor: NSColor.textColor,
            NSAttributedString.Key.paragraphStyle: style
        ]
        
        for char in String(self.title.prefix(3)).uppercased().reversed() {
            let str = NSAttributedString.init(string: "\(char)", attributes: stringAttributes)
            self.NSLabelCharts.append(str)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        var value: [[ColorValue]] = []
        var pressureLevel: RAMPressure = .normal
        var colorZones: colorZones = (0.6, 0.8)
        var coreGroups: [Int]? = nil
        var coreTemperature: String? = nil
        self.queue.sync {
            value = self._value
            pressureLevel = self._pressureLevel
            colorZones = self._colorZones
            coreGroups = self._coreGroups
            coreTemperature = self._coreTemperature
        }
        
        guard !value.isEmpty else {
            self.setWidth(0)
            return
        }
        
        if let coreGroups, coreGroups.reduce(0, +) == value.count {
            self.drawCoreBoxes(value, groups: coreGroups, colorZones: colorZones, temperature: coreTemperature)
            return
        }
        
        var width: CGFloat = Constants.Widget.margin.x*2
        var x: CGFloat = 0
        let lineWidth = 1 / (NSScreen.main?.backingScaleFactor ?? 1)
        let offset = lineWidth / 2
        
        switch value.count {
        case 0, 1:
            width += 10 + (offset*2)
        case 2:
            width += 22
        case 3...4: // 3,4
            width += 30
        case 5...8: // 5,6,7,8
            width += 40
        case 9...12: // 9..12
            width += 50
        case 13...16: // 13..16
            width += 76
        case 17...32: // 17..32
            width += 84
        default: // > 32
            width += 118
        }
        
        if self.labelState {
            let letterHeight = self.frame.height / 3
            let letterWidth: CGFloat = 6.0
            
            var yMargin: CGFloat = 0
            for char in self.NSLabelCharts {
                let rect = CGRect(x: x, y: yMargin, width: letterWidth, height: letterHeight)
                char.draw(with: rect)
                yMargin += letterHeight
            }
            
            width += letterWidth + Constants.Widget.spacing
            x = letterWidth + Constants.Widget.spacing
        }
        
        let box = NSBezierPath(roundedRect: NSRect(
            x: x + offset,
            y: offset,
            width: width - x - (offset*2) - (Constants.Widget.margin.x*2),
            height: self.frame.size.height - (offset*2)
        ), xRadius: 2, yRadius: 2)
        
        if self.boxState {
            (isDarkMode ? NSColor.white : NSColor.black).set()
            box.stroke()
            box.fill()
        }
        
        let widthForBarChart = box.bounds.width
        let partitionMargin: CGFloat = 0.5
        let partitionsMargin: CGFloat = (CGFloat(value.count - 1)) * partitionMargin / CGFloat(value.count - 1)
        let partitionWidth: CGFloat = (widthForBarChart / CGFloat(value.count)) - CGFloat(partitionsMargin.isNaN ? 0 : partitionsMargin)
        let maxPartitionHeight: CGFloat = box.bounds.height
        
        x += offset
        for i in 0..<value.count {
            var y = offset
            for a in 0..<value[i].count {
                let partitionValue = value[i][a]
                let partitionHeight = maxPartitionHeight * CGFloat(partitionValue.value)
                let partition = NSBezierPath(rect: NSRect(x: x, y: y, width: partitionWidth, height: partitionHeight))
                
                if partitionValue.color == nil {
                    switch self.colorState {
                    case .systemAccent: NSColor.controlAccentColor.set()
                    case .utilization: partitionValue.value.usageColor(zones: colorZones, reversed: self.title == "Battery").set()
                    case .pressure: pressureLevel.pressureColor().set()
                    case .monochrome:
                        if self.boxState {
                            (isDarkMode ? NSColor.black : NSColor.white).set()
                        } else {
                            (isDarkMode ? NSColor.white : NSColor.black).set()
                        }
                    default: (self.colorState.additional as? NSColor ?? .controlAccentColor).set()
                    }
                } else {
                    partitionValue.color?.set()
                }
                
                partition.fill()
                partition.close()
                
                y += partitionHeight
            }
            
            x += partitionWidth + partitionMargin
        }
        
        if self.boxState || self.frameState {
            (isDarkMode ? NSColor.white : NSColor.black).set()
            box.lineWidth = lineWidth
            box.stroke()
        }
        
        self.setWidth(width)
    }
    
    // A small sample of the real thing: the whole row would not fit the settings strip.
    private func showCorePreview(groups: [Int]) {
        self._coreGroups = groups
        if self.coreSettingsSupported {
            if self.coreStackState {
                self._value = self._value.map { row in
                    let value = row.first?.value ?? 0
                    return [ColorValue(value * 0.35, color: .systemRed), ColorValue(value * 0.65, color: .systemBlue)]
                }
            }
            if self.coreTemperatureState {
                self._coreTemperature = Self.coreTemperatureText(52)
            }
        }
        self.updateCoreFrame()
    }
    
    private var coreScale: CGFloat {
        self.renderScale ?? self.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
    }
    
    // Core boxes stand taller than the other widgets, so only they get a taller frame.
    private func updateCoreFrame() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.updateCoreFrame() }
            return
        }
        
        let barHeight = Constants.Widget.height
        var target = self.frame
        if self.queue.sync(execute: { self._coreGroups }) != nil {
            let scale = max(self.coreScale, 1)
            target.size.height = CoreBoxLayout.boxHeight
            target.origin.y = (((barHeight - CoreBoxLayout.boxHeight) / 2) * scale).rounded() / scale
        } else {
            target.size.height = barHeight - (2*Constants.Widget.margin.y)
            target.origin.y = Constants.Widget.margin.y
        }
        
        if target != self.frame {
            self.frame = target
        }
    }
    
    private func drawCoreBoxes(_ value: [[ColorValue]], groups: [Int], colorZones: colorZones, temperature: String?) {
        let scale = self.coreScale
        let dark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        var origin: CGFloat = 0
        
        if self.labelState {
            let letterHeight = self.frame.height / 3
            let letterWidth: CGFloat = 6.0
            
            var yMargin: CGFloat = 0
            for char in self.NSLabelCharts {
                char.draw(with: CGRect(x: 0, y: yMargin, width: letterWidth, height: letterHeight))
                yMargin += letterHeight
            }
            origin = letterWidth + Constants.Widget.spacing
        }
        
        if let temperature {
            origin = self.drawCoreTemperature(temperature, at: origin, dark: dark, scale: scale)
        }
        
        let layout = CoreBoxLayout(
            groups: groups,
            barWidth: CGFloat(self.coreBarWidth),
            gap: CGFloat(self.coreGap),
            clusterGap: CGFloat(self.coreClusterGap),
            maxWidth: CGFloat(self.coreMaxWidth),
            height: self.frame.size.height,
            scale: scale
        )
        
        let lineColor = dark ? NSColor.white : NSColor.black
        let outlineColor = lineColor.withAlphaComponent(CoreBoxLayout.outlineAlpha)
        let pixel = 1 / max(scale, 1)
        let line = CoreBoxLayout.outlineWidth
        
        for (i, box) in layout.boxes.enumerated() {
            let frame = box.offsetBy(dx: origin, dy: 0)
            let inner = frame.insetBy(dx: line, dy: line)
            
            var y = inner.minY
            for segment in value[i] {
                guard segment.value > 0 else { continue }
                var height = (inner.height * CGFloat(segment.value) / pixel).rounded() * pixel
                height = min(max(height, pixel), inner.maxY - y)
                guard height > 0 else { continue }
                self.coreFillColor(segment, dark: dark, colorZones: colorZones).setFill()
                NSRect(x: inner.minX, y: y, width: inner.width, height: height).fill()
                y += height
            }
            
        }
        
        let outline = NSBezierPath()
        outline.lineWidth = line
        layout.outlines.forEach { outline.appendRect($0.offsetBy(dx: origin, dy: 0).insetBy(dx: line/2, dy: line/2)) }
        outlineColor.setStroke()
        outline.stroke()
        
        let dividers = NSBezierPath()
        layout.dividers.forEach { dividers.appendRect($0.offsetBy(dx: origin, dy: 0)) }
        lineColor.withAlphaComponent(CoreBoxLayout.dividerAlpha).setFill()
        dividers.fill()
        
        lineColor.withAlphaComponent(0.4).setFill()
        layout.separators.forEach { NSBezierPath(ovalIn: $0.offsetBy(dx: origin, dy: 0)).fill() }
        
        self.setWidth(origin + layout.width + Constants.Widget.margin.x*2)
    }
    
    // Returns where the boxes start.
    private func drawCoreTemperature(_ text: String, at x: CGFloat, dark: Bool, scale: CGFloat) -> CGFloat {
        let font = Self.coreTemperatureFont
        let string = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: dark ? NSColor.white : NSColor.textColor
        ])
        
        let pixels = max(scale, 1)
        let width = Self.coreTemperatureWidth(text)
        let left = x + width - string.size().width
        let bottom = (self.frame.height - font.capHeight) / 2 + font.descender
        string.draw(at: NSPoint(x: (left * pixels).rounded() / pixels, y: (bottom * pixels).rounded() / pixels))
        
        return x + width + Self.coreTemperatureGap
    }
    
    // Always room for three digits, so going from 99° to 100° doesn't move the boxes.
    internal static func coreTemperatureWidth(_ text: String) -> CGFloat {
        let sample = "000" + text.filter { !$0.isNumber }
        return NSAttributedString(string: sample, attributes: [.font: self.coreTemperatureFont]).size().width.rounded(.up)
    }
    
    internal static func coreTemperatureText(_ value: Double) -> String {
        String(temperature(value).prefix(while: { !$0.isLetter }))
    }
    
    private func coreFillColor(_ segment: ColorValue, dark: Bool, colorZones: colorZones) -> NSColor {
        if let color = segment.color {
            return color
        }
        switch self.colorState {
        case .systemAccent: return .controlAccentColor
        case .utilization: return segment.value.usageColor(zones: colorZones, reversed: false)
        case .monochrome: return dark ? .white : .black
        default: return self.colorState.additional as? NSColor ?? .controlAccentColor
        }
    }
    
    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if self.coreBoxesEnabled {
            self.updateCoreFrame()
            self.redraw()
        }
    }
    
    public func setCoreGroups(_ newValue: [Int]?) {
        let updated = self.queue.sync { () -> Bool in
            guard self._coreGroups != newValue else { return false }
            self._coreGroups = newValue
            return true
        }
        if updated {
            self.updateCoreFrame()
            self.redraw()
        }
    }
    
    public func setCoreTemperature(_ newValue: Double?) {
        let text = newValue.map { Self.coreTemperatureText($0) }
        let updated = self.queue.sync { () -> Bool in
            guard self._coreTemperature != text else { return false }
            self._coreTemperature = text
            return true
        }
        if updated {
            self.redraw()
        }
    }
    
    public func setValue(_ newValue: [[ColorValue]]) {
        let updated = self.queue.sync { () -> Bool in
            let tolerance: CGFloat = 0.01
            let isDifferent = self._value.count != newValue.count || zip(self._value, newValue).contains { row1, row2 in
                row1.count != row2.count || zip(row1, row2).contains { val1, val2 in
                    abs(val1.value - val2.value) > tolerance || val1.color != val2.color
                }
            }
            guard isDifferent else { return false }
            self._value = newValue
            return true
        }
        if updated {
            self.redraw()
        }
    }
    
    public func setPressure(_ newPressureLevel: RAMPressure) {
        let updated = self.queue.sync { () -> Bool in
            guard self._pressureLevel != newPressureLevel else { return false }
            self._pressureLevel = newPressureLevel
            return true
        }
        if updated {
            self.redraw()
        }
    }
    
    public func setColorZones(_ newColorZones: colorZones) {
        let updated = self.queue.sync { () -> Bool in
            guard self._colorZones != newColorZones else { return false }
            self._colorZones = newColorZones
            return true
        }
        if updated {
            self.redraw()
        }
    }
    
    // MARK: - Settings
    
    public override func settings() -> NSView {
        let view = SettingsContainerView()
        
        let box = switchView(
            action: #selector(self.toggleBox),
            state: self.boxState
        )
        self.boxSettingsView = box
        let frame = switchView(
            action: #selector(self.toggleFrame),
            state: self.frameState
        )
        self.frameSettingsView = frame
        
        view.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Label"), component: switchView(
                action: #selector(self.toggleLabel),
                state: self.labelState
            )),
            PreferencesRow(localizedString("Color"), component: colorSelectView(
                action: #selector(self.toggleColor),
                items: self.colors,
                selected: self.colorState.key
            )),
            PreferencesRow(localizedString("Box"), component: box),
            PreferencesRow(localizedString("Frame"), component: frame)
        ]))
        
        if self.coreBoxesSupported && self.coreSettingsSupported {
            view.addArrangedSubview(PreferencesSection([
                PreferencesRow(localizedString("Separate core boxes"), component: switchView(
                    action: #selector(self.toggleCoreBoxes),
                    state: self.coreBoxesState
                )),
                PreferencesRow(localizedString("Stack system and user"), component: switchView(
                    action: #selector(self.toggleCoreStack),
                    state: self.coreStackState
                )),
                PreferencesRow(localizedString("Temperature"), component: switchView(
                    action: #selector(self.toggleCoreTemperature),
                    state: self.coreTemperatureState
                )),
                PreferencesRow(localizedString("Box width"), component: self.coreSizeView(
                    action: #selector(self.changeCoreBarWidth), values: [4, 5, 6, 7, 8, 9, 10, 12], selected: self.coreBarWidth
                )),
                PreferencesRow(localizedString("Box gap"), component: self.coreSizeView(
                    action: #selector(self.changeCoreGap), values: [0, 1, 2, 3, 4, 5, 6, 7, 8], selected: self.coreGap
                )),
                PreferencesRow(localizedString("Cluster gap"), component: self.coreSizeView(
                    action: #selector(self.changeCoreClusterGap), values: [0, 2, 4, 6, 7, 8, 10, 11, 12], selected: self.coreClusterGap
                )),
                PreferencesRow(localizedString("Maximum width"), component: self.coreSizeView(
                    action: #selector(self.changeCoreMaxWidth), values: [120, 160, 200, 250, 300, 400, 500], selected: self.coreMaxWidth
                ))
            ]))
        }
        
        return view
    }
    
    private func coreSizeView(action: Selector, values: [Int], selected: Int) -> NSView {
        selectView(
            action: action,
            items: values.map { KeyValue_t(key: "\($0)", value: "\($0) pt") },
            selected: "\(selected)"
        )
    }
    
    private func storeCoreSize(_ sender: NSMenuItem, key: String, apply: (Int) -> Void) {
        guard let raw = sender.representedObject as? String, let value = Int(raw) else { return }
        apply(value)
        Store.shared.set(key: "\(self.title)_\(self.type.rawValue)_\(key)", value: value)
        self.redraw()
    }
    
    @objc private func toggleCoreBoxes(_ sender: NSControl) {
        self.coreBoxesState = controlState(sender)
        Store.shared.set(key: "\(self.title)_\(self.type.rawValue)_coreBoxes", value: self.coreBoxesState)
        self.redraw()
    }
    
    @objc private func toggleCoreStack(_ sender: NSControl) {
        self.coreStackState = controlState(sender)
        Store.shared.set(key: "\(self.title)_\(self.type.rawValue)_coreStack", value: self.coreStackState)
    }
    
    @objc private func toggleCoreTemperature(_ sender: NSControl) {
        self.coreTemperatureState = controlState(sender)
        Store.shared.set(key: "\(self.title)_\(self.type.rawValue)_coreTemperature", value: self.coreTemperatureState)
        if !self.coreTemperatureState {
            self.setCoreTemperature(nil)
        }
    }
    
    @objc private func changeCoreBarWidth(_ sender: NSMenuItem) {
        self.storeCoreSize(sender, key: "coreBarWidth") { self.coreBarWidth = $0 }
    }
    
    @objc private func changeCoreGap(_ sender: NSMenuItem) {
        self.storeCoreSize(sender, key: "coreGap") { self.coreGap = $0 }
    }
    
    @objc private func changeCoreClusterGap(_ sender: NSMenuItem) {
        self.storeCoreSize(sender, key: "coreClusterGap") { self.coreClusterGap = $0 }
    }
    
    @objc private func changeCoreMaxWidth(_ sender: NSMenuItem) {
        self.storeCoreSize(sender, key: "coreMaxWidth") { self.coreMaxWidth = $0 }
    }
    
    @objc private func toggleLabel(_ sender: NSControl) {
        self.labelState = controlState(sender)
        Store.shared.set(key: "\(self.title)_\(self.type.rawValue)_label", value: self.labelState)
        self.redraw()
    }
    
    @objc private func toggleBox(_ sender: NSControl) {
        self.boxState = controlState(sender)
        Store.shared.set(key: "\(self.title)_\(self.type.rawValue)_box", value: self.boxState)
        
        if self.frameState {
            self.frameSettingsView?.state = .off
            self.frameState = false
            Store.shared.set(key: "\(self.title)_\(self.type.rawValue)_frame", value: self.frameState)
        }
        
        self.redraw()
    }
    
    @objc private func toggleFrame(_ sender: NSControl) {
        self.frameState = controlState(sender)
        Store.shared.set(key: "\(self.title)_\(self.type.rawValue)_frame", value: self.frameState)
        
        if self.boxState {
            self.boxSettingsView?.state = .off
            self.boxState = false
            Store.shared.set(key: "\(self.title)_\(self.type.rawValue)_box", value: self.boxState)
        }
        
        self.redraw()
    }
    
    @objc private func toggleColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.colorState = SColor.fromString(key, defaultValue: self.colorState)
        Store.shared.set(key: "\(self.title)_\(self.type.rawValue)_color", value: self.colorState.key)
        self.redraw()
    }
}
