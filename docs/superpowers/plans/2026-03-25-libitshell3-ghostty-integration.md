# libitshell3 ghostty Integration Plan (Plan 2)

> **Execution model:** Use the `/implementation` skill. The implementation step
> spawns persistent `implementer` + `qa-reviewer` agents from
> `.claude/agents/impl-team/` that stay alive through Steps 3-8. The
> `ghostty-expert` agent (`.claude/agents/daemon-team/`) is spawned ad-hoc for
> research tasks and disbanded after each.

**Goal:** Integrate vendored ghostty into libitshell3 — Terminal lifecycle, VT
stream processing, RenderState snapshots, key/mouse encoding, cell data export,
and preedit overlay — replacing the opaque `?*anyopaque` placeholders in Pane
with real ghostty types.

**Architecture:** The `ghostty/` module is a thin wrapper around vendored
ghostty APIs. It provides stable interfaces that insulate `server/` from ghostty
API churn. Per the design docs, the daemon runs ghostty in headless mode (no
Surface, no GPU renderer).

**Tech Stack:** Zig 0.15+, vendored libghostty at `vendors/ghostty/`.

**Blocking dependencies:**

- `render_export.zig` (bulkExport, FlatCell, ExportResult) must be ported from
  PoC vendor copy to the vendored submodule
- `overlayPreedit()` must be written from scratch
- HID-to-ghostty-Key comptime mapping table must be authored

---

## Team Composition

| Agent               | Source                                            | Role                                       | When                  |
| ------------------- | ------------------------------------------------- | ------------------------------------------ | --------------------- |
| implementer         | `.claude/agents/impl-team/implementer.md`         | Primary coder (opus)                       | Persistent: Steps 3-8 |
| qa-reviewer         | `.claude/agents/impl-team/qa-reviewer.md`         | Spec compliance + integration tests (opus) | Persistent: Steps 3-8 |
| principal-architect | `.claude/agents/impl-team/principal-architect.md` | Over-engineering review                    | Step 8 only           |
| ghostty-expert      | `.claude/agents/daemon-team/ghostty-expert.md`    | ghostty API research                       | Ad-hoc: Tasks 1, 4, 6 |

---

## Task Dependency Graph & Parallelization

```
Task 1 (build integration) ──── GATE: must pass before any other task
    │
    ├── Task 2 (Terminal wrapper)    ─┐
    ├── Task 3 (RenderState wrapper)  ├── Batch A: 4 tasks in parallel
    ├── Task 6 (Key encoder + HID)    │   (no file conflicts)
    └── Task 7 (Mouse encoder)       ─┘
              │
         Task 4 (render_export port) ── Batch B: needs Tasks 2+3
              │
         Task 5 (preedit overlay)    ── Batch C: needs Task 4
              │
         Task 8 (wire up + Pane)     ── Batch D: needs all above
```

**Execution schedule:**

| Batch | Tasks      | Parallelism       | Agent assignment                                          |
| ----- | ---------- | ----------------- | --------------------------------------------------------- |
| Gate  | 1          | Sequential        | ghostty-expert researches, implementer builds             |
| A     | 2, 3, 6, 7 | All 4 in parallel | implementer writes; QA tests completed files as they land |
| B     | 4          | Sequential        | ghostty-expert assists PoC port, implementer codes        |
| C     | 5          | Sequential        | implementer codes                                         |
| D     | 8          | Sequential        | implementer integrates, QA runs full suite                |

---

**Design spec references:**

- `daemon-architecture/.../03-integration-boundaries.md` §3-5
- `daemon-architecture/.../01-module-structure.md` §1.2 (ghostty/ helpers)
- `daemon-architecture/.../02-state-and-types.md` §3 (data flow)
- `docs/insights/ghostty-api-extensions.md`

---

## API Availability Matrix

| API                                  | Vendored ghostty | PoC copy  | Must write |
| ------------------------------------ | ---------------- | --------- | ---------- |
| Terminal.init/deinit/resize          | Yes              | —         | —          |
| Terminal.vtStream                    | Yes              | —         | —          |
| RenderState.update                   | Yes (render.zig) | —         | —          |
| key_encode.encode                    | Yes              | —         | —          |
| key_encode.Options.fromTerminal      | Yes              | —         | —          |
| mouse_encode.encode                  | Yes              | —         | —          |
| bulkExport / FlatCell / ExportResult | No               | PoC 06-07 | Port       |
| importFlatCells                      | No               | PoC 08    | Port       |
| overlayPreedit                       | No               | No        | Author     |
| HID→ghostty Key table                | No               | No        | Author     |

---

## File Structure

```
modules/libitshell3/src/
├── ghostty/
│   ├── terminal.zig         # Terminal lifecycle wrapper (init, deinit, resize, feed)
│   ├── render_state.zig     # RenderState.update wrapper + dirty tracking
│   ├── render_export.zig    # bulkExport, FlatCell, ExportResult (ported from PoC)
│   ├── key_encoder.zig      # key_encode wrapper + HID→Key translation
│   ├── mouse_encoder.zig    # mouse_encode wrapper
│   ├── preedit_overlay.zig  # overlayPreedit (written from scratch)
│   └── types.zig            # Re-exports of ghostty types needed by server/
```

---

## Task 1: Vendor ghostty Build Integration

**Files:**

- Modify: `modules/libitshell3/build.zig`

- [ ] **Step 1: Add ghostty as a build dependency**

The ghostty source at `vendors/ghostty/` must be importable. Add the ghostty
source tree to the build as a module dependency so `@import("ghostty/...")`
works from libitshell3 source files.

