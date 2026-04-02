# Input Module Table: Remove Functions Located in server/ime/

- **Date**: 2026-04-02
- **Source team**: impl
- **Source version**: libitshell3 Plan 8 verification
- **Source resolution**: Plan 8 Step 3 triage (SC-10)
- **Target docs**: daemon-architecture 01-module-structure.md
- **Status**: open

---

## Context

Plan 8 verification found the spec places `handleIntraSessionFocusChange` and
`handleInputMethodSwitch` in the `input/` module (Section 1.2). The code
implements equivalent functions (`onFocusChange` and `onInputMethodSwitch`) in
`server/ime/procedures.zig`.

The code's placement is architecturally correct: both functions require PTY
write access (to flush composition text) and broadcast infrastructure (to send
preedit messages). These are `server/` responsibilities. Placing them in
`input/` (which depends only on `core/`) would require `input/` to depend on
`server/`, creating a circular dependency.

## Required Changes

1. **01-module-structure.md Section 1.2**: Remove
   `handleIntraSessionFocusChange` and `handleInputMethodSwitch` from the
   `input/` module table.

2. **01-module-structure.md**: Add or update the `server/ime/` module
   description to document `onFocusChange` and `onInputMethodSwitch` as the
   actual locations of these functions. Note the rationale: they require PTY I/O
   and broadcast, which are `server/` scope.

## Summary Table

| Target Doc             | Section/Message         | Change Type    | Source Resolution |
| ---------------------- | ----------------------- | -------------- | ----------------- |
| 01-module-structure.md | §1.2 input/ table       | Remove entries | SC-10 triage      |
| 01-module-structure.md | server/ime/ description | Add entries    | SC-10 triage      |
