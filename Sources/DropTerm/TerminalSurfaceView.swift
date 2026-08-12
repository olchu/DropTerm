import AppKit
import SwiftTerm

@MainActor
final class TerminalSurfaceView: NSVisualEffectView {
    private let terminalView: LocalProcessTerminalView
    private var hasStartedSession = false

    override init(frame frameRect: NSRect) {
        terminalView = LocalProcessTerminalView(
            frame: .zero,
            font: Self.preferredTerminalFont(),
            options: TerminalOptions()
        )
        super.init(frame: frameRect)
        configureAppearance()
        installTerminalView()
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

    private func configureAppearance() {
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
    }

    private func installTerminalView() {
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        terminalView.nativeForegroundColor = .white
        terminalView.nativeBackgroundColor = NSColor.black.withAlphaComponent(0.12)
        terminalView.backgroundOpacity = 0.12
        terminalView.caretColor = .white
        terminalView.optionAsMetaKey = true
        addSubview(terminalView)

        NSLayoutConstraint.activate([
            terminalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: trailingAnchor),
            terminalView.topAnchor.constraint(equalTo: topAnchor),
            terminalView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func startSessionIfNeeded() {
        guard !hasStartedSession else {
            focusTerminal()
            return
        }

        let shell = Self.loginShell()
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

    private static func loginShell() -> String {
        let configuredShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard FileManager.default.isExecutableFile(atPath: configuredShell) else {
            return "/bin/zsh"
        }
        return configuredShell
    }

    private static func preferredTerminalFont() -> NSFont {
        let powerlevelFonts = [
            "MesloLGS-NF-Regular",
            "MesloLGS NF",
            "MesloLGS Nerd Font"
        ]

        for fontName in powerlevelFonts {
            if let font = NSFont(name: fontName, size: 14) {
                return font
            }
        }

        return NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    }
}
