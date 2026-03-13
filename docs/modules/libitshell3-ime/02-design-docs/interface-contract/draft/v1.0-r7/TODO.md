# IME Contract v0.7 TODO

> **Cross-team revision** with Protocol v0.8. Single topic: composition_state removal.
> Protocol TODO: `docs/modules/libitshell3/02-design-docs/server-client-protocols/draft/v1.0-r8/TODO.md`
> See protocol TODO for full phase tracking. This file tracks IME-specific deliverables only.

## IME Contract Changes (tracked in Protocol v0.8 Phase 3)

- [x] 02-types.md: Remove `composition_state` field from `ImeResult` (Section 3.2)
- [x] 02-types.md: Remove `composition_state` column from scenario matrix (Section 3.2)
- [x] 03-engine-interface.md: Remove `CompositionStates` struct from `HangulImeEngine` (Section 3.7)
- [x] 03-engine-interface.md: Remove composition-state naming convention (Section 3.7)
- [x] 03-engine-interface.md: Update `setActiveInputMethod` return value examples (Section 3.6)
- [x] 04-ghostty-integration.md: Remove `composition_state` memory model note (Section 6)
- [x] 05-extensibility-and-deployment.md: Add `itshell3_preedit_cb` revision note (Section 8)
