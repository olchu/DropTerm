import AppKit
import Carbon.HIToolbox

@MainActor
final class TerminalPanelController: NSObject, NSWindowDelegate {
    private let settings: AppSettings
    private let terminalTabs: TerminalTabsView
    private lazy var panel = makePanel()
    private var isVisible = false
    private var appliedStartingDirectory: String
    private var inputSourceBeforeShowing: TISInputSource?

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

        if !isVisible {
            inputSourceBeforeShowing = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        }

        let frames = layout.frames(screenFrame: screen.frame, visibleFrame: screen.visibleFrame)
        terminalTabs.setBottomBackdropHeight(layout.bottomBackdropHeight(for: screen))
        panel.setFrame(frames.hidden, display: false)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
        selectEnglishInputSource()
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
        terminalTabs.resetSnippetSidebar()
        restorePreviousInputSource()

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

    func windowDidBecomeKey(_ notification: Notification) {
        selectEnglishInputSource()
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
        panel.appearance = NSAppearance(named: .darkAqua)
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

    private func selectEnglishInputSource() {
        guard let inputSource = TISCopyInputSourceForLanguage("en" as CFString)?.takeRetainedValue()
        else { return }
        TISSelectInputSource(inputSource)
    }

    private func restorePreviousInputSource() {
        guard let inputSourceBeforeShowing else { return }
        TISSelectInputSource(inputSourceBeforeShowing)
        self.inputSourceBeforeShowing = nil
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
    private let tabBar = ArrowCursorView()
    private let tabScrollView = ArrowCursorScrollView()
    private let tabStack = NSStackView()
    private let addTabButton = ArrowCursorButton()
    private let snippetButton = ArrowCursorButton()
    private let snippetStore: SnippetStore
    private let snippetSidebar: SnippetSidebarView
    private let aiCommandBar = AICommandBarView()
    private var tabs: [Tab] = []
    private var selectedIndex = 0
    private var bottomBackdropHeight: CGFloat = 0
    private var isSnippetSidebarVisible = false
    private var isSnippetSidebarPresented = false
    private var sidebarTransitionID = 0
    private var keyboardMonitor: Any?
    private var swipeMonitor: Any?
    private var swipeTranslation = CGPoint.zero
    private var didTriggerSwipe = false

    init(settings: AppSettings) {
        self.settings = settings
        let snippetStore = SnippetStore()
        self.snippetStore = snippetStore
        snippetSidebar = SnippetSidebarView(store: snippetStore)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        configureTabBar()
        snippetSidebar.onRunCommand = { [weak self] command in
            self?.activeSurface?.runCommand(command)
        }
        snippetSidebar.onInsertCommand = { [weak self] command in
            self?.activeSurface?.insertCommand(command)
        }
        snippetSidebar.onClose = { [weak self] in
            self?.setSnippetSidebarVisible(false)
        }
        aiCommandBar.onSubmit = { [weak self] request in
            self?.generateCommand(from: request)
        }
        aiCommandBar.onCancel = { [weak self] in
            self?.hideAICommandBar()
        }
        aiCommandBar.isHidden = true
        addSubview(aiCommandBar, positioned: .above, relativeTo: snippetSidebar)
        installKeyboardShortcuts()
        installSwipeGesture()
        newTab()
    }

    required init?(coder: NSCoder) { nil }

    func newTab() {
        let surface = TerminalSurfaceView(settings: settings)
        let id = UUID()
        surface.onTitleChange = { [weak self] title in self?.updateTitle(title, for: id) }
        let startingPath = NSString(string: settings.startingDirectory).expandingTildeInPath
        let folderName = URL(fileURLWithPath: startingPath).lastPathComponent
        let tab = Tab(
            id: id,
            surface: surface,
            title: folderName.isEmpty ? "~" : folderName
        )
        tabs.append(tab)
        addSubview(surface, positioned: .below, relativeTo: tabBar)
        selectTab(at: tabs.count - 1)
        rebuildTabBar()
    }

    func closeCurrentTab() {
        guard tabs.indices.contains(selectedIndex) else { return }
        closeTab(at: selectedIndex)
    }

    private func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        closeTab(at: index)
    }

    private func closeTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        let removed = tabs.remove(at: index)
        removed.surface.terminateSession()
        removed.surface.removeFromSuperview()
        if tabs.isEmpty {
            selectedIndex = 0
            newTab()
            return
        }
        if index < selectedIndex {
            selectedIndex -= 1
        } else if index == selectedIndex {
            selectedIndex = min(index, tabs.count - 1)
        }
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

    func resetSnippetSidebar() {
        aiCommandBar.cancelRequest()
        aiCommandBar.isHidden = true
        guard isSnippetSidebarVisible || isSnippetSidebarPresented else { return }
        sidebarTransitionID += 1
        isSnippetSidebarVisible = false
        isSnippetSidebarPresented = false
        snippetSidebar.layer?.removeAnimation(forKey: "snippet-sidebar-slide")
        snippetSidebar.isHidden = true
        snippetButton.contentTintColor = .secondaryLabelColor
        needsLayout = true
    }

    func setBottomBackdropHeight(_ height: CGFloat) {
        bottomBackdropHeight = max(0, height)
        tabs.forEach { $0.surface.setBottomBackdropHeight(bottomBackdropHeight) }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let barHeight: CGFloat = 40
        let sidebarWidth: CGFloat = isSnippetSidebarPresented ? 360 : 0
        tabs.forEach {
            $0.surface.frame = bounds
            $0.surface.setTrailingContentInset(0)
        }
        // `bottomBackdropHeight` includes PanelLayout.verticalMargin (10 pt).
        // Remove it here so tabs sit just above the actual Dock boundary.
        let dockSafeY = max(5, bottomBackdropHeight - 19)
        tabBar.frame = CGRect(
            x: 0,
            y: dockSafeY,
            width: bounds.width,
            height: barHeight
        )
        let snippetButtonWidth: CGFloat = 38
        snippetButton.frame = CGRect(
            x: tabBar.bounds.width - snippetButtonWidth - 8,
            y: 4,
            width: snippetButtonWidth,
            height: 32
        )
        tabScrollView.frame = CGRect(
            x: 0,
            y: 0,
            width: max(0, snippetButton.frame.minX - 4),
            height: tabBar.bounds.height
        )
        let contentWidth = max(tabScrollView.contentSize.width, tabStack.fittingSize.width)
        tabStack.frame = CGRect(
            origin: .zero,
            size: CGSize(width: contentWidth, height: tabScrollView.contentSize.height)
        )
        snippetSidebar.frame = CGRect(
            x: bounds.width - sidebarWidth,
            y: 0,
            width: sidebarWidth,
            height: bounds.height
        )
        let aiWidth = min(620, max(360, bounds.width - 80))
        aiCommandBar.frame = CGRect(
            x: (bounds.width - aiWidth) / 2,
            y: dockSafeY + barHeight + 14,
            width: aiWidth,
            height: aiCommandBar.preferredHeight
        )
    }

    private var activeSurface: TerminalSurfaceView? {
        tabs.indices.contains(selectedIndex) ? tabs[selectedIndex].surface : nil
    }

    private func configureTabBar() {
        addSubview(tabBar)

        tabScrollView.drawsBackground = false
        tabScrollView.hasVerticalScroller = false
        tabScrollView.hasHorizontalScroller = true
        tabScrollView.autohidesScrollers = true
        tabScrollView.horizontalScrollElasticity = .automatic
        tabScrollView.verticalScrollElasticity = .none
        tabBar.addSubview(tabScrollView)

        tabStack.orientation = .horizontal
        tabStack.alignment = .centerY
        tabStack.spacing = 4
        tabStack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        // The scroll view's document view is sized manually in `layout()`.
        // Prevent AppKit from generating a temporary 0×0 autoresizing constraint
        // before the first layout pass.
        tabStack.translatesAutoresizingMaskIntoConstraints = false
        tabScrollView.documentView = tabStack

        addTabButton.title = "+  ⌘T"
        addTabButton.image = nil
        addTabButton.isBordered = false
        addTabButton.font = .systemFont(ofSize: 13, weight: .regular)
        addTabButton.contentTintColor = .secondaryLabelColor
        addTabButton.toolTip = "New Tab (⌘T)"
        addTabButton.target = self
        addTabButton.action = #selector(addTabClicked(_:))

        snippetButton.image = NSImage(
            systemSymbolName: "text.badge.plus",
            accessibilityDescription: "Command Snippets"
        )
        snippetButton.isBordered = false
        snippetButton.contentTintColor = .secondaryLabelColor
        snippetButton.toolTip = "Command Snippets (⇧⌘S)"
        snippetButton.target = self
        snippetButton.action = #selector(toggleSnippets(_:))
        tabBar.addSubview(snippetButton)

        snippetSidebar.isHidden = true
        addSubview(snippetSidebar)
    }

    private func installKeyboardShortcuts() {
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard let key = event.charactersIgnoringModifiers?.lowercased() else {
                return event
            }

            switch (modifiers, key) {
            case (.command, "v") where !self.aiCommandBar.isHidden:
                self.aiCommandBar.pasteClipboard()
                return nil
            case (.command, "t"):
                self.newTab()
                return nil
            case (.command, "w"):
                self.closeCurrentTab()
                return nil
            case ([.command, .shift], "s"):
                self.toggleSnippetSidebar()
                return nil
            case (.command, "k"):
                self.toggleAICommandBar()
                return nil
            default:
                return event
            }
        }
    }

