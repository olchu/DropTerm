import AppKit

@MainActor
final class TerminalPanelController: NSObject, NSWindowDelegate {
    private let settings: AppSettings
    private let terminalSurface: TerminalSurfaceView
    private lazy var panel = makePanel()
    private var isVisible = false

    init(settings: AppSettings = .shared) {
        self.settings = settings
        terminalSurface = TerminalSurfaceView(settings: settings)
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
        terminalSurface.setBottomBackdropHeight(layout.bottomBackdropHeight(for: screen))
        panel.setFrame(frames.hidden, display: false)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
        terminalSurface.focusTerminal()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frames.visible, display: true)
        }

        isVisible = true
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
        terminalSurface.terminateSession()
    }

    func copyLastCommandOutput() {
        terminalSurface.copyLastCommandOutput()
    }

    func copySelection() {
        terminalSurface.copySelection()
    }

    func pasteClipboard() {
        terminalSurface.pasteClipboard()
    }

    func selectAllText() {
        terminalSurface.selectAllText()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard settings.hideOnDeactivate, isVisible else { return }
        hide()
    }

    private var layout: PanelLayout {
        PanelLayout(heightRatio: settings.panelHeightRatio)
    }

    private func applySettings() {
        terminalSurface.applySettings()
        panel.hidesOnDeactivate = settings.hideOnDeactivate

        guard isVisible, let screen = panel.screen ?? NSScreen.main else { return }
        terminalSurface.setBottomBackdropHeight(layout.bottomBackdropHeight(for: screen))
        panel.setFrame(
            layout.frames(screenFrame: screen.frame, visibleFrame: screen.visibleFrame).visible,
            display: true,
            animate: false
        )
        terminalSurface.focusTerminal()
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
        panel.hasShadow = false
        panel.isMovable = false
        panel.contentView = terminalSurface
        panel.delegate = self
        return panel
    }

    private func screenUnderPointer() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(pointer) }
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
