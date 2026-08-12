import AppKit

@MainActor
final class TerminalPanelController {
    private let layout = PanelLayout()
    private let terminalSurface = TerminalSurfaceView()
    private lazy var panel = makePanel()
    private var isVisible = false

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        guard let screen = screenUnderPointer() ?? NSScreen.main else { return }

        let frames = layout.frames(in: screen.visibleFrame)
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
        let hiddenFrame = layout.frames(in: screen.visibleFrame).hidden

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
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.contentView = terminalSurface
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

    func frames(in visibleFrame: CGRect) -> PanelFrames {
        let height = max(240, visibleFrame.height * heightRatio)
        let visible = CGRect(
            x: visibleFrame.minX,
            y: visibleFrame.minY,
            width: visibleFrame.width,
            height: height
        )
        let hidden = visible.offsetBy(dx: 0, dy: -height - 16)
        return PanelFrames(visible: visible, hidden: hidden)
    }
}