    private func installSwipeGesture() {
        swipeMonitor = NSEvent.addLocalMonitorForEvents(matching: [.swipe, .scrollWheel]) { [weak self] event in
            guard let self, event.window === self.window else { return event }

            if event.type == .swipe {
                if event.deltaX < 0, !self.isSnippetSidebarVisible {
                    self.setSnippetSidebarVisible(true)
                    return nil
                }
                if event.deltaX > 0, self.isSnippetSidebarVisible {
                    self.setSnippetSidebarVisible(false)
                    return nil
                }
                return event
            }

            guard event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else { return event }

            if event.phase == .mayBegin || event.phase == .began {
                self.swipeTranslation = .zero
                self.didTriggerSwipe = false
            }

            guard !self.didTriggerSwipe else { return nil }
            self.swipeTranslation.x += event.scrollingDeltaX
            self.swipeTranslation.y += event.scrollingDeltaY

            let horizontalDistance = abs(self.swipeTranslation.x)
            guard horizontalDistance >= 42,
                  horizontalDistance > abs(self.swipeTranslation.y) else {
                if event.phase == .ended || event.phase == .cancelled {
                    self.swipeTranslation = .zero
                }
                return event
            }

            if self.swipeTranslation.x < 0, !self.isSnippetSidebarVisible {
                self.didTriggerSwipe = true
                self.setSnippetSidebarVisible(true)
                return nil
            }
            if self.swipeTranslation.x > 0, self.isSnippetSidebarVisible {
                self.didTriggerSwipe = true
                self.setSnippetSidebarVisible(false)
                return nil
            }
            return event
        }
    }