- [ ] **Step 2: Verify build compiles with ghostty import**
- [ ] **Step 3: Commit**

---

## Task 2: Terminal Lifecycle Wrapper

**Files:**

- Create: `modules/libitshell3/src/ghostty/terminal.zig`
- Modify: `modules/libitshell3/src/core/pane.zig` (replace `?*anyopaque`)

Wrap ghostty Terminal with stable interface:

- `TerminalWrapper.init(alloc, cols, rows) -> !TerminalWrapper`
- `TerminalWrapper.deinit(alloc) -> void`
- `TerminalWrapper.resize(alloc, cols, rows) -> !void`
- `TerminalWrapper.feed(bytes: []const u8) -> void` (wraps vtStream)
- `TerminalWrapper.terminal() -> *Terminal` (raw access for key_encode)

Replace `pane.terminal: ?*anyopaque` with `pane.terminal: ?*TerminalWrapper`.

Tests: init/deinit, feed bytes + verify terminal state changed, resize.

---

## Task 3: RenderState Wrapper

**Files:**

- Create: `modules/libitshell3/src/ghostty/render_state.zig`
- Modify: `modules/libitshell3/src/core/pane.zig`

Wrap ghostty RenderState:

- `RenderStateWrapper.init(alloc) -> !RenderStateWrapper`
- `RenderStateWrapper.update(alloc, terminal) -> !void`
- `RenderStateWrapper.isDirty() -> bool`
- `RenderStateWrapper.dirtyRows() -> iterator`

Replace `pane.render_state: ?*anyopaque` with `?*RenderStateWrapper`.

Tests: update after terminal feed → dirty, update without changes → not dirty.

---

## Task 4: Port render_export.zig (bulkExport + FlatCell)

**Files:**

- Create: `modules/libitshell3/src/ghostty/render_export.zig`

Port from PoC vendor copy. Key types:

- `FlatCell` (16-byte extern struct, C ABI) — called CellData at wire level
- `PackedColor` (4-byte extern struct)
- `ExportResult` — cells array + dirty bitmap + metadata
- `bulkExport(alloc, render_state, terminal) -> !ExportResult`
- `freeExport(alloc, result) -> void`

Must adapt to current vendored ghostty commit (PoC was against older commit).

Tests: feed VT sequences to terminal → update render state → bulkExport → verify
FlatCell data matches expected content.

---

## Task 5: Preedit Overlay

**Files:**

- Create: `modules/libitshell3/src/ghostty/preedit_overlay.zig`

Write from scratch. Reference: `renderer.State.Preedit.range()` for width
overflow / edge clamping logic.

- `overlayPreedit(result: *ExportResult, preedit: []const Codepoint, cursor_row: u16, cursor_col: u16) -> void`

Overwrites FlatCell entries at cursor position with preedit codepoints. Handles:

- Wide characters (CJK takes 2 cells)
- Screen edge clamping (preedit at right edge wraps or truncates)
- Empty preedit = no-op (clear is handled by not calling overlay)

Tests: overlay "한" (wide) at cursor position → verify 2 FlatCells modified.
Overlay at right edge → verify clamping. Overlay empty → no change.

---

## Task 6: Key Encoder + HID→Key Translation

**Files:**

- Create: `modules/libitshell3/src/ghostty/key_encoder.zig`

Wraps `key_encode.encode()` with HID keycode translation:

- `encode(hid_keycode: u8, mods: Mods, terminal: *Terminal) -> ![]const u8`

Must author the HID-to-ghostty-Key comptime lookup table. Reference: ghostty's
`Key` enum at `src/input/key.zig`. Map standard HID Usage Page 0x07 keycodes to
ghostty semantic Key values.

Tests: encode key_a → correct escape sequence. Encode with ctrl mod. Encode
arrow keys. Encode in application cursor mode.

---

## Task 7: Mouse Encoder

**Files:**

- Create: `modules/libitshell3/src/ghostty/mouse_encoder.zig`

Thin wrapper around `mouse_encode.encode()`:

- `encode(button, x, y, mods, terminal) -> ![]const u8`

Tests: encode left click at (10, 5) → correct SGR sequence.

---

## Task 8: Wire Up ghostty/ Module + Update Pane

**Files:**

- Create: `modules/libitshell3/src/ghostty/types.zig`
- Modify: `modules/libitshell3/src/root.zig`
- Modify: `modules/libitshell3/src/core/pane.zig`
- Modify: `modules/libitshell3/src/server/handlers/pty_read.zig`

Replace PTY read handler's "read and discard" with:

1. Read from PTY → feed to terminal.vtStream
2. Mark pane dirty

Update Pane to use real ghostty types instead of `?*anyopaque`.

Tests: full pipeline — create pane with Terminal, feed PTY data, verify render
state is dirty.

---

## Summary

| Task | Component               | Complexity | Blocker              |
| ---- | ----------------------- | ---------- | -------------------- |
| 1    | Build integration       | Medium     | ghostty build system |
| 2    | Terminal wrapper        | Low        | Task 1               |
| 3    | RenderState wrapper     | Low        | Task 1               |
| 4    | render_export port      | High       | PoC adaptation       |
| 5    | Preedit overlay         | Medium     | Task 4               |
| 6    | Key encoder + HID table | High       | Must author table    |
| 7    | Mouse encoder           | Low        | Task 1               |
| 8    | Wire up + update Pane   | Medium     | Tasks 2-7            |

**Critical risk:** Task 1 (ghostty build integration) may surface Zig version
incompatibilities with the vendored ghostty commit. If the vendored ghostty
doesn't build with Zig 0.15, the submodule pin must be updated first.
