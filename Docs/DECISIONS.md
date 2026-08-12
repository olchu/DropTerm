# Decisions and open questions

## Accepted initial decisions

| Topic | Decision | Reason |
| --- | --- | --- |
| Platform | macOS 15+ | Modern Observation and Swift concurrency without legacy compatibility burden. |
| UI | SwiftUI + AppKit | SwiftUI for settings; AppKit provides precise `NSPanel`, responder, and native view control. |
| Architecture | MV with focused services | Enough separation for an MVP without framework overhead. |
| Terminal core | SwiftTerm 1.15+ | It provides a native AppKit terminal, PTY process lifecycle, True Color, Unicode, alternate screen, mouse reporting, selection, and resize support. |
| Shell lifetime | Independent from panel visibility | Hiding the UI must not terminate commands or lose the directory. |
| Font | User-selectable; prefer MesloLGS NF | Powerlevel10k glyph support without silently bundling a third-party font. |

## Open before Phase 1 implementation

1. Product name and bundle identifier.
2. Terminal engine selection after a short proof-of-concept comparison.
3. Direct distribution, Mac App Store, or both. Sandboxing constraints can influence PTY design.
4. Default shortcut: Shift+Command+E may conflict with an existing application shortcut.
5. Whether the panel appears on the pointer display or the currently focused window's display.
6. Whether closing the app should terminate the shell immediately or request confirmation when a foreground job is active.
