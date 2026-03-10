# Server-Client Protocols v0.11 TODO

> **Cross-team revision** with Daemon v0.3 and IME Contract v0.8.
> Single topic: remove daemon behavioral descriptions per cross-team request.
> Daemon TODO (primary): `docs/modules/libitshell3/02-design-docs/daemon/v0.3/TODO.md`
> See daemon v0.3 TODO for full phase tracking. This file tracks protocol-specific deliverables only.
>
> Cross-team request: `v0.10/cross-team-requests/01-daemon-behavior-extraction.md`
>
> **Model policy**: writing — **sonnet**; verification — **opus** for history-guardian only

## Carry-Over Notes (NOT addressed in v0.11 — deferred to v0.12)

- review note 01: Mouse event and preedit interaction (MEDIUM)
- review note 02: Zoom + split interaction (MEDIUM)
- review note 03: Pane auto-close on process exit (MEDIUM)
- review note 04: Hyperlink CellData encoding (MEDIUM)
- review note 05: Resolution document text fixes (LOW)
- review note 06: Remove frame_type=2 (MEDIUM)

## Protocol v0.11 Changes (tracked in Daemon v0.3 Phase 3)

- [x] doc 01 §2.1: Remove auto-start procedure; keep Unix domain socket transport def (P1)
- [x] doc 01 §2.3: Remove FD passing / crash recovery description (P2)
- [x] doc 01 §5.4: Remove heartbeat initiation policy; keep message definition (P19)
- [x] doc 01 §5.7: Remove eviction timeout values; keep Disconnect reason enum ref (P7)
- [x] doc 01 §5.5.3: Remove connection limit number; keep ERR_RESOURCE_EXHAUSTED ref (P3)
- [x] doc 01 §5.6: Remove resize policy internal tracking (latest_client_id, fallback) (P4)
- [x] doc 01 §10: Remove coalescing tiers/timing; keep "server sends on state changes" (P10)
- [x] doc 01 §12.1: Remove auth syscalls/permissions; keep "kernel-level UID verification" (P5)
- [x] doc 02 §9.6: Remove preedit ownership algorithm; keep PreeditEnd reason enum (P11)
- [x] doc 02 §9.9: Remove stale re-inclusion hysteresis rule entirely (P4)
- [x] doc 02 §11.2: Remove reconnection step-by-step procedure (P6)
- [x] doc 02 §12.1: Remove auth implementation details (P5) — bonus, same content as doc 01
- [x] doc 03 §1.9, §2.5: Remove SIGHUP/PTY cleanup/reflow; keep ClosePaneResponse + LayoutChanged (P14)
- [x] doc 03 §2.7: Remove PTY flush detail; keep PreeditEnd reason=focus_changed (P12)
- [x] doc 03 §5.4: Remove TIOCSWINSZ/debounce; keep WindowResizeRequest/Response (P14)
- [x] doc 03 §5.5-5.6: Remove stale exclusion/hysteresis details (P4) — bonus, related to §9.9
- [x] doc 03 §8: Remove IME engine lifecycle; keep active_input_method + active_keyboard_layout fields (P17)
- [x] doc 04 §4.1: Remove PTY independence guarantee; keep "server MAY suppress FrameUpdate" (P15)
- [x] doc 04 §8.3: Remove coalescing details; reference doc 01 reduced description (P10)
- [x] doc 05 §6.1-6.4: Remove ownership algorithm; keep PreeditEnd reason enums (P11)
- [x] doc 05 §7.4, §7.7: Remove PTY commit details; keep PreeditEnd reasons (P12)
- [x] doc 05 §8: Remove ring buffer / timing / power state details; keep "delivered with minimal latency" (P10)
- [x] doc 06 §1: Remove coalescing tier definitions/transitions/WAN/power/idle suppression (P10)
- [x] doc 06 §2.1-2.9: Remove ring buffer arch, health timeline, stale trigger conditions;
      keep PausePane/ContinuePane/FlowControlConfig message definitions (P7, P8, P9)
- [x] doc 06 §4.4: Remove engine reconstruction/snapshot impl; keep message field tables (P17)
- [x] doc 06 §6: Keep auto-subscription list (wire-observable behavior); add daemon-side note (P18)
- [x] All docs: Version headers updated to v0.11, changelog added to doc 01