    private func activateSelectedTab() {
        for (index, tab) in tabs.enumerated() { tab.surface.setActive(index == selectedIndex) }
        activeSurface?.focusTerminal()
    }

    private func rebuildTabBar() {
        tabStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let visibleTabs = Array(tabs.enumerated())
        for (visibleIndex, entry) in visibleTabs.enumerated() {
            let (index, tab) = entry
            if visibleIndex > 0 {
                tabStack.addArrangedSubview(TabSeparatorView())
            }
            let item = AnimatedTabItem(
                title: tab.title,
                color: Self.tabColor(for: tab.id),
                isSelected: index == selectedIndex,
                tabIndex: index,
                target: self,
                action: #selector(tabClicked(_:)),
                onClose: { [weak self] in self?.closeTab(id: tab.id) }
            )
            item.toolTip = "Tab \(index + 1)"
            tabStack.addArrangedSubview(item)
        }
        if !visibleTabs.isEmpty {
            tabStack.addArrangedSubview(TabSeparatorView())
        }
        tabStack.addArrangedSubview(addTabButton)
        needsLayout = true
        DispatchQueue.main.async { [weak self] in
            self?.scrollSelectedTabToVisible()
        }
    }

    @objc private func tabClicked(_ sender: NSButton) { selectTab(at: sender.tag) }
    @objc private func addTabClicked(_ sender: Any?) { newTab() }
    @objc private func toggleSnippets(_ sender: Any?) { toggleSnippetSidebar() }

