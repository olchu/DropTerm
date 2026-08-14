import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private lazy var panelController = TerminalPanelController(settings: settings)
    private lazy var settingsWindowController = SettingsWindowController(settings: settings)
    private var hotKeyService: GlobalHotKeyService?
    private var statusItem: NSStatusItem?
    private var workspaceActivationObserver: NSObjectProtocol?
    private var isHotKeySuppressedForParallels: Bool?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        applyBundleIcon()
        installMainMenu()
        installStatusItem()
        observeWorkspaceActivation()
        updateHotKeyRegistration(for: NSWorkspace.shared.frontmostApplication)
        settings.onHotKeyChange = { [weak self] in
            guard self?.isHotKeySuppressedForParallels == false else { return }
            self?.installGlobalHotKey()
        }

        if settings.showOnLaunch {
            Task { @MainActor [panelController] in
                panelController.show()
            }
        }
    }

    /// A debugger can launch the executable inside the app bundle directly,
    /// bypassing Launch Services. In that case Dock falls back to its generic
    /// `exec` icon unless the application supplies its bundle icon explicitly.
    private func applyBundleIcon() {
        guard
            Bundle.main.bundleURL.pathExtension == "app",
            let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            let icon = NSImage(contentsOf: iconURL)
        else { return }

        NSApp.applicationIconImage = icon
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyService?.invalidate()
        hotKeyService = nil
        if let workspaceActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceActivationObserver)
        }
        panelController.terminateSession()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        panelController.show()
        return true
    }

    @objc private func toggleTerminal() {
        panelController.toggle()
    }

    @objc private func openSettings() {
        settingsWindowController.present()
    }

    @objc private func copyLastCommandOutput() {
        panelController.copyLastCommandOutput()
    }

    @objc private func copySelection() {
        panelController.copySelection()
    }

    @objc private func pasteClipboard() {
        panelController.pasteClipboard()
    }

    @objc private func selectAllText() {
        panelController.selectAllText()
    }

    @objc private func newTab() { panelController.newTab() }
    @objc private func closeCurrentTab() { panelController.closeCurrentTab() }
    @objc private func selectTab(_ sender: NSMenuItem) { panelController.selectTab(sender.tag) }
    @objc private func selectNextTab() { panelController.selectNextTab() }
    @objc private func selectPreviousTab() { panelController.selectPreviousTab() }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Toggle DropTerm", action: #selector(toggleTerminal), keyEquivalent: " ")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit DropTerm", action: #selector(quit), keyEquivalent: "q")

        for item in appMenu.items {
            item.target = self
        }

        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        let copyItem = editMenu.addItem(
            withTitle: "Copy",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        copyItem.target = nil
        let pasteItem = editMenu.addItem(
            withTitle: "Paste",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        pasteItem.target = nil
        let copyOutputItem = editMenu.addItem(
            withTitle: "Copy Last Command Output",
            action: #selector(copyLastCommandOutput),
            keyEquivalent: "c"
        )
        copyOutputItem.keyEquivalentModifierMask = [.command, .shift]
        copyOutputItem.target = self
        editMenu.addItem(.separator())
        let selectAllItem = editMenu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        selectAllItem.target = nil
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let shellItem = NSMenuItem()
        let shellMenu = NSMenu(title: "Shell")
        let newTabItem = shellMenu.addItem(withTitle: "New Tab", action: #selector(newTab), keyEquivalent: "t")
        newTabItem.target = self
        let closeTabItem = shellMenu.addItem(withTitle: "Close Tab", action: #selector(closeCurrentTab), keyEquivalent: "w")
        closeTabItem.target = self
        shellMenu.addItem(.separator())
        for index in 0..<9 {
            let item = shellMenu.addItem(withTitle: "Select Tab \(index + 1)", action: #selector(selectTab(_:)), keyEquivalent: "\(index + 1)")
            item.tag = index
            item.target = self
        }
        shellMenu.addItem(.separator())
        let nextItem = shellMenu.addItem(withTitle: "Next Tab", action: #selector(selectNextTab), keyEquivalent: "\t")
        nextItem.keyEquivalentModifierMask = [.control]
        nextItem.target = self
        let previousItem = shellMenu.addItem(withTitle: "Previous Tab", action: #selector(selectPreviousTab), keyEquivalent: "\t")
        previousItem.keyEquivalentModifierMask = [.control, .shift]
        previousItem.target = self
        shellItem.submenu = shellMenu
        mainMenu.addItem(shellItem)

        NSApp.mainMenu = mainMenu
    }

    private func installStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "terminal.fill",
            accessibilityDescription: "DropTerm"
        )
        statusItem.button?.toolTip = "DropTerm"

        let menu = NSMenu()
        menu.addItem(withTitle: "Show or Hide DropTerm", action: #selector(toggleTerminal), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit DropTerm", action: #selector(quit), keyEquivalent: "")

        for item in menu.items {
            item.target = self
        }

        statusItem.menu = menu
        self.statusItem = statusItem
    }

    private func installGlobalHotKey() {
        hotKeyService?.invalidate()
        hotKeyService = nil
        do {
            hotKeyService = try GlobalHotKeyService.register(shortcut: settings.globalShortcut) { [weak self] in
                self?.panelController.toggle()
            }
        } catch {
            NSLog("DropTerm could not register %@: %@", settings.globalShortcut.displayName, error.localizedDescription)
        }
    }

    private func observeWorkspaceActivation() {
        workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            else {
                return
            }

            Task { @MainActor [weak self] in
                self?.updateHotKeyRegistration(for: application)
            }
        }
    }

    private func updateHotKeyRegistration(for application: NSRunningApplication?) {
        let shouldSuppress = application?.bundleIdentifier?.hasPrefix("com.parallels.") == true
        guard shouldSuppress != isHotKeySuppressedForParallels else { return }

        isHotKeySuppressedForParallels = shouldSuppress

        if shouldSuppress {
            panelController.hide()
            hotKeyService?.invalidate()
            hotKeyService = nil
        } else {
            installGlobalHotKey()
        }
    }
}
