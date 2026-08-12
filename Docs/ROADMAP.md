# Roadmap

## Phase 0 — Foundation (current)

- [x] Product specification and acceptance criteria.
- [x] Initial architecture and module boundaries.
- [x] Compilable Swift package application shell.
- [x] Reusable material panel and bottom-edge animation prototype.
- [x] Unit-test target and first geometry tests.
- [ ] Confirm product name and bundle identifier.

## Phase 1 — Functional terminal MVP

- [x] Select and integrate SwiftTerm as the terminal engine.
- [x] Implement PTY-backed login shell lifecycle.
- [x] Propagate terminal size changes to the PTY through SwiftTerm.
- [x] Implement input, selection, clipboard, scrollback, and focus behavior through SwiftTerm.
- [x] Register Shift+Command+E as the initial global shortcut.
- [ ] Make the global shortcut configurable in Settings.
- [x] Detect MesloLGS NF and provide a safe fallback.
- [ ] Validate Powerlevel10k, true color, vim, and tmux acceptance scenarios.

## Phase 2 — Product polish

- [x] Live settings for panel height, darkening, padding, typography, and behavior.
- [x] Persist settings between launches.
- [ ] Restart the shell session from Settings after changing its executable.
- [ ] Launch at login.
- [ ] Multi-display and Spaces regression coverage.
- [ ] Accessibility and Reduce Motion behavior.
- [ ] Crash-safe child-process cleanup.
- [ ] App icon, signing, notarization, update and distribution plan.

## Phase 3 — Expanded terminal experience

- [ ] Tabs and split panes.
- [ ] Profiles and themes.
- [ ] Searchable scrollback.
- [ ] Shell integration and semantic actions.
