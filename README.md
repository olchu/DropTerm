# DropTerm

DropTerm is a native macOS drop-down terminal: press a global shortcut and a translucent terminal panel slides up from the bottom of the active display.

The repository currently contains the product specification, architecture decisions, delivery plan, and a compilable UI foundation. The terminal emulator is intentionally isolated behind a boundary so a proven ANSI/VT engine can be integrated without coupling it to window behavior.

## Current foundation

- native Swift 6 / SwiftUI + AppKit application shell;
- borderless floating `NSPanel` with system material;
- show/hide animation from the bottom of the active display;
- a real login shell connected through SwiftTerm's PTY-backed terminal view;
- True Color, Unicode, selection, clipboard, scrollback, and terminal resize support;
- minimal MV architecture with injected services;
- unit-test target;
- product and technical specifications in `Docs/`.

## Open locally

```sh
open Package.swift
```

Xcode can open the Swift package directly. Select the `DropTerm` scheme and run it. The terminal panel appears immediately, and a terminal icon remains in the macOS menu bar for show/hide and quit commands. Press Shift+Command+E globally to show or hide the panel while keeping the shell session alive.

Command-line verification:

```sh
swift test
```

## Documentation

- [Product specification](Docs/SPEC.md)
- [Architecture](Docs/ARCHITECTURE.md)
- [Roadmap](Docs/ROADMAP.md)
- [Decisions and open questions](Docs/DECISIONS.md)
