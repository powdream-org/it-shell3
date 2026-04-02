# Dispatcher Directory Path: server/dispatch/ → server/handlers/

- **Date**: 2026-04-02
- **Source team**: impl
- **Source version**: libitshell3 Plan 8 verification
- **Source resolution**: Plan 8 Step 3 triage (SC-1)
- **Target docs**: daemon-architecture 01-module-structure.md
- **Status**: open

---

## Context

Plan 8 verification (spec-code-verifier) found that the spec defines category
dispatchers under `server/dispatch/` (Section 2.6) but all six dispatchers were
implemented under `server/handlers/` during Plan 7.5 (dispatcher refactor, ADR
00064). The `server/dispatch/` directory does not exist and was never created.
The organizational pattern (category-based dispatch) is correctly implemented —
only the directory path differs.

## Required Changes

1. **01-module-structure.md Section 2.6**: Update dispatcher table path
   annotations from `server/dispatch/` to `server/handlers/`. All six entries
   affected.

## Summary Table

| Target Doc             | Section/Message       | Change Type | Source Resolution |
| ---------------------- | --------------------- | ----------- | ----------------- |
| 01-module-structure.md | §2.6 dispatcher table | Path update | SC-1 triage       |
