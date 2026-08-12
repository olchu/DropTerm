# DropTerm product specification

Status: Draft 0.1  
Platform: macOS 15+  
Working title: DropTerm

## 1. Product statement

DropTerm is a fast, keyboard-first terminal that appears from the bottom edge of the display on demand. It should feel like a system overlay rather than a conventional desktop window.

The first release is not intended to replace every iTerm2 feature. It focuses on an excellent single-session drop-down workflow while preserving compatibility with real terminal applications and customized shells.

## 2. Primary user story

As a macOS user, I press a configurable global shortcut from any application, immediately get my existing shell session on the current display, run commands, and dismiss the terminal with the same shortcut or Escape.

## 3. MVP scope

### Window behavior

- A global shortcut shows or hides the panel. Default proposal: Option+Space.
- The panel opens on the display containing the mouse pointer.
- It slides from the bottom edge and occupies 40% of the display's visible height.
- It is borderless, floats above normal windows, and does not create a normal Dock window.
- Background uses native macOS material with adjustable opacity.
- Animation respects Reduce Motion.
- Optional setting: hide when the panel loses focus.

### Terminal behavior

- Launch the user's login shell, with `zsh` as the fallback.
- Use a real pseudo-terminal (PTY), not redirected stdin/stdout pipes.
- Support common VT/ANSI control sequences, alternate screen, cursor movement, scrollback, selection, copy/paste, bracketed paste, mouse reporting, and window resize.
- Expose `TERM` and true-color capability consistently with the selected terminal engine.
- Work correctly with Powerlevel10k, `vim`/`nvim`, `tmux`, `less`, SSH, and interactive CLI tools.
- Keep the shell process alive while the panel is hidden.

### Typography and Powerlevel10k

- Let the user select any installed monospaced font.
- Prefer `MesloLGS NF` when installed; fall back to a system monospaced font.
- Support Nerd Font private-use glyphs, Unicode combining marks, emoji, ligatures where supported, and double-width characters.
- Do not bundle MesloLGS NF until its redistribution terms and package size are explicitly reviewed. The app should detect it and offer installation guidance.

### Settings

- Global shortcut.
- Shell executable and optional launch arguments.
- Font family and size.
- Panel height, material, opacity, and animation duration.
- Hide-on-focus-loss behavior.

## 4. Explicitly out of scope for MVP

- Tabs and split panes.
- Profiles synchronized through iCloud.
- Triggers, badges, shell integration, semantic history, and password manager integration.
- GPU renderer written from scratch.
- Remote session management UI.
- Full iTerm2 feature parity.

## 5. Quality requirements

- Warm show latency target: under 100 ms from shortcut to visible animation.
- No shell restart when hiding and showing the panel.
- Smooth resize and animation at the display refresh rate.
- No dropped or reordered PTY bytes during normal interactive use.
- Keyboard navigation and VoiceOver labels for settings.
- No command content, environment variables, or terminal history collected by analytics.
- Shell child process is terminated gracefully on explicit session close and app quit.

## 6. Acceptance scenarios

1. With Powerlevel10k configured and MesloLGS NF selected, prompt segments and icons render without replacement squares.
2. `printf '\e[38;2;255;100;0mtruecolor\e[0m\n'` displays the expected 24-bit color.
3. Opening `vim`, resizing the panel, entering alternate screen, and exiting restores the prior scrollback correctly.
4. `tmux` starts, receives shortcuts, redraws correctly after resize, and supports mouse mode.
5. Hiding and showing DropTerm preserves the running command and current directory.
6. The shortcut opens the panel on the display under the pointer.
7. Reduce Motion replaces the slide with a minimal fade or immediate transition.

## 7. Later releases

- Multiple tabs and split panes.
- Profiles and per-profile themes.
- Searchable scrollback.
- Quake-style top-edge mode and custom placement.
- Shell integration for current directory, command status, and semantic selection.
- Session restoration after application restart where technically safe.

