import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared
    private lazy var panelController = TerminalPanelController(settings: settings)
    private lazy var settingsWindowController = SettingsWindowController(settings: settings)
    private var hotKeyService: GlobalHotKeyService?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        applyBundleIcon()
        installMainMenu()
        installStatusItem()
        installGlobalHotKey()

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
            action: #selector(copySelection),
            keyEquivalent: "c"
        )
        copyItem.target = self
        let pasteItem = editMenu.addItem(
            withTitle: "Paste",
            action: #selector(pasteClipboard),
            keyEquivalent: "v"
        )
        pasteItem.target = self
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
            action: #selector(selectAllText),
            keyEquivalent: "a"
        )
        selectAllItem.target = self
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

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
        do {
            hotKeyService = try GlobalHotKeyService.shiftCommandE { [weak self] in
                self?.panelController.toggle()
            }
        } catch {
            NSLog("DropTerm could not register Shift-Command-E: %@", error.localizedDescription)
        }
    }
}
