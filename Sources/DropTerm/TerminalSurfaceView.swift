import AppKit
import SwiftTerm

@MainActor
final class TerminalSurfaceView: NSVisualEffectView {
    private let settings: AppSettings
    private let terminalView: LocalProcessTerminalView
    private var terminalConstraints: [NSLayoutConstraint] = []
    private var hasStartedSession = false

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

    func focusTerminal() {
        window?.makeFirstResponder(terminalView)
    }

    func terminateSession() {
        guard hasStartedSession else { return }
        terminalView.terminate()
        hasStartedSession = false
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

        let padding = CGFloat(settings.contentPadding)
        terminalConstraints[0].constant = padding
        terminalConstraints[1].constant = -padding
        terminalConstraints[2].constant = padding
        terminalConstraints[3].constant = -padding
        needsLayout = true
    }

    private func configureAppearance() {
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
    }

    private func installTerminalView() {
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        terminalView.nativeForegroundColor = .white
        terminalView.nativeBackgroundColor = .clear
        terminalView.backgroundOpacity = 0
        terminalView.caretColor = .white
        terminalView.optionAsMetaKey = true
        terminalView.subviews
            .compactMap { $0 as? NSScroller }
            .forEach { $0.isHidden = true }
        addSubview(terminalView)

        terminalConstraints = [
            terminalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: trailingAnchor),
            terminalView.topAnchor.constraint(equalTo: topAnchor),
            terminalView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ]
        NSLayoutConstraint.activate(terminalConstraints)
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
