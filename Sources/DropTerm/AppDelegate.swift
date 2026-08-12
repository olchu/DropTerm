import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let panelController = TerminalPanelController()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        installStatusItem()

        // Make the prototype discoverable when launched from Xcode.
        // Later this can become a persisted "show on launch" preference.
        DispatchQueue.main.async { [panelController] in
            panelController.show()
        }
    }

    @objc private func toggleTerminal() {
        panelController.toggle()
    }

    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
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
}
