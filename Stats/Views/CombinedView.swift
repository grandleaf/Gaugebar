//
//  CombinedView.swift
//  Stats
//
//  Created by Serhiy Mytrovtsiy on 09/01/2023
//  Using Swift 5.0
//  Running on macOS 13.1
//
//  Copyright © 2023 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

internal class CombinedView: NSObject, NSGestureRecognizerDelegate {
    private var menuBarItem: NSStatusItem? = nil
    private var view: NSView = NSView(frame: NSRect(x: 0, y: 0, width: 0, height: Constants.Widget.height))
    private var popup: PopupWindow? = nil
    private let popupView = Popup()
    
    private var status: Bool {
        Store.shared.bool(key: "CombinedModules", defaultValue: false)
    }
    private var iconOnly: Bool {
        Store.shared.bool(key: "CombinedModules_icon", defaultValue: false)
    }
    private var spacing: CGFloat {
        CGFloat(Int(Store.shared.string(key: "CombinedModules_spacing", defaultValue: "")) ?? 0)
    }
    private var separator: Bool {
        Store.shared.bool(key: "CombinedModules_separator", defaultValue: false)
    }
    
    private var activeModules: [Module] {
        modules.filter({ $0.enabled }).sorted(by: { $0.combinedPosition < $1.combinedPosition })
    }
    
    private var combinedModulesPopup: Bool {
        get { Store.shared.bool(key: "CombinedModules_popup", defaultValue: true) }
        set { Store.shared.set(key: "CombinedModules_popup", value: newValue) }
    }
    
    override init() {
        super.init()
        
        modules.forEach { (m: Module) in
            m.menuBar.callback = { [weak self] in
                if let s = self?.status, s {
                    DispatchQueue.main.async(execute: {
                        self?.recalculate()
                    })
                }
            }
        }
        
        self.popup = PopupWindow(title: "Combined modules", module: .combined, view: self.popupView) { _ in }
        // Above other apps' floating windows, which would otherwise cover the panel and take its clicks.
        self.popup?.level = .statusBar
        
        if self.status {
            self.enable()
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(listenForOneView), name: .toggleOneView, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(listenForModuleRearrrange), name: .moduleRearrange, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: .toggleOneView, object: nil)
        NotificationCenter.default.removeObserver(self, name: .moduleRearrange, object: nil)
    }
    
    public func enable() {
        self.menuBarItem = NSStatusBar.system.statusItem(withLength: 0)
        DispatchQueue.main.async(execute: {
            self.menuBarItem?.autosaveName = "CombinedModules"
        })
        self.menuBarItem?.button?.addSubview(self.view)
        self.menuBarItem?.button?.image = NSImage()
        self.menuBarItem?.button?.toolTip = localizedString("Combined modules")
        
        self.menuBarItem?.button?.target = self
        self.menuBarItem?.button?.action = #selector(self.handleClick)
        self.menuBarItem?.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
        
        DispatchQueue.main.async(execute: {
            self.recalculate()
        })
    }
    
    public func disable() {
        if let item = self.menuBarItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        self.menuBarItem = nil
    }
    
    private func recalculate() {
        guard self.status, self.menuBarItem != nil else { return }
        self.view.subviews.forEach({ $0.removeFromSuperview() })
        
        if self.iconOnly {
            self.view.addSubview(AppIcon())
            self.view.setFrameSize(NSSize(width: AppIcon.size.width, height: self.view.frame.height))
            self.menuBarItem?.length = AppIcon.size.width
            return
        }
        
        let visibleModules = self.activeModules.filter({ !$0.menuBar.activeWidgets.isEmpty })
        var w: CGFloat = 0
        visibleModules.enumerated().forEach { (i, m) in
            if i != 0 {
                if self.separator {
                    w += self.spacing
                    self.view.addSubview(SeparatorLineView(frame: NSRect(x: w, y: 3, width: 1, height: Constants.Widget.height-6)))
                    w += 3 + self.spacing
                } else {
                    // Room a widget leaves empty already reads as gap. Only the padding can be taken back.
                    let slack = visibleModules[i - 1].menuBar.trailingSlack + m.menuBar.leadingSlack
                    w += max(self.spacing - slack, -Constants.Widget.spacing * 2)
                }
            }
            self.view.addSubview(m.menuBar.view)
            m.menuBar.view.setFrameOrigin(NSPoint(x: w, y: 0))
            w += m.menuBar.view.frame.width
        }
        self.view.setFrameSize(NSSize(width: w, height: self.view.frame.height))
        self.menuBarItem?.length = w
    }
    
    // call when popup appear/disappear
    private func visibilityCallback(_ state: Bool) {}
    
