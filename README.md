# DropTerm

DropTerm is a native macOS drop-down terminal: press a global shortcut and a translucent terminal panel slides up from the bottom of the active display.

The repository currently contains the product specification, architecture decisions, delivery plan, and a compilable UI foundation. The terminal emulator is intentionally isolated behind a boundary so a proven ANSI/VT engine can be integrated without coupling it to window behavior.

## Current foundation

- native Swift 6 / SwiftUI + AppKit application shell;
- borderless floating `NSPanel` with system material;
- show/hide animation from the bottom of the active display;
- a real login shell connected through SwiftTerm's PTY-backed terminal view;
- True Color, Unicode, selection, clipboard, scrollback, and terminal resize support;
- persistent live settings for height, darkening, padding, font, and focus behavior;
- minimal MV architecture with injected services;
- unit-test target;
- product and technical specifications in `Docs/`.

## Open locally

```sh
open DropTerm.xcodeproj
```

Select the `DropTerm` scheme and run it. The app target has the stable bundle identifier `com.olchu.DropTerm` and uses the configured Apple Development Team, allowing macOS to remember Files & Folders permissions across rebuilds. DropTerm appears in both the Dock and the macOS menu bar; clicking its Dock icon shows the terminal. Press Shift+Command+E globally to show or hide the panel while keeping the shell session alive.

Regenerate the Xcode project after changing its structure with:

```sh
ruby scripts/generate_xcode_project.rb
```

Command-line verification:

```sh
swift test
```

## Documentation

- [Product specification](Docs/SPEC.md)
- [Architecture](Docs/ARCHITECTURE.md)
- [Roadmap](Docs/ROADMAP.md)
- [Decisions and open questions](Docs/DECISIONS.md)