    private func toggleSnippetSidebar() {
        setSnippetSidebarVisible(!isSnippetSidebarVisible)
    }

    private func toggleAICommandBar() {
        aiCommandBar.isHidden ? showAICommandBar() : hideAICommandBar()
    }

    private func showAICommandBar() {
        aiCommandBar.prepareForInput()
        aiCommandBar.isHidden = false
        needsLayout = true
        layoutSubtreeIfNeeded()
        aiCommandBar.focusInput()
    }

    private func hideAICommandBar() {
        aiCommandBar.cancelRequest()
        aiCommandBar.isHidden = true
        activeSurface?.focusTerminal()
    }

    private func generateCommand(from request: String) {
        guard let surface = activeSurface else { return }
        let service = OllamaCommandService(
            baseURL: settings.ollamaURL,
            model: settings.ollamaModel
        )
        let workingDirectory = surface.currentDirectory
        aiCommandBar.beginLoading()
        aiCommandBar.requestTask = Task { [weak self, weak surface] in
            do {
                async let candidates = ProjectDirectoryIndex.matches(
                    for: request,
                    currentDirectory: workingDirectory
                )
                async let commandContext = SafeCommandContext.collect(
                    for: request,
                    workingDirectory: workingDirectory
                )
                let command = try await service.command(
                    for: request,
                    workingDirectory: workingDirectory,
                    projectCandidates: candidates,
                    commandContext: commandContext
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, let surface, surface === self.activeSurface else { return }
                    surface.insertCommand(command)
                    self.aiCommandBar.finishLoading()
                    self.aiCommandBar.isHidden = true
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    self?.aiCommandBar.showError(error.localizedDescription)
                }
            }
        }
    }

    private func setSnippetSidebarVisible(_ isVisible: Bool) {
        guard isVisible != isSnippetSidebarVisible else { return }
        isSnippetSidebarVisible = isVisible
        sidebarTransitionID += 1
        let transitionID = sidebarTransitionID
        snippetButton.contentTintColor = isVisible ? .controlAccentColor : .secondaryLabelColor

        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            isSnippetSidebarPresented = isVisible
            snippetSidebar.isHidden = !isVisible
            snippetSidebar.layer?.removeAllAnimations()
            needsLayout = true
            if !isVisible { activeSurface?.focusTerminal() }
            return
        }

        if isVisible {
            isSnippetSidebarPresented = true
            snippetSidebar.isHidden = false
            needsLayout = true
            layoutSubtreeIfNeeded()
            animateSnippetSidebar(from: 360, to: 0, transitionID: transitionID)
        } else {
            animateSnippetSidebar(from: 0, to: 360, transitionID: transitionID) { [weak self] in
                guard let self,
                      self.sidebarTransitionID == transitionID,
                      !self.isSnippetSidebarVisible else { return }
                self.isSnippetSidebarPresented = false
                self.snippetSidebar.isHidden = true
                self.snippetSidebar.layer?.removeAnimation(forKey: "snippet-sidebar-slide")
                self.needsLayout = true
                self.activeSurface?.focusTerminal()
            }
        }
    }

    private func animateSnippetSidebar(
        from startX: CGFloat,
        to endX: CGFloat,
        transitionID: Int,
        completion: (() -> Void)? = nil
    ) {
        guard let layer = snippetSidebar.layer else {
            completion?()
            return
        }
        layer.removeAnimation(forKey: "snippet-sidebar-slide")

        let animation = CASpringAnimation(keyPath: "transform.translation.x")
        animation.fromValue = startX
        animation.toValue = endX
        animation.mass = 1
        animation.stiffness = 250
        animation.damping = 22
        animation.initialVelocity = 0.35
        animation.duration = min(0.52, animation.settlingDuration)
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard self?.sidebarTransitionID == transitionID else { return }
            completion?()
        }
        layer.add(animation, forKey: "snippet-sidebar-slide")
        CATransaction.commit()
    }

    private func updateTitle(_ title: String, for id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].title = String(title.prefix(28))
        rebuildTabBar()
    }

    private func scrollSelectedTabToVisible() {
        let arrangedIndex = selectedIndex * 2
        guard tabStack.arrangedSubviews.indices.contains(arrangedIndex) else { return }
        tabStack.arrangedSubviews[arrangedIndex].scrollToVisible(
            tabStack.arrangedSubviews[arrangedIndex].bounds
        )
    }

    private static func tabColor(for id: UUID) -> NSColor {
        let colors: [NSColor] = [.systemIndigo, .systemGreen, .systemOrange, .systemBlue, .systemPink, .systemPurple, .systemTeal, .systemRed]
        return colors[Int(id.hashValue.magnitude % UInt(colors.count))]
    }
}

