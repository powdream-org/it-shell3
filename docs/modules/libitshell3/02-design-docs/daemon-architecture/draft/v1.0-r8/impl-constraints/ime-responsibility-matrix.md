# IME Responsibility Matrix — Implementation Reference

> **Transient artifact**: Implementer checklist for daemon/IME boundary. Deleted
> when the implementation is complete.

Source: `daemon/draft/v1.0-r7/02-integration-boundaries.md` §4.9

---

The daemon (libitshell3) and the IME engine (libitshell3-ime) have clearly
separated responsibilities. The engine is a pure composition state machine; the
daemon owns routing, lifecycle, I/O, and ghostty integration.

| Responsibility                                                 | Owner                                 | Rationale                                                                                                                                                |
| -------------------------------------------------------------- | ------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Routing & Lifecycle**                                        |                                       |                                                                                                                                                          |
| Per-session ImeEngine lifecycle (create/destroy)               | **daemon**                            | Creates one engine per session, destroys on session close.                                                                                               |
| activate/deactivate on session-level focus change              | **daemon**                            | Calls `deactivate()` when session loses focus, `activate()` when it gains focus.                                                                         |
| flush() on intra-session pane focus change                     | **daemon**                            | Commits composition to old pane before switching focus.                                                                                                  |
| Routing ImeResult to the correct pane's PTY                    | **daemon**                            | Tracks `focused_pane` and directs ImeResult accordingly. Engine is pane-agnostic.                                                                        |
| New pane inheriting active input method                        | **daemon**                            | Automatic — the shared engine already has the correct state. No engine call needed.                                                                      |
| Language toggle key detection                                  | **daemon**                            | Configurable keybinding. Not an IME concern.                                                                                                             |
| Active input method switching                                  | **daemon**                            | Calls `setActiveInputMethod(input_method)` when user toggles.                                                                                            |
| **I/O & ghostty Integration**                                  |                                       |                                                                                                                                                          |
| HID keycode -> platform-native keycode mapping                 | **daemon**                            | ghostty's key encoder uses platform-native keycodes. IME-independent.                                                                                    |
| Writing committed/forwarded text to PTY (`write(pty_fd, ...)`) | **daemon**                            | Translates ImeResult into PTY writes. Committed text: `write(pty_fd, committed_text)`. Forwarded keys: `key_encode.encode()` + `write(pty_fd, encoded)`. |
| Updating preedit overlay state (`session.current_preedit`)     | **daemon**                            | Sets `session.current_preedit = preedit_text` and marks dirty. `overlayPreedit()` applies it at next frame export.                                       |
| Explicit preedit clearing (`session.current_preedit = null`)   | **daemon**                            | Daemon sets null and marks dirty — overlay is cleared at next frame export.                                                                              |
| Terminal escape sequence encoding                              | **daemon** (via ghostty `key_encode`) | ghostty's KeyEncoder runs daemon-side.                                                                                                                   |
| PTY writes                                                     | **daemon**                            | Daemon owns PTY master FDs and performs all writes.                                                                                                      |
| **Protocol & Client Communication**                            |                                       |                                                                                                                                                          |
| Wire-to-KeyEvent decomposition                                 | **daemon**                            | Decomposes protocol modifier bitmask into `KeyEvent.shift` and `KeyEvent.modifiers`.                                                                     |
| Sending preedit/render state to remote client                  | **daemon**                            | Part of the FrameUpdate protocol.                                                                                                                        |
| Language indicator in FrameUpdate metadata                     | **daemon**                            | Derived from `active_input_method` string. ghostty has no language state.                                                                                |
| Composing-capable check                                        | **daemon**                            | `"direct" = no`, anything else = yes. Runtime: `engine.isEmpty()`.                                                                                       |
| `display_width` / UAX #11 character width computation          | **daemon**                            | East Asian Width property lookup for CellData encoding. IME has no width knowledge.                                                                      |
| **Pane Close Handling**                                        |                                       |                                                                                                                                                          |
| Preedit on pane close                                          | **daemon**                            | Calls `engine.reset()` (discard, NOT flush) — see behavior docs.                                                                                         |

For the IME engine's own responsibilities (HID->ASCII mapping, jamo composition,
modifier flush decisions, UCS-4->UTF-8 conversion), see IME contract Section 4
(Responsibility Matrix).
