import AppKit
@preconcurrency import SwiftTerm

@MainActor
final class TerminalSurfaceView: NSVisualEffectView {
    var onTitleChange: ((String) -> Void)?
    var onProcessTermination: (() -> Void)?

    private let cornerRadius: CGFloat = 18
    private let settings: AppSettings
    private let terminalView: OutputObservingTerminalView
    private let dimmingView = PassthroughView()
    private let copyOutputButton = NSButton()
    private var keyboardMonitor: Any?
    private var hasStartedSession = false
    private var lastAvailableSize: CGSize = .zero
    private var bottomBackdropHeight: CGFloat = 0

    init(settings: AppSettings) {
        self.settings = settings
        terminalView = OutputObservingTerminalView(
            frame: .zero,
            font: Self.preferredTerminalFont(settings: settings),
            options: TerminalOptions()
        )
        super.init(frame: .zero)
        terminalView.processDelegate = self
        terminalView.onDataReceived = { [weak self] in
            self?.refreshCopyOutputAvailability()
        }
        configureAppearance()
        installDimmingView()
        installTerminalView()
        installKeyboardShortcuts()
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
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
            self.keyboardMonitor = nil
        }
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
        dimmingView.layer?.backgroundColor = NSColor.black
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

    func applyStartingDirectory() {
        guard hasStartedSession else { return }
        let command = "builtin cd -- \(shellQuote(startingDirectory()))\n"
        terminalView.terminal.sendUserInput(Array(command.utf8)[...])
        focusTerminal()
    }

    func setActive(_ isActive: Bool) {
        isHidden = !isActive
        if isActive {
            refreshCopyOutputAvailability()
        }
    }

    private func configureAppearance() {
        material = .hudWindow
        isEmphasized = false
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

    private func installDimmingView() {
        dimmingView.frame = bounds
        dimmingView.autoresizingMask = [.width, .height]
        dimmingView.wantsLayer = true
        addSubview(dimmingView)
    }

    private func installKeyboardShortcuts() {
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  event.window === self.window,
                  event.window?.firstResponder === self.terminalView else {
                return event
            }

            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard modifiers == .command,
                  let key = event.charactersIgnoringModifiers?.lowercased() else {
                return event
            }

            switch key {
            case "c": self.copySelection()
            case "v": self.pasteClipboard()
            case "a": self.selectAllText()
            default: return event
            }
            return nil
        }
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
        copyOutputButton.isHidden = true
        addSubview(copyOutputButton)

        let bottomConstraint = copyOutputButton.bottomAnchor.constraint(
            equalTo: bottomAnchor,
            constant: -14
        )
        NSLayoutConstraint.activate([
            copyOutputButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            bottomConstraint,
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

    private func refreshCopyOutputAvailability() {
        copyOutputButton.isHidden = lastCommandOutput()?.isEmpty != false
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
            currentDirectory: startingDirectory()
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

    private func startingDirectory() -> String {
        let expandedPath = NSString(string: settings.startingDirectory).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return FileManager.default.homeDirectoryForCurrentUser.path
        }
        return expandedPath
    }

    private func prepareZshIntegration() -> URL? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.olchu.DropTerm", isDirectory: true)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let integration = """
        autoload -Uz add-zsh-hook
        _dropterm_preexec() { printf '\\e]133;C\\a' }
        _dropterm_precmd() {
          # Persist every completed command immediately. DropTerm can close
          # the PTY without giving an interactive shell time to exit cleanly.
          [[ -n "$HISTFILE" ]] && fc -AI "$HISTFILE"
          printf '\\e]133;D\\a\\e]133;A\\a'
        }
        add-zsh-hook preexec _dropterm_preexec
        add-zsh-hook precmd _dropterm_precmd

        # Prefix-aware history navigation. Oh My Zsh ships this plugin, but it
        # is not enabled in every user configuration. Load it only for
        # DropTerm and bind both normal and application-cursor sequences.
        if [[ -r "$ZSH/plugins/history-substring-search/history-substring-search.plugin.zsh" ]]; then
          HISTORY_SUBSTRING_SEARCH_PREFIXED=true
          source "$ZSH/plugins/history-substring-search/history-substring-search.plugin.zsh"
          bindkey -M emacs '^[[A' history-substring-search-up
          bindkey -M emacs '^[OA' history-substring-search-up
          bindkey -M emacs '^[[B' history-substring-search-down
          bindkey -M emacs '^[OB' history-substring-search-down
          bindkey -M viins '^[[A' history-substring-search-up
          bindkey -M viins '^[OA' history-substring-search-up
          bindkey -M viins '^[[B' history-substring-search-down
          bindkey -M viins '^[OB' history-substring-search-down
          [[ -n "$terminfo[kcuu1]" ]] && bindkey -M emacs "$terminfo[kcuu1]" history-substring-search-up
          [[ -n "$terminfo[kcud1]" ]] && bindkey -M emacs "$terminfo[kcud1]" history-substring-search-down
        else
          bindkey -M emacs '^[[A' history-beginning-search-backward
          bindkey -M emacs '^[OA' history-beginning-search-backward
          bindkey -M emacs '^[[B' history-beginning-search-forward
          bindkey -M emacs '^[OB' history-beginning-search-forward
        fi
        """

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            for fileName in [".zshenv", ".zprofile", ".zlogin"] {
                let userFile = home.appendingPathComponent(fileName).path
                let wrapper = "[[ -r \(shellQuote(userFile)) ]] && source \(shellQuote(userFile))\n"
                try wrapper.write(
                    to: directory.appendingPathComponent(fileName),
                    atomically: true,
                    encoding: .utf8
                )
            }

            let userRC = home.appendingPathComponent(".zshrc").path
            let rcWrapper = """
            [[ -r \(shellQuote(userRC)) ]] && source \(shellQuote(userRC))
            \(integration)
            """
            try rcWrapper.write(
                to: directory.appendingPathComponent(".zshrc"),
                atomically: true,
                encoding: .utf8
            )

            let userLogout = home.appendingPathComponent(".zlogout").path
            let logoutWrapper = "[[ -r \(shellQuote(userLogout)) ]] && source \(shellQuote(userLogout))\n"
            try logoutWrapper.write(
                to: directory.appendingPathComponent(".zlogout"),
                atomically: true,
                encoding: .utf8
            )
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

extension TerminalSurfaceView: @preconcurrency LocalProcessTerminalViewDelegate {
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        onTitleChange?(trimmedTitle)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory, !directory.isEmpty else { return }
        let path = URL(string: directory)?.path ?? directory
        let name = URL(fileURLWithPath: path).lastPathComponent
        onTitleChange?(name.isEmpty ? "~" : name)
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        onProcessTermination?()
    }
}

private final class OutputObservingTerminalView: LocalProcessTerminalView {
    var onDataReceived: (() -> Void)?

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        DispatchQueue.main.async { [weak self] in
            self?.onDataReceived?()
        }
    }
}

private final class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
