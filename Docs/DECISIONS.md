# Decisions and open questions

## Accepted initial decisions

| Topic | Decision | Reason |
| --- | --- | --- |
| Platform | macOS 15+ | Modern Observation and Swift concurrency without legacy compatibility burden. |
| UI | SwiftUI + AppKit | SwiftUI for settings; AppKit provides precise `NSPanel`, responder, and native view control. |
| Architecture | MV with focused services | Enough separation for an MVP without framework overhead. |
| Terminal core | Reuse a proven engine | VT parsing, Unicode width, and interactive app compatibility are too risky to rebuild casually. |
| Shell lifetime | Independent from panel visibility | Hiding the UI must not terminate commands or lose the directory. |
| Font | User-selectable; prefer MesloLGS NF | Powerlevel10k glyph support without silently bundling a third-party font. |

## Open before Phase 1 implementation

1. Product name and bundle identifier.
2. Terminal engine selection after a short proof-of-concept comparison.
3. Direct distribution, Mac App Store, or both. Sandboxing constraints can influence PTY design.
4. Default shortcut: Option+Space may conflict with existing launchers or input-source shortcuts.
5. Whether the panel appears on the pointer display or the currently focused window's display.
6. Whether closing the app should terminate the shell immediately or request confirmation when a foreground job is active.

