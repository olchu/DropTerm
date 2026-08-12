import AppKit
import SwiftTerm

@MainActor
final class TerminalSurfaceView: NSVisualEffectView {
    private let cornerRadius: CGFloat = 18
    private let settings: AppSettings
    private let terminalView: LocalProcessTerminalView
    private let copyOutputButton = NSButton()
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
        installCopyOutputButton()
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

    func copySelection() {
        terminalView.copy(self)
    }

    func pasteClipboard() {
        terminalView.paste(self)
    }

    func selectAllText() {
        terminalView.selectAll(self)
    }

    @discardableResult
    func copyLastCommandOutput() -> Bool {
        guard let output = lastCommandOutput(), !output.isEmpty else {
            NSSound.beep()
            return false
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        copyOutputButton.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Copied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.copyOutputButton.image = NSImage(
                systemSymbolName: "doc.on.doc",
                accessibilityDescription: "Copy last command output"
            )
        }
        return true
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

    private func installCopyOutputButton() {
        copyOutputButton.bezelStyle = .recessed
        copyOutputButton.isBordered = false
        copyOutputButton.image = NSImage(
            systemSymbolName: "doc.on.doc",
            accessibilityDescription: "Copy last command output"
        )
        copyOutputButton.contentTintColor = .secondaryLabelColor
        copyOutputButton.toolTip = "Copy last command output (⇧⌘C)"
        copyOutputButton.target = self
        copyOutputButton.action = #selector(copyLastOutput(_:))
        copyOutputButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(copyOutputButton)

        NSLayoutConstraint.activate([
            copyOutputButton.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            copyOutputButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            copyOutputButton.widthAnchor.constraint(equalToConstant: 30),
            copyOutputButton.heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    @objc private func copyLastOutput(_ sender: Any?) {
        copyLastCommandOutput()
        focusTerminal()
    }

    private func lastCommandOutput() -> String? {
        let terminal = terminalView.terminal!
        var promptRows: [Int] = []
        var row = 0

        while terminal.semanticContent(at: Position(col: 0, row: row)) != nil {
            if terminal.semanticPromptMarks(at: row).contains(where: { $0.kind == .initial }) {
                promptRows.append(row)
            }
            row += 1
        }

        guard promptRows.count >= 2 else { return nil }
        let startRow = promptRows[promptRows.count - 2]
        let endRow = promptRows[promptRows.count - 1]
        var outputRows: [Int] = []

        for candidateRow in startRow..<endRow {
            let containsOutput = (0..<terminal.cols).contains { column in
                terminal.semanticContent(at: Position(col: column, row: candidateRow)) == .output
            }
            if containsOutput {
                outputRows.append(candidateRow)
            }
        }

        guard let firstRow = outputRows.first, let lastRow = outputRows.last else { return nil }
        return terminal.getText(
            start: Position(col: 0, row: firstRow),
            end: Position(col: terminal.cols - 1, row: lastRow)
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func startSessionIfNeeded() {
        guard !hasStartedSession else {
            focusTerminal()
            return
        }

        let shell = loginShell()
        let executableName = URL(fileURLWithPath: shell).lastPathComponent
        var environment = Terminal.getEnvironmentVariables(
            termName: "xterm-256color",
            trueColor: true
        )
        if executableName == "zsh", let integrationDirectory = prepareZshIntegration() {
            environment.removeAll { $0.hasPrefix("ZDOTDIR=") }
            environment.append("ZDOTDIR=\(integrationDirectory.path)")
        }

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

    private func prepareZshIntegration() -> URL? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.olchu.DropTerm", isDirectory: true)
        let rcFile = directory.appendingPathComponent(".zshrc")
        let userRC = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".zshrc").path
        let script = """
        [[ -r \(shellQuote(userRC)) ]] && source \(shellQuote(userRC))
        autoload -Uz add-zsh-hook
        _dropterm_preexec() { printf '\\e]133;C\\a' }
        _dropterm_precmd() {
          printf '\\e]133;D\\a\\e]133;A\\a'
        }
        add-zsh-hook preexec _dropterm_preexec
        add-zsh-hook precmd _dropterm_precmd
        """

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try script.write(to: rcFile, atomically: true, encoding: .utf8)
            return directory
        } catch {
            return nil
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
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
