# Architecture

## Direction

DropTerm uses a small Model–View architecture for the application state, SwiftUI for settings and simple UI, and AppKit for window ownership and terminal hosting. This is intentionally lighter than MVVM/TCA for the MVP.

The terminal core and PTY lifecycle are services, not view responsibilities. The window controller never parses terminal bytes, and the emulator never decides where or how the panel is presented.

```text
DropTermApp / AppDelegate
        |
        +-- AppModel (@Observable, @MainActor)
        |       +-- settings and presentation state
        |
        +-- PanelController (AppKit)
        |       +-- material, screen selection, animation
        |       +-- hosts TerminalSurface
        |
        +-- HotKeyService
        |       +-- global shortcut registration
        |
        +-- TerminalSession
                +-- PTY process lifecycle
                +-- read/write/resize
                +-- TerminalEngine adapter
                        +-- ANSI/VT parsing and rendering
```

## Main boundaries

### `AppModel`

Owns user-visible preferences and high-level state. It is isolated to the main actor. Persistence uses a dedicated settings store rather than `@AppStorage` inside an observable model.

### `PanelController`

Owns one reusable `NSPanel`, chooses the active display, computes visible and hidden frames, and performs show/hide animation. The panel remains alive when hidden so the hosted terminal view and responder state are preserved.

### `TerminalSession`

Owns one login shell child process attached to a PTY. It provides byte-oriented input/output and resize operations. PTY reads must not run on the main actor; decoded terminal state is delivered to the renderer through the selected engine's concurrency model.

### `TerminalEngine`

An adapter around a proven terminal emulator. Before selection, candidates must be validated against:

- Swift 6 strict concurrency and macOS 15+;
- ANSI/VT coverage and true color;
- alternate screen, bracketed paste, mouse mode, and resize;
- Unicode width and Nerd Font rendering;
- accessibility, selection, clipboard, scrollback, and IME input;
- license, maintenance activity, binary size, and rendering performance.

The project should not implement a VT parser or text grid renderer from scratch for MVP.

## Concurrency

- UI and application state: `@MainActor`.
- Blocking PTY reads: dedicated descriptor source or background execution context.
- Bytes retain ordering from the PTY to the terminal engine.
- Session shutdown is explicit and idempotent.
- Types crossing isolation boundaries are `Sendable` or wrapped behind actor-safe interfaces.

## Testing layers

- Pure tests for panel frame calculations and settings validation.
- PTY integration tests using a deterministic child command.
- Emulator compatibility fixtures for colors, cursor movement, Unicode width, and alternate screen.
- Manual smoke matrix: Powerlevel10k, tmux, vim/neovim, SSH, resize, multiple displays, Spaces, and full-screen apps.

## Security and privacy

- No shell output or command history leaves the process.
- No implicit environment logging.
- Pasted multi-line commands should support an optional confirmation safeguard.
- The shell inherits a deliberately reviewed environment and starts as the user's login shell.
- App Sandbox requirements must be prototyped before distribution strategy is finalized; PTY and child-process behavior are a release-blocking validation item.

