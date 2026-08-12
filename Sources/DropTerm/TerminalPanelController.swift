import AppKit

@MainActor
final class TerminalPanelController: NSObject, NSWindowDelegate {
    private let settings: AppSettings
    private let terminalTabs: TerminalTabsView
    private lazy var panel = makePanel()
    private var isVisible = false
    private var appliedStartingDirectory: String

    init(settings: AppSettings = .shared) {
        self.settings = settings
        terminalTabs = TerminalTabsView(settings: settings)
        appliedStartingDirectory = settings.startingDirectory
        super.init()
        settings.onChange = { [weak self] in
            self?.applySettings()
        }
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        guard let screen = screenUnderPointer() ?? NSScreen.main else { return }

        let frames = layout.frames(screenFrame: screen.frame, visibleFrame: screen.visibleFrame)
        terminalTabs.setBottomBackdropHeight(layout.bottomBackdropHeight(for: screen))
        panel.setFrame(frames.hidden, display: false)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
        terminalTabs.focusTerminal()

        isVisible = true

        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.setFrame(frames.visible, display: true)
            return
        }

        let overshoot = frames.visible.offsetBy(dx: 0, dy: 12)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: 0.16,
                0.78,
                0.28,
                1
            )
            panel.animator().setFrame(overshoot, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.isVisible else { return }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.14
                    context.timingFunction = CAMediaTimingFunction(
                        controlPoints: 0.22,
                        0.72,
                        0.36,
                        1
                    )
                    self.panel.animator().setFrame(frames.visible, display: true)
                }
            }
        }
    }

    func hide() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let hiddenFrame = layout.frames(screenFrame: screen.frame, visibleFrame: screen.visibleFrame).hidden

        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(hiddenFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.panel.orderOut(nil)
            }
        }

        isVisible = false
    }

    func terminateSession() {
        terminalTabs.terminateSessions()
    }

    func copyLastCommandOutput() {
        terminalTabs.copyLastCommandOutput()
    }

    func copySelection() {
        terminalTabs.copySelection()
    }

    func pasteClipboard() {
        terminalTabs.pasteClipboard()
    }

    func selectAllText() {
        terminalTabs.selectAllText()
    }

    func newTab() { terminalTabs.newTab() }
    func closeCurrentTab() { terminalTabs.closeCurrentTab() }
    func selectTab(_ index: Int) { terminalTabs.selectTab(at: index) }
    func selectNextTab() { terminalTabs.selectRelativeTab(offset: 1) }
    func selectPreviousTab() { terminalTabs.selectRelativeTab(offset: -1) }

    func windowDidResignKey(_ notification: Notification) {
        guard settings.hideOnDeactivate, isVisible else { return }
        hide()
    }

    private var layout: PanelLayout {
        PanelLayout(heightRatio: settings.panelHeightRatio)
    }

    private func applySettings() {
        terminalTabs.applySettings()
        panel.alphaValue = settings.panelOpacity
        if appliedStartingDirectory != settings.startingDirectory {
            appliedStartingDirectory = settings.startingDirectory
            terminalTabs.applyStartingDirectory()
        }
        panel.hidesOnDeactivate = settings.hideOnDeactivate

        guard isVisible, let screen = panel.screen ?? NSScreen.main else { return }
        terminalTabs.setBottomBackdropHeight(layout.bottomBackdropHeight(for: screen))
        panel.setFrame(
            layout.frames(screenFrame: screen.frame, visibleFrame: screen.visibleFrame).visible,
            display: true,
            animate: false
        )
        terminalTabs.focusTerminal()
    }

    private func makePanel() -> NSPanel {
        let panel = DropTermPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = settings.hideOnDeactivate
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.alphaValue = settings.panelOpacity
        panel.hasShadow = false
        panel.isMovable = false
        panel.contentView = terminalTabs
        panel.delegate = self
        return panel
    }

    private func screenUnderPointer() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(pointer) }
    }
}

@MainActor
private final class TerminalTabsView: NSView {
    private struct Tab {
        let id: UUID
        let surface: TerminalSurfaceView
        var title: String
    }

    private let settings: AppSettings
    private let tabBar = NSVisualEffectView()
    private let tabStack = NSStackView()
    private var tabs: [Tab] = []
    private var selectedIndex = 0
    private var bottomBackdropHeight: CGFloat = 0

    init(settings: AppSettings) {
        self.settings = settings
        super.init(frame: .zero)
        configureTabBar()
        newTab()
    }

    required init?(coder: NSCoder) { nil }

    func newTab() {
        let surface = TerminalSurfaceView(settings: settings)
        let id = UUID()
        surface.onTitleChange = { [weak self] title in self?.updateTitle(title, for: id) }
        let tab = Tab(id: id, surface: surface, title: "Terminal \(tabs.count + 1)")
        tabs.append(tab)
        addSubview(surface, positioned: .below, relativeTo: tabBar)
        selectTab(at: tabs.count - 1)
        rebuildTabBar()
    }

