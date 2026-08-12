# DropTerm

DropTerm is a native macOS drop-down terminal: press a global shortcut and a translucent terminal panel slides up from the bottom of the active display.

The repository currently contains the product specification, architecture decisions, delivery plan, and a compilable UI foundation. The terminal emulator is intentionally isolated behind a boundary so a proven ANSI/VT engine can be integrated without coupling it to window behavior.

## Current foundation

- native Swift 6 / SwiftUI + AppKit application shell;
- borderless floating `NSPanel` with system material;
- show/hide animation from the bottom of the active display;
- minimal MV architecture with injected services;
- unit-test target;
- product and technical specifications in `Docs/`.

## Open locally

```sh
open Package.swift
```

Xcode can open the Swift package directly. Select the `DropTerm` scheme and run it. The current shortcut is available from the menu bar; global shortcut registration and the terminal engine are the first implementation milestone.

Command-line verification:

```sh
swift test
```

## Documentation

- [Product specification](Docs/SPEC.md)
- [Architecture](Docs/ARCHITECTURE.md)
- [Roadmap](Docs/ROADMAP.md)
- [Decisions and open questions](Docs/DECISIONS.md)

