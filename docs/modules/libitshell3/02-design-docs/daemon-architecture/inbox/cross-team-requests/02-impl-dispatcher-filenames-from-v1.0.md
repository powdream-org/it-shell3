# Dispatcher Filenames: Spec Names → Code Names

- **Date**: 2026-04-02
- **Source team**: impl
- **Source version**: libitshell3 Plan 8 verification
- **Source resolution**: Plan 8 Step 3 triage (SC-2)
- **Target docs**: daemon-architecture 01-module-structure.md
- **Status**: open

---

## Context

Plan 8 verification found all six dispatcher filenames in the spec differ from
code. The code uses a `_dispatcher` suffix convention adopted during Plan 7.5.
Two files also have semantic name changes: `handshake` → `lifecycle` (0x00xx
covers handshake AND error messages) and `subscription` → `flow_control`
(matches protocol spec's 0x05xx "Flow control and auxiliary" category name).

## Required Changes

1. **01-module-structure.md Section 2.6**: Update dispatcher filenames:
   - `handshake.zig` → `lifecycle_dispatcher.zig`
   - `session_pane.zig` → `session_pane_dispatcher.zig`
   - `input.zig` → `input_dispatcher.zig`
   - `render.zig` → `render_dispatcher.zig`
   - `ime.zig` → `ime_dispatcher.zig`
   - `subscription.zig` → `flow_control_dispatcher.zig`

## Summary Table

| Target Doc             | Section/Message       | Change Type     | Source Resolution |
| ---------------------- | --------------------- | --------------- | ----------------- |
| 01-module-structure.md | §2.6 dispatcher table | Filename update | SC-2 triage       |
