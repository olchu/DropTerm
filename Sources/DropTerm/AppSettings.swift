import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings(defaults: persistentDefaults())

    var panelHeightRatio: Double {
        didSet { persist(panelHeightRatio, for: .panelHeightRatio) }
    }

    var backgroundOpacity: Double {
        didSet { persist(backgroundOpacity, for: .backgroundOpacity) }
    }

    var panelOpacity: Double {
        didSet { persist(panelOpacity, for: .panelOpacity) }
    }

    var contentPadding: Double {
        didSet { persist(contentPadding, for: .contentPadding) }
    }

    var fontSize: Double {
        didSet { persist(fontSize, for: .fontSize) }
    }

    var fontName: String {
        didSet { persist(fontName, for: .fontName) }
    }

    var shellPath: String {
        didSet { persist(shellPath, for: .shellPath) }
    }

    var startingDirectory: String {
        didSet { persist(startingDirectory, for: .startingDirectory) }
    }

    var hideOnDeactivate: Bool {
        didSet { persist(hideOnDeactivate, for: .hideOnDeactivate) }
    }

    var showOnLaunch: Bool {
        didSet { persist(showOnLaunch, for: .showOnLaunch) }
    }

    var globalShortcut: GlobalShortcut {
        didSet {
            defaults.set(Int(globalShortcut.keyCode), forKey: Key.hotKeyCode.rawValue)
            defaults.set(Int(globalShortcut.modifiers), forKey: Key.hotKeyModifiers.rawValue)
            onHotKeyChange?()
        }
    }

    @ObservationIgnored
    var onChange: (@MainActor () -> Void)?

    @ObservationIgnored
    var onHotKeyChange: (@MainActor () -> Void)?

    @ObservationIgnored
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        panelHeightRatio = Self.double(
            in: defaults,
            key: .panelHeightRatio,
            default: 0.4,
            range: 0.2...0.8
        )
        backgroundOpacity = Self.double(
            in: defaults,
            key: .backgroundOpacity,
            default: 0.12,
            range: 0...0.6
        )
        panelOpacity = Self.double(
            in: defaults,
            key: .panelOpacity,
            default: 1,
            range: 0.45...1
        )
        contentPadding = Self.double(
            in: defaults,
            key: .contentPadding,
            default: 14,
            range: 0...40
        )
        fontSize = Self.double(
            in: defaults,
            key: .fontSize,
            default: 14,
            range: 10...28
        )
        fontName = defaults.string(forKey: Key.fontName.rawValue) ?? "Automatic"
        shellPath = defaults.string(forKey: Key.shellPath.rawValue)
            ?? ProcessInfo.processInfo.environment["SHELL"]
            ?? "/bin/zsh"
        startingDirectory = defaults.string(forKey: Key.startingDirectory.rawValue)
            ?? FileManager.default.homeDirectoryForCurrentUser.path
        hideOnDeactivate = defaults.object(forKey: Key.hideOnDeactivate.rawValue) as? Bool ?? false
        showOnLaunch = defaults.object(forKey: Key.showOnLaunch.rawValue) as? Bool ?? true
        if defaults.object(forKey: Key.hotKeyCode.rawValue) != nil,
           defaults.object(forKey: Key.hotKeyModifiers.rawValue) != nil {
            globalShortcut = GlobalShortcut(
                keyCode: UInt32(defaults.integer(forKey: Key.hotKeyCode.rawValue)),
                modifiers: UInt32(defaults.integer(forKey: Key.hotKeyModifiers.rawValue))
            )
        } else {
            globalShortcut = .defaultShortcut
        }
    }

    private static func persistentDefaults() -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: "com.olchu.DropTerm") else {
            return .standard
        }

        let legacyDefaults = UserDefaults.standard
        for key in Key.allCases where defaults.object(forKey: key.rawValue) == nil {
            if let value = legacyDefaults.object(forKey: key.rawValue) {
                defaults.set(value, forKey: key.rawValue)
            }
        }
        return defaults
    }

    private func persist(_ value: Any, for key: Key) {
        defaults.set(value, forKey: key.rawValue)
        onChange?()
    }

    private static func double(
        in defaults: UserDefaults,
        key: Key,
        default defaultValue: Double,
        range: ClosedRange<Double>
    ) -> Double {
        guard defaults.object(forKey: key.rawValue) != nil else { return defaultValue }
        return min(max(defaults.double(forKey: key.rawValue), range.lowerBound), range.upperBound)
    }

    private enum Key: String, CaseIterable {
        case panelHeightRatio = "panel.heightRatio"
        case backgroundOpacity = "appearance.backgroundOpacity"
        case panelOpacity = "appearance.panelOpacity"
        case contentPadding = "appearance.contentPadding"
        case fontSize = "terminal.fontSize"
        case fontName = "terminal.fontName"
        case shellPath = "terminal.shellPath"
        case startingDirectory = "terminal.startingDirectory"
        case hideOnDeactivate = "behavior.hideOnDeactivate"
        case showOnLaunch = "behavior.showOnLaunch"
        case hotKeyCode = "behavior.hotKeyCode"
        case hotKeyModifiers = "behavior.hotKeyModifiers"
    }
}
