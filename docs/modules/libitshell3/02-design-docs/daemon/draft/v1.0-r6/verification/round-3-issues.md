# Verification Round 3 Issues — Daemon v1.0-r6

- **Date**: 2026-03-24
- **Phase 1 agents**: consistency-verifier (sonnet), semantic-verifier (sonnet)
- **Phase 2**: Skipped — owner declared clean after sweep fix + team leader
  review

---

## Issues Found (Phase 1)

### SEM-01 / CRX-11 (minor, merged) — MouseScroll/MouseMove API inconsistency

- **Description**: doc01 §5.2 used `terminal.mouse*(event)` while doc02 §4.8
  used `write(pty_fd, mouse escape sequence)` for non-button mouse events.
  Cascading inconsistency from Round 2 SEM-05 fix (parallel writers diverged).
- **Fix**: Sweeper updated both to
  `terminal.mouseScroll() / terminal.mousePos()` (confirmed against ghostty C
  API). Also updated doc03 §4.5 prose.
- **Verified clean** by team leader (grep confirms zero remaining raw PTY write
  for mouse events in spec docs).

### TRM-02 (minor) — `keyboard_layout` vs `active_keyboard_layout`

- **Description**: doc02 §4.1 line 328 used bare `keyboard_layout` instead of
  `active_keyboard_layout` (the canonical field name per doc01 §3.3).
- **Fix**: Sweeper updated to `active_keyboard_layout`.
- **Verified clean** by team leader (grep confirms all occurrences consistent).

---

## Dismissed Issues

None.

---

## Result

**Owner declared clean** after sweep fixes and team leader review. No Phase 2
needed.