@MainActor
private final class AICommandBarView: NSView, NSTextFieldDelegate {
    var onSubmit: ((String) -> Void)?
    var onCancel: (() -> Void)?
    var requestTask: Task<Void, Never>?
    let preferredHeight: CGFloat = 66

    private let sparkle = NSImageView()
    private let input = NSTextField()
    private let submitButton = NSButton()
    private let spinner = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = AppColors.panelBackground(tint: 0.09, alpha: 0.98).cgColor
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.35
        layer?.shadowRadius = 18
        layer?.shadowOffset = CGSize(width: 0, height: -4)

        sparkle.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "AI command")
        sparkle.contentTintColor = .systemPurple
        addSubview(sparkle)

        input.placeholderString = "Describe a command…"
        input.font = .systemFont(ofSize: 14)
        input.isBezeled = false
        input.drawsBackground = false
        input.focusRingType = .none
        input.delegate = self
        addSubview(input)

        submitButton.title = "Generate"
        submitButton.bezelStyle = .rounded
        submitButton.controlSize = .small
        submitButton.target = self
        submitButton.action = #selector(submit(_:))
        addSubview(submitButton)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        addSubview(spinner)

        statusLabel.font = .systemFont(ofSize: 10.5)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        addSubview(statusLabel)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        sparkle.frame = CGRect(x: 15, y: 32, width: 18, height: 18)
        submitButton.sizeToFit()
        submitButton.frame = CGRect(
            x: bounds.width - submitButton.frame.width - 14,
            y: 27,
            width: submitButton.frame.width,
            height: 26
        )
        spinner.frame = CGRect(x: submitButton.frame.minX - 25, y: 31, width: 16, height: 16)
        input.frame = CGRect(
            x: 43,
            y: 27,
            width: max(0, spinner.frame.minX - 51),
            height: 25
        )
        statusLabel.frame = CGRect(x: 43, y: 8, width: max(0, bounds.width - 58), height: 14)
    }

    func prepareForInput() {
        cancelRequest()
        input.isEnabled = true
        submitButton.isEnabled = true
        statusLabel.stringValue = "Enter to insert  ·  Esc to close  ·  Local Ollama"
        statusLabel.textColor = .secondaryLabelColor
    }

    func focusInput() {
        window?.makeFirstResponder(input)
    }

    func pasteClipboard() {
        guard input.isEnabled else { return }
        if window?.firstResponder !== input.currentEditor() {
            window?.makeFirstResponder(input)
        }
        input.currentEditor()?.paste(nil)
    }

    func beginLoading() {
        input.isEnabled = false
        submitButton.isEnabled = false
        spinner.startAnimation(nil)
        statusLabel.stringValue = "Generating command…"
        statusLabel.textColor = .secondaryLabelColor
    }

    func finishLoading() {
        spinner.stopAnimation(nil)
        requestTask = nil
        input.stringValue = ""
    }

    func showError(_ message: String) {
        spinner.stopAnimation(nil)
        requestTask = nil
        input.isEnabled = true
        submitButton.isEnabled = true
        statusLabel.stringValue = message
        statusLabel.textColor = .systemRed
        focusInput()
    }

    func cancelRequest() {
        requestTask?.cancel()
        requestTask = nil
        spinner.stopAnimation(nil)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            submit(nil)
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            onCancel?()
            return true
        }
        return false
    }

    @objc private func submit(_ sender: Any?) {
        let request = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, requestTask == nil else {
            NSSound.beep()
            return
        }
        onSubmit?(request)
    }
}

