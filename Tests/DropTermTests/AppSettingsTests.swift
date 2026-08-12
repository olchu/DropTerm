import Foundation
import Testing
@testable import DropTerm

@MainActor
@Suite("App settings")
struct AppSettingsTests {
    @Test("Values persist across settings instances")
    func persistence() throws {
        let suiteName = "DropTermTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        settings.panelHeightRatio = 0.55
        settings.backgroundOpacity = 0.24
        settings.panelOpacity = 0.72
        settings.contentPadding = 18
        settings.fontSize = 16
        settings.fontName = "Menlo"
        settings.shellPath = "/bin/zsh"
        settings.startingDirectory = "/tmp"
        settings.hideOnDeactivate = true
        settings.showOnLaunch = false
        settings.globalShortcut = GlobalShortcut(keyCode: 49, modifiers: 768)
        settings.cursorShape = .underline
        settings.cursorBlink = true

        let restored = AppSettings(defaults: defaults)
        #expect(restored.panelHeightRatio == 0.55)
        #expect(restored.backgroundOpacity == 0.24)
        #expect(restored.panelOpacity == 0.72)
        #expect(restored.contentPadding == 18)
        #expect(restored.fontSize == 16)
        #expect(restored.fontName == "Menlo")
        #expect(restored.shellPath == "/bin/zsh")
        #expect(restored.startingDirectory == "/tmp")
        #expect(restored.hideOnDeactivate)
        #expect(!restored.showOnLaunch)
        #expect(restored.globalShortcut == GlobalShortcut(keyCode: 49, modifiers: 768))
        #expect(restored.cursorShape == .underline)
        #expect(restored.cursorBlink)
    }

    @Test("Stored numeric values are clamped to supported ranges")
    func clamping() throws {
        let suiteName = "DropTermTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(2.0, forKey: "panel.heightRatio")
        defaults.set(-1.0, forKey: "appearance.backgroundOpacity")

        let settings = AppSettings(defaults: defaults)

        #expect(settings.panelHeightRatio == 0.8)
        #expect(settings.backgroundOpacity == 0)
    }
}
