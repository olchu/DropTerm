import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    var panelHeightRatio: Double {
        didSet { persist(panelHeightRatio, for: .panelHeightRatio) }
    }

    var backgroundOpacity: Double {
        didSet { persist(backgroundOpacity, for: .backgroundOpacity) }
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

    var hideOnDeactivate: Bool {
        didSet { persist(hideOnDeactivate, for: .hideOnDeactivate) }
    }

    var showOnLaunch: Bool {
        didSet { persist(showOnLaunch, for: .showOnLaunch) }
    }

    @ObservationIgnored
    var onChange: (@MainActor () -> Void)?

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
        hideOnDeactivate = defaults.object(forKey: Key.hideOnDeactivate.rawValue) as? Bool ?? false
        showOnLaunch = defaults.object(forKey: Key.showOnLaunch.rawValue) as? Bool ?? true
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

    private enum Key: String {
        case panelHeightRatio = "panel.heightRatio"
        case backgroundOpacity = "appearance.backgroundOpacity"
        case contentPadding = "appearance.contentPadding"
        case fontSize = "terminal.fontSize"
        case fontName = "terminal.fontName"
        case shellPath = "terminal.shellPath"
        case hideOnDeactivate = "behavior.hideOnDeactivate"
        case showOnLaunch = "behavior.showOnLaunch"
    }
}