private final class AnimatedTabItem: NSView {
    private let contentView = ArrowCursorView()
    private let button: ColoredTabButton
    private let closeButton = ArrowCursorButton()
    private let closeActionTarget: ClosureActionTarget
    private let closeAction: () -> Void
    private let selected: Bool
    private let tabTitle: String
    private let tabColor: NSColor
    private var isHovered = false
    private var trackingArea: NSTrackingArea?
    private let baseWidth: CGFloat
    private var widthConstraint: NSLayoutConstraint?

    init(
        title: String,
        color: NSColor,
        isSelected: Bool,
        tabIndex: Int,
        target: AnyObject?,
        action: Selector?,
        onClose: @escaping () -> Void
    ) {
        selected = isSelected
        tabTitle = title
        tabColor = color
        closeAction = onClose
        closeActionTarget = ClosureActionTarget(action: onClose)
        button = ColoredTabButton(
            title: title,
            color: color.withAlphaComponent(isSelected ? 0.82 : 0.48),
            textColor: isSelected ? .secondaryLabelColor : .tertiaryLabelColor,
            target: target,
            action: action
        )
        button.tag = tabIndex
        baseWidth = button.intrinsicContentSize.width + 28
        super.init(frame: .zero)
        button.toolTip = "Tab \(tabIndex + 1)"
        wantsLayer = true
        contentView.wantsLayer = true
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
        button.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(button)
        closeButton.title = "×"
        closeButton.isBordered = false
        closeButton.font = .systemFont(ofSize: 15, weight: .regular)
        closeButton.contentTintColor = .tertiaryLabelColor
        closeButton.toolTip = "Close Tab (⌘W)"
        closeButton.alphaValue = isSelected ? 0.78 : 0.52
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.target = closeActionTarget
        closeButton.action = #selector(ClosureActionTarget.invoke(_:))
        contentView.addSubview(closeButton)
        NSLayoutConstraint.activate([
            contentView.centerXAnchor.constraint(equalTo: centerXAnchor),
            contentView.centerYAnchor.constraint(equalTo: centerYAnchor),
            contentView.widthAnchor.constraint(equalToConstant: baseWidth),
            contentView.heightAnchor.constraint(equalToConstant: 28),
            button.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 5),
            button.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            button.heightAnchor.constraint(equalToConstant: 26),
            closeButton.leadingAnchor.constraint(equalTo: button.trailingAnchor, constant: 3),
            closeButton.centerYAnchor.constraint(equalTo: button.centerYAnchor, constant: -0.5),
            closeButton.widthAnchor.constraint(equalToConstant: 14),
            closeButton.heightAnchor.constraint(equalToConstant: 14)
        ])
        let widthConstraint = widthAnchor.constraint(
            equalToConstant: baseWidth
        )
        widthConstraint.isActive = true
        self.widthConstraint = widthConstraint
        heightAnchor.constraint(equalToConstant: 32).isActive = true
        updateMagnification(animated: false)
        installHoverResetObservers()
    }

    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.arrow.set()
        isHovered = true
        updateAppearance(active: true)
        updateCloseButtonAppearance(active: true)
        updateMagnification(animated: true)
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        resetHover(animated: true)
        super.mouseExited(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { resetHover(animated: false) }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let closeHitWidth: CGFloat = isHovered ? 30 : 22
        if point.x >= bounds.maxX - closeHitWidth {
            closeAction()
            return
        }
        super.mouseDown(with: event)
    }

    private func updateMagnification(animated: Bool) {
        let scale: CGFloat = isHovered ? 1.14 : 1
        let transform = CATransform3DMakeScale(scale, scale, 1)
        let targetWidth = baseWidth * scale

        guard animated, let contentLayer = contentView.layer else {
            widthConstraint?.constant = targetWidth
            contentView.layer?.transform = transform
            return
        }

        window?.contentView?.layoutSubtreeIfNeeded()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.32
            context.allowsImplicitAnimation = true
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: 0.16,
                0.82,
                0.22,
                1
            )
            widthConstraint?.constant = targetWidth
            window?.contentView?.animator().layoutSubtreeIfNeeded()
        }

        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = contentLayer.presentation()?.transform ?? contentLayer.transform
        animation.toValue = transform
        animation.duration = 0.32
        animation.timingFunction = CAMediaTimingFunction(
            controlPoints: 0.16,
            0.82,
            0.22,
            1
        )
        contentLayer.add(animation, forKey: "tabScale")
        contentLayer.transform = transform
    }

    private func updateCloseButtonAppearance(active: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            closeButton.animator().alphaValue = active ? 0.78 : 0.52
        }
    }

    private func updateAppearance(active: Bool) {
        button.updateAppearance(
            title: tabTitle,
            color: tabColor.withAlphaComponent(active ? 0.82 : 0.48),
            textColor: active ? .secondaryLabelColor : .tertiaryLabelColor,
            animated: true
        )
    }

    private func resetHover(animated: Bool) {
        guard isHovered else { return }
        isHovered = false
        updateAppearance(active: selected)
        updateCloseButtonAppearance(active: selected)
        updateMagnification(animated: animated)
    }

    private func installHoverResetObservers() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(applicationDidResignActive(_:)),
            name: NSApplication.didResignActiveNotification,
            object: NSApp
        )
        center.addObserver(
            self,
            selector: #selector(windowDidResignKey(_:)),
            name: NSWindow.didResignKeyNotification,
            object: nil
        )
    }

    @objc private func applicationDidResignActive(_ notification: Notification) {
        resetHover(animated: false)
    }

    @objc private func windowDidResignKey(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        resetHover(animated: false)
    }
}

