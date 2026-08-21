import AppKit

/// DropTerm's brand palette. Other UI colors are derived from `accent` rather than
/// hardcoded separately, so panels stay visually related to the brand red.
enum AppColors {
    private static let accentComponents: (r: CGFloat, g: CGFloat, b: CGFloat) = (1.0, 0.2196, 0.2353)

    static let accent = NSColor(
        calibratedRed: accentComponents.r,
        green: accentComponents.g,
        blue: accentComponents.b,
        alpha: 1
    )

    /// A near-black panel background tinted with `accent`, used behind sidebars and floating panels.
    static func panelBackground(tint: CGFloat, alpha: CGFloat) -> NSColor {
        NSColor(
            calibratedRed: accentComponents.r * tint,
            green: accentComponents.g * tint,
            blue: accentComponents.b * tint,
            alpha: alpha
        )
    }
}