    // A left click follows the Combined details setting, and a right click does the opposite.
    @objc private func handleClick() {
        let event = NSApplication.shared.currentEvent
        let secondaryClick = event?.type == .rightMouseDown || event?.modifierFlags.contains(.control) == true
        
        if self.iconOnly || self.combinedModulesPopup != secondaryClick {
            self.togglePopup()
        } else {
            self.openModulePopup()
        }
    }
    
    private func openModulePopup() {
        guard let window = self.menuBarItem?.button?.window else { return }
        let location = self.view.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        let visibleModules = self.activeModules.filter({ !$0.menuBar.activeWidgets.isEmpty })
        guard let module = visibleModules.last(where: { $0.menuBar.view.frame.minX <= location.x }) ?? visibleModules.first else { return }
        
        let moduleFrame = module.menuBar.view.convert(module.menuBar.view.bounds, to: nil)
        var userInfo: [String: Any] = [
            "module": module.name,
            "origin": window.frame.origin,
            "center": moduleFrame.midX
        ]
        let widgetLocation = module.menuBar.view.convert(location, from: self.view)
        let widgets = module.menuBar.activeWidgets
        if let widget = widgets.last(where: { $0.item.frame.minX <= widgetLocation.x }) ?? widgets.first {
            userInfo["widget"] = widget.type
        }
        NotificationCenter.default.post(name: .togglePopup, object: nil, userInfo: userInfo)
    }
    
    private func togglePopup() {
        guard let popup = self.popup, let item = self.menuBarItem, let window = item.button?.window else { return }
        let openedWindows = NSApplication.shared.windows.filter{ $0 is NSPanel }
        openedWindows.forEach{ $0.setIsVisible(false) }
        
        if popup.occlusionState.rawValue == 8192 {
            NSApplication.shared.activate(ignoringOtherApps: true)
            
            let openPoint = NSPoint(x: window.frame.midX, y: window.frame.midY)
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(openPoint) }) ?? NSScreen.main {
                popup.setScreenHeight(screen.visibleFrame.height)
                self.popupView.fit(screenHeight: screen.visibleFrame.height)
            }
            
            popup.contentView?.invalidateIntrinsicContentSize()
            
            let windowCenter = popup.contentView!.intrinsicContentSize.width / 2
            var x = window.frame.origin.x - windowCenter + window.frame.width/2
            let y = window.frame.origin.y - popup.contentView!.intrinsicContentSize.height - 3
            
            let buttonPoint = NSPoint(x: window.frame.midX, y: window.frame.midY)
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(buttonPoint) }) ?? NSScreen.main {
                if x + popup.contentView!.intrinsicContentSize.width > screen.frame.maxX {
                    x = screen.frame.maxX - popup.contentView!.intrinsicContentSize.width - 3
                }
                if x < screen.frame.minX {
                    x = screen.frame.minX + 3
                }
            }
            
            popup.setFrameOrigin(NSPoint(x: x, y: y))
            popup.setIsVisible(true)
        } else {
            popup.setIsVisible(false)
        }
    }
    
    @objc private func listenForOneView(_ notification: Notification) {
        guard notification.userInfo?["module"] == nil else { return }
        
        if self.status {
            self.enable()
        } else {
            self.disable()
        }
    }
    
    @objc private func listenForModuleRearrrange() {
        self.recalculate()
    }
}

private class SeparatorLineView: NSView {
    override var wantsUpdateLayer: Bool { true }
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        self.wantsLayer = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func updateLayer() {
        self.layer?.backgroundColor = (self.isDarkMode ? NSColor.white : NSColor.black).cgColor
    }
    
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        self.needsDisplay = true
    }
}

private class Popup: NSStackView, Popup_p {
    fileprivate var keyboardShortcut: [UInt16] = []
    fileprivate var sizeCallback: ((NSSize) -> Void)? = nil
    
    private static let buttonHeight: CGFloat = 24
    private static let extraHeightKey = "CombinedModules_popup_sensorsHeight"
    private let activityMonitor = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor")
    
    private var sensorsPortal: Portal_p?
    private var contentHeight: CGFloat = 0
    private var extraHeight: CGFloat = 0
    private var dragStartHeight: CGFloat = 0
    private var screenHeight: CGFloat = NSScreen.main?.visibleFrame.height ?? 0
    
    private var availableHeight: CGFloat {
        self.screenHeight - Constants.Popup.headerHeight - (Constants.Popup.margins*2) - 8
    }
    private var savedExtraHeight: CGFloat {
        CGFloat(Store.shared.int(key: Self.extraHeightKey, defaultValue: 0))
    }
    
    init() {
        self.keyboardShortcut = Store.shared.array(key: "CombinedModules_popup_keyboardShortcut", defaultValue: []) as? [UInt16] ?? []
        
        super.init(frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: 0))
        
        self.orientation = .vertical
        self.distribution = .fill
        self.alignment = .width
        self.spacing = Constants.Popup.spacing*3
        
        self.reinit()
        