private final class ClosureActionTarget: NSObject {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @objc func invoke(_ sender: Any?) { action() }
}

private final class ColoredTabButton: NSButton {
    init(
        title: String,
        color: NSColor,
        textColor: NSColor,
        target: AnyObject?,
        action: Selector?
    ) {
        super.init(frame: .zero)
        self.target = target
        self.action = action
        bezelStyle = .regularSquare
        isBordered = false
        attributedTitle = Self.title(title, color: color, textColor: textColor)
        wantsLayer = true
        setButtonType(.momentaryChange)
    }

    required init?(coder: NSCoder) { nil }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    func updateAppearance(
        title: String,
        color: NSColor,
        textColor: NSColor,
        animated: Bool
    ) {
        let updatedTitle = Self.title(title, color: color, textColor: textColor)
        guard animated else {
            attributedTitle = updatedTitle
            return
        }
        let transition = CATransition()
        transition.type = .fade
        transition.duration = 0.18
        transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(transition, forKey: "tabAppearance")
        attributedTitle = updatedTitle
    }

    private static func title(
        _ title: String,
        color: NSColor,
        textColor: NSColor
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: "● ",
            attributes: [
                .foregroundColor: color,
                .font: NSFont.systemFont(ofSize: 9, weight: .medium)
            ]
        )
        result.append(NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: textColor,
                .font: NSFont.systemFont(ofSize: 13, weight: .regular)
            ]
        ))
        return result
    }
}

private class ArrowCursorView: NSView {
    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }
}

private final class TabSeparatorView: ArrowCursorView {
    private let line = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 9).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true

        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor
            .withAlphaComponent(0.18)
            .cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)
        NSLayoutConstraint.activate([
            line.centerXAnchor.constraint(equalTo: centerXAnchor),
            line.centerYAnchor.constraint(equalTo: centerYAnchor),
            line.widthAnchor.constraint(equalToConstant: 1),
            line.heightAnchor.constraint(equalToConstant: 15)
        ])
    }

    required init?(coder: NSCoder) { nil }
}

private final class ArrowCursorButton: NSButton {
    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.arrow.set()
        super.mouseEntered(with: event)
    }
}

private final class ArrowCursorScrollView: NSScrollView {
    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.arrow.set()
        super.mouseMoved(with: event)
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
