# IME Interface Contract v0.8 TODO

> **Cross-team revision** with Daemon v0.3 and Protocol v0.11.
> Single topic: remove daemon behavioral descriptions per cross-team request.
> Daemon TODO (primary): `docs/modules/libitshell3/02-design-docs/daemon/draft/v1.0-r3/TODO.md`
> See daemon v0.3 TODO for full phase tracking. This file tracks IME-specific deliverables only.
>
> Cross-team request: `draft/v1.0-r7/cross-team-requests/01-daemon-behavior-extraction.md`
>
> **Model policy**: writing — **sonnet**; verification — **opus** for history-guardian only
>
> **Note on design-resolutions**: `design-resolutions-per-tab-engine.md` is a historical
> discussion record. It is NOT a migration target and MUST NOT be modified.

## Carry-Over Notes (NOT addressed in v0.8 — deferred to v0.9)

- review note 01: Surface API references in comments in 02-types.md and 03-engine-interface.md (LOW)

## IME Contract v0.8 Changes (tracked in Daemon v0.3 Phase 3)

- [x] 01-overview §53-104: Keep Phase 1 description only; replace Phase 0 and Phase 2 with
      reference to daemon design docs (I1)
- [x] 01-overview §106-114: Remove IME-before-keybindings rationale (I2)
- [x] 01-overview §142-178: Keep IME engine rows only in responsibility matrix;
      replace daemon rows with reference to daemon design docs (I3)
- [x] 04-ghostty-integration: Replace entire section with brief reference section:
      "ghostty integration is defined in daemon design docs; the IME engine does not
      interact with ghostty directly" (I4)
- [x] 02-types §69-71: Remove wire-to-KeyEvent decomposition detail and Phase 0 reference;
      keep KeyEvent type definition (I9)
- [x] 03-engine-interface §24-48: Keep vtable method behavioral contracts (what engine does);
      remove "when daemon calls them" lifecycle rationale (I5)
- [x] 05-extensibility §125-160: Remove session persistence procedure (save/restore timing,
      flush-on-save); keep engine constructor accepts canonical input_method string (I7)
- [x] 05-extensibility §72-122: Reduce C API boundary discussion to one-liner:
      "libitshell3-ime exports a Zig API only; it has no public C header" (I8)