    func closeCurrentTab() {
        guard tabs.indices.contains(selectedIndex) else { return }
        let removed = tabs.remove(at: selectedIndex)
        removed.surface.terminateSession()
        removed.surface.removeFromSuperview()
        if tabs.isEmpty {
            selectedIndex = 0
            newTab()
            return
        }
        selectedIndex = min(selectedIndex, tabs.count - 1)
        activateSelectedTab()
        rebuildTabBar()
    }

    func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        selectedIndex = index
        activateSelectedTab()
        rebuildTabBar()
    }

    func selectRelativeTab(offset: Int) {
        guard !tabs.isEmpty else { return }
        selectTab(at: (selectedIndex + offset + tabs.count) % tabs.count)
    }

    func focusTerminal() { activeSurface?.focusTerminal() }
    func copySelection() { activeSurface?.copySelection() }
    func pasteClipboard() { activeSurface?.pasteClipboard() }
    func selectAllText() { activeSurface?.selectAllText() }
    func copyLastCommandOutput() { activeSurface?.copyLastCommandOutput() }
    func applyStartingDirectory() { activeSurface?.applyStartingDirectory() }
    func applySettings() { tabs.forEach { $0.surface.applySettings() } }
    func terminateSessions() { tabs.forEach { $0.surface.terminateSession() } }

    func setBottomBackdropHeight(_ height: CGFloat) {
        bottomBackdropHeight = max(0, height)
        tabs.forEach { $0.surface.setBottomBackdropHeight(bottomBackdropHeight) }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        tabs.forEach { $0.surface.frame = bounds }
        let barHeight: CGFloat = 34
        tabBar.frame = CGRect(x: 14, y: 12, width: max(160, min(bounds.width - 70, tabStack.fittingSize.width + 20)), height: barHeight)
    }

    private var activeSurface: TerminalSurfaceView? {
        tabs.indices.contains(selectedIndex) ? tabs[selectedIndex].surface : nil
    }

    private func configureTabBar() {
        tabBar.material = .hudWindow
        tabBar.blendingMode = .withinWindow
        tabBar.state = .active
        tabBar.wantsLayer = true
        tabBar.layer?.cornerRadius = 11
        tabBar.layer?.cornerCurve = .continuous
        addSubview(tabBar)

        tabStack.orientation = .horizontal
        tabStack.alignment = .centerY
        tabStack.spacing = 4
        tabStack.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        tabStack.frame = tabBar.bounds
        tabStack.autoresizingMask = [.width, .height]
        tabBar.addSubview(tabStack)
    }

    private func activateSelectedTab() {
        for (index, tab) in tabs.enumerated() { tab.surface.setActive(index == selectedIndex) }
        activeSurface?.focusTerminal()
    }

    private func rebuildTabBar() {
        tabStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, tab) in tabs.enumerated() {
            let button = NSButton(title: tab.title, target: self, action: #selector(tabClicked(_:)))
            button.tag = index
            button.bezelStyle = .recessed
            button.isBordered = index == selectedIndex
            button.font = .systemFont(ofSize: 12, weight: index == selectedIndex ? .semibold : .regular)
            button.contentTintColor = index == selectedIndex ? .labelColor : .secondaryLabelColor
            button.toolTip = "Tab \(index + 1)"
            tabStack.addArrangedSubview(button)
        }
        let addButton = NSButton(image: NSImage(systemSymbolName: "plus", accessibilityDescription: "New tab")!, target: self, action: #selector(addTabClicked(_:)))
        addButton.isBordered = false
        addButton.toolTip = "New Tab (⌘T)"
        tabStack.addArrangedSubview(addButton)
        needsLayout = true
    }

    @objc private func tabClicked(_ sender: NSButton) { selectTab(at: sender.tag) }
    @objc private func addTabClicked(_ sender: Any?) { newTab() }

    private func updateTitle(_ title: String, for id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].title = String(title.prefix(28))
        rebuildTabBar()
    }
}

private final class DropTermPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

struct PanelFrames: Equatable {
    let visible: CGRect
    let hidden: CGRect
}

struct PanelLayout {
    var heightRatio = 0.4
    var verticalMargin: CGFloat = 10

    func frames(screenFrame: CGRect, visibleFrame: CGRect) -> PanelFrames {
        let height = max(240, visibleFrame.height * heightRatio)
        let panelBottom = screenFrame.minY
        let panelTop = visibleFrame.minY + verticalMargin + height
        let visible = CGRect(
            x: screenFrame.minX,
            y: panelBottom,
            width: screenFrame.width,
            height: panelTop - panelBottom
        )
        let hidden = visible.offsetBy(dx: 0, dy: -visible.height - 16)
        return PanelFrames(visible: visible, hidden: hidden)
    }

    func bottomBackdropHeight(for screen: NSScreen) -> CGFloat {
        max(0, screen.visibleFrame.minY - screen.frame.minY) + verticalMargin
    }
}
