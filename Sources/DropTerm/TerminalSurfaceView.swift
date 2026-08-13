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
    private var trailingContentInset: CGFloat = 0
    private(set) var currentDirectory: String

    init(settings: AppSettings) {
        self.settings = settings
        currentDirectory = NSString(string: settings.startingDirectory).expandingTildeInPath
        terminalView = OutputObservingTerminalView(
            frame: .zero,
            font: Self.preferredTerminalFont(settings: settings),
            options: TerminalOptions(cursorStyle: Self.cursorStyle(settings: settings))
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
            width: max(0, bounds.width - trailingContentInset - padding * 2),
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

    func runCommand(_ command: String) {
        let input = Self.snippetShellInput(command) + "\n"
        terminalView.terminal.sendUserInput(Array(input.utf8)[...])
        focusTerminal()
    }

    func insertCommand(_ command: String) {
        terminalView.terminal.sendUserInput(Array(Self.snippetShellInput(command).utf8)[...])
        focusTerminal()
    }

    private static func snippetShellInput(_ value: String) -> String {
        value.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " && ")
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

    func setTrailingContentInset(_ inset: CGFloat) {
        let inset = max(0, inset)
        guard trailingContentInset != inset else { return }
        trailingContentInset = inset
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
        terminalView.terminal.setCursorStyle(Self.cursorStyle(settings: settings))

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
        terminalView.caretColor = NSColor(
            calibratedRed: 1.0,
            green: 0.294,
            blue: 0.271,
            alpha: 1
        )
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
        autoload -Uz add-zsh-hook add-zle-hook-widget
        _dropterm_preexec() { printf '\\e]133;C\\a' }
        _dropterm_precmd() {
          # Persist every completed command immediately. DropTerm can close
          # the PTY without giving an interactive shell time to exit cleanly.
          [[ -n "$HISTFILE" ]] && fc -AI "$HISTFILE"
          # Powerlevel10k owns PROMPT when loaded. Replacing it from a precmd
          # hook breaks instant prompt; use the compact prompt only for other
          # zsh configurations.
          (( ${+functions[p10k]} )) || PROMPT='%3~ '
          printf '\\e]133;D\\a\\e]133;A;cl=w\\a'
        }
        _dropterm_line_init() { printf '\\e]133;B\\a' }
        add-zsh-hook preexec _dropterm_preexec
        add-zsh-hook precmd _dropterm_precmd
        add-zle-hook-widget line-init _dropterm_line_init

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
            if (( ${+functions[p10k]} )); then
              typeset -g POWERLEVEL9K_SHORTEN_STRATEGY=truncate_to_last
              typeset -g POWERLEVEL9K_SHORTEN_DIR_LENGTH=3
              typeset -g POWERLEVEL9K_DIR_MAX_LENGTH=0
              p10k reload
              p10k finalize
            fi
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

    private static func cursorStyle(settings: AppSettings) -> CursorStyle {
        switch (settings.cursorShape, settings.cursorBlink) {
        case (.bar, false): .steadyBar
        case (.bar, true): .blinkBar
        case (.block, false): .steadyBlock
        case (.block, true): .blinkBlock
        case (.underline, false): .steadyUnderline
        case (.underline, true): .blinkUnderline
        }
    }
}

extension TerminalSurfaceView: @preconcurrency LocalProcessTerminalViewDelegate {
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        // Processes such as npm, Vite, and SSH frequently replace the terminal
        // title with their command name. Tab titles intentionally follow only
        // the shell's reported working directory instead.
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory, !directory.isEmpty else { return }
        let path = URL(string: directory)?.path ?? directory
        currentDirectory = path
        let name = URL(fileURLWithPath: path).lastPathComponent
        onTitleChange?(name.isEmpty ? "~" : name)
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        onProcessTermination?()
    }
}

private final class OutputObservingTerminalView: LocalProcessTerminalView {
    var onDataReceived: (() -> Void)?
    private var isDraggingPointer = false

    override func mouseDown(with event: NSEvent) {
        isDraggingPointer = false
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        isDraggingPointer = true
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        let shouldMoveCursor = event.clickCount == 1
            && !isDraggingPointer
            && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty
        let target = shouldMoveCursor ? terminalPosition(for: event) : nil

        // SwiftTerm normally waits for the full system double-click interval
        // before routing a semantic prompt click. Disable that deferred route
        // for this event and perform the same movement immediately below.
        let clickBehavior = terminal.semanticPromptClickBehavior
        terminal.semanticPromptClickBehavior = .disabled
        super.mouseUp(with: event)
        terminal.semanticPromptClickBehavior = clickBehavior

        if let target {
            _ = terminal.handleSemanticPromptClick(at: target)
            setNeedsDisplay(bounds)
        }
        isDraggingPointer = false
    }

    private func terminalPosition(for event: NSEvent) -> Position? {
        guard terminal.cols > 0, terminal.rows > 0,
              bounds.width > 0, bounds.height > 0 else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        let cellWidth = bounds.width / CGFloat(terminal.cols)
        let cellHeight = bounds.height / CGFloat(terminal.rows)
        let column = min(max(Int(point.x / cellWidth), 0), terminal.cols - 1)
        let visibleRow = min(
            max(Int((bounds.height - point.y) / cellHeight), 0),
            terminal.rows - 1
        )
        return Position(col: column, row: visibleRow + terminal.buffer.yDisp)
    }

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