        NotificationCenter.default.addObserver(self, selector: #selector(reinit), name: .toggleModule, object: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: .toggleOneView, object: nil)
    }
    
    fileprivate func settings() -> NSView? { return nil }
    fileprivate func appear() {}
    fileprivate func disappear() {}
    fileprivate func setKeyboardShortcut(_ binding: [UInt16]) {
        self.keyboardShortcut = binding
        Store.shared.set(key: "CombinedModules_popup_keyboardShortcut", value: binding)
    }
    
    @objc private func reinit() {
        self.subviews.forEach({ $0.removeFromSuperview() })
        
        // Sensors is a long list, so it goes last.
        let enabledModules = modules.filter({ $0.enabled && $0.portal != nil })
        let availableModules = enabledModules.filter({ $0.name != "Sensors" }) + enabledModules.filter({ $0.name == "Sensors" })
        var modulesHeight: CGFloat = 0
        availableModules.forEach { (m: Module) in
            if let p = m.portal {
                modulesHeight += p.height
                self.addArrangedSubview(p)
                p.widthAnchor.constraint(equalTo: self.widthAnchor).isActive = true
            }
        }
        
        var h = modulesHeight + (CGFloat(availableModules.count-1)*self.spacing)
        if self.activityMonitor != nil {
            let button = NSButton(title: localizedString("Open Activity Monitor"), target: self, action: #selector(self.openActivityMonitor))
            button.bezelStyle = .rounded
            button.heightAnchor.constraint(equalToConstant: Self.buttonHeight).isActive = true
            self.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: self.widthAnchor).isActive = true
            h += Self.buttonHeight + (availableModules.isEmpty ? 0 : self.spacing)
        }
        
        self.sensorsPortal = availableModules.first(where: { $0.name == "Sensors" })?.portal
        if self.sensorsPortal != nil {
            let grip = PopupResizeGrip()
            grip.onDragBegan = { [weak self] in
                self?.dragStartHeight = self?.extraHeight ?? 0
            }
            grip.onDrag = { [weak self] distance in
                guard let self else { return }
                self.setExtraHeight(self.dragStartHeight + distance)
            }
            grip.onDragEnded = { [weak self] in
                guard let self else { return }
                Store.shared.set(key: Self.extraHeightKey, value: Int(self.extraHeight))
            }
            self.addArrangedSubview(grip)
            grip.widthAnchor.constraint(equalTo: self.widthAnchor).isActive = true
            h += PopupResizeGrip.height + self.spacing
        }
        
        self.contentHeight = h
        self.setExtraHeight(self.savedExtraHeight)
    }
    
    // A saved height that doesn't fit this screen is only limited here, not overwritten,
    // so it comes back on a bigger screen.
    fileprivate func fit(screenHeight: CGFloat) {
        self.screenHeight = screenHeight
        self.setExtraHeight(self.savedExtraHeight)
    }
    
    private func setExtraHeight(_ wanted: CGFloat) {
        self.extraHeight = self.sensorsPortal == nil ? 0 : PopupResize.extraHeight(
            wanted: wanted,
            content: self.contentHeight,
            available: self.availableHeight
        )
        self.sensorsPortal?.setExtraHeight(self.extraHeight)
        
        let h = self.contentHeight + self.extraHeight
        if h > 0 {
            self.setFrameSize(NSSize(width: self.frame.width, height: h))
            self.sizeCallback?(self.frame.size)
        }
    }
    
    @objc private func openActivityMonitor() {
        guard let app = self.activityMonitor else { return }
        self.window?.setIsVisible(false)
        NSWorkspace.shared.open([], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
}

private class PopupResizeGrip: NSView {
    static let height: CGFloat = 12
    
    var onDragBegan: () -> Void = {}
    var onDrag: (CGFloat) -> Void = { _ in }
    var onDragEnded: () -> Void = {}
    private var startY: CGFloat = 0
    
    override var mouseDownCanMoveWindow: Bool { false }
    
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: Self.height))
        self.heightAnchor.constraint(equalToConstant: Self.height).isActive = true
        self.toolTip = localizedString("Drag to resize")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ dirtyRect: NSRect) {
        NSColor.tertiaryLabelColor.setFill()
        let pill = NSRect(x: (self.bounds.width - 36) / 2, y: (self.bounds.height - 4) / 2, width: 36, height: 4)
        NSBezierPath(roundedRect: pill, xRadius: 2, yRadius: 2).fill()
    }
    
    override func resetCursorRects() {
        self.addCursorRect(self.bounds, cursor: .resizeUpDown)
    }
    
    override func mouseDown(with event: NSEvent) {
        self.startY = NSEvent.mouseLocation.y
        self.onDragBegan()
    }
    
    override func mouseDragged(with event: NSEvent) {
        self.onDrag(self.startY - NSEvent.mouseLocation.y)
    }
    
    override func mouseUp(with event: NSEvent) {
        self.onDragEnded()
    }
}
