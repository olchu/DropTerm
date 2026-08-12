import AppKit
import SwiftTerm

@MainActor
final class TerminalSurfaceView: NSVisualEffectView {
    private let cornerRadius: CGFloat = 18
    private let settings: AppSettings
    private let terminalView: LocalProcessTerminalView
    private var hasStartedSession = false
    private var lastAvailableSize: CGSize = .zero
    private var bottomBackdropHeight: CGFloat = 0

    init(settings: AppSettings) {
        self.settings = settings
        terminalView = LocalProcessTerminalView(
            frame: .zero,
            font: Self.preferredTerminalFont(settings: settings),
            options: TerminalOptions()
        )
        super.init(frame: .zero)
        configureAppearance()
        installTerminalView()
        applySettings()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        startSessionIfNeeded()
    }

    override func layout() {
        super.layout()

        let padding = CGFloat(settings.contentPadding)
        let availableFrame = CGRect(
            x: bounds.minX + padding,
            y: bounds.minY + bottomBackdropHeight + padding,
            width: max(0, bounds.width - padding * 2),
            height: max(0, bounds.height - bottomBackdropHeight - padding * 2)
        )
        guard availableFrame.width > 0, availableFrame.height > 0 else { return }

        if lastAvailableSize != availableFrame.size {
            terminalView.frame = availableFrame
            terminalView.layoutSubtreeIfNeeded()
            lastAvailableSize = availableFrame.size
        }

        let gridSize = terminalView.getOptimalFrameSize().size
        let centeredSize = CGSize(
            width: min(gridSize.width, availableFrame.width),
            height: min(gridSize.height, availableFrame.height)
        )
        terminalView.frame = CGRect(
            x: availableFrame.midX - centeredSize.width / 2,
            y: availableFrame.midY - centeredSize.height / 2,
            width: centeredSize.width,
            height: centeredSize.height
        ).integral
    }

    func focusTerminal() {
        window?.makeFirstResponder(terminalView)
    }

    func terminateSession() {
        guard hasStartedSession else { return }
        terminalView.terminate()
        hasStartedSession = false
    }

    func setBottomBackdropHeight(_ height: CGFloat) {
        guard bottomBackdropHeight != height else { return }
        bottomBackdropHeight = max(0, height)
        lastAvailableSize = .zero
        needsLayout = true
    }

    func applySettings() {
        layer?.backgroundColor = NSColor.black
            .withAlphaComponent(settings.backgroundOpacity)
            .cgColor
        let preferredFont = Self.preferredTerminalFont(settings: settings)
        if terminalView.font.fontName != preferredFont.fontName
            || terminalView.font.pointSize != preferredFont.pointSize {
            terminalView.font = preferredFont
        }

        lastAvailableSize = .zero
        needsLayout = true
    }

    private func configureAppearance() {
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
    }

    private func installTerminalView() {
        terminalView.autoresizingMask = []
        terminalView.nativeForegroundColor = .white
        terminalView.nativeBackgroundColor = .clear
        terminalView.backgroundOpacity = 0
        terminalView.caretColor = .white
        terminalView.optionAsMetaKey = true
        terminalView.subviews
            .compactMap { $0 as? NSScroller }
            .forEach { $0.isHidden = true }
        addSubview(terminalView)
    }

    private func startSessionIfNeeded() {
        guard !hasStartedSession else {
            focusTerminal()
            return
        }

        let shell = loginShell()
        let executableName = URL(fileURLWithPath: shell).lastPathComponent
        let environment = Terminal.getEnvironmentVariables(
            termName: "xterm-256color",
            trueColor: true
        )

        hasStartedSession = true
        terminalView.startProcess(
            executable: shell,
            environment: environment,
            execName: "-\(executableName)",
            currentDirectory: FileManager.default.homeDirectoryForCurrentUser.path
        )
        focusTerminal()
    }

    private func loginShell() -> String {
        let configuredShell = settings.shellPath
        guard FileManager.default.isExecutableFile(atPath: configuredShell) else {
            return "/bin/zsh"
        }
        return configuredShell
    }

    private static func preferredTerminalFont(settings: AppSettings) -> NSFont {
        let size = CGFloat(settings.fontSize)

        if settings.fontName != "Automatic",
           let selectedFont = NSFont(name: settings.fontName, size: size) {
            return selectedFont
        }

        let powerlevelFonts = [
            "MesloLGS-NF-Regular",
            "MesloLGS NF",
            "MesloLGS Nerd Font"
        ]

        for fontName in powerlevelFonts {
            if let font = NSFont(name: fontName, size: size) {
                return font
            }
        }

        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}
