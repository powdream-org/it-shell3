# Handover: Server-Client Protocols v0.10 to v0.11

**Date**: 2026-03-10
**Author**: team-lead

---

## Insights and New Perspectives

### frame_type=2 is unnecessary — dirty tracking is a single boolean

During the owner review, we traced the "math" for deciding I-frame dirty vs unchanged. Every terminal state change (PTY output, cursor, modes, colors, preedit) flows through ghostty's RenderState, which triggers P-frame emission via the coalescing pipeline. There are no bypass paths — not even IME state changes (verified against the IME contract v0.7 implementation).

This means when the I-frame timer fires, the dirty/unchanged decision reduces to: "has any P-frame been emitted since the last I-frame?" — a single boolean per pane. If not dirty, the last I-frame in the per-pane ring buffer is still valid and seekable. Writing a duplicate `frame_type=2` entry wastes ~6-33 KB/s bandwidth per idle pane and adds complexity (3 frame types, byte-comparison logic, seeking client exception rule) for zero benefit.

The owner decided to remove `frame_type=2` for KISS, keeping the `frame_type` field name for extensibility. See review note 06.

### Direct message queue is orthogonal to I-frame payload

LayoutChanged, PreeditSync, InputMethodAck, and other direct-queue messages carry session/pane metadata that is NOT part of the I-frame's CellData or JSON metadata payload. They don't affect the dirty boolean. This clean separation between control messages (direct queue) and rendering data (ring buffer) is a design strength worth preserving.

### All IME output flows through ghostty's API surface

The IME contract v0.7 routes all engine output through `ghostty_surface_key()` (committed text, forwarded keys) and `ghostty_surface_preedit()` (preedit cells). Even `setActiveInputMethod()` calls `session.markDirty()` unconditionally. There is no IME bypass path that could make the RenderState inconsistent with the dirty flag.

---

## Design Philosophy

### Rendering state is the single source of truth for frame decisions

The protocol should not maintain parallel tracking mechanisms (byte comparison, generation counters, per-field change flags) when ghostty's RenderState already captures all mutations. Trust the engine's dirty tracking. The server's job is to serialize when dirty, skip when not.

### Fewer frame types is better

Three frame types (P-frame, I-frame, I-unchanged) create a combinatorial explosion in client processing rules (caught-up vs seeking × frame_type). Two frame types (P-frame, I-frame) are sufficient. The `frame_type` field remains extensible if a genuine need arises in the future — but the bar for adding a new type should be high.

---

## Owner Priorities

### KISS over optimization hints

The owner explicitly chose to remove `frame_type=2` even though it provides a minor client-side CPU optimization (skip processing identical I-frames). The complexity cost (extra frame type, byte-comparison logic, seeking exception rule) outweighs the benefit. The v0.11 team should apply this same lens to other "advisory hint" patterns in the spec.

### Verify claims across module boundaries

The owner asked to verify the dirty-tracking claim against both protocol docs and IME contract implementations. Cross-module verification (protocol × IME contract) caught that the claim holds — no bypass paths exist. Future design discussions should similarly verify assumptions at module boundaries rather than trusting single-doc analysis.

---

## New Conventions and Procedures

### Review note carry-over: drop confirm-and-close

When carrying review notes from v(N) to v(N+1), only carry notes with `Status: open`. Notes with `Status: confirm-and-close` (or any resolved/closed status) should be dropped. Renumber from 01 in the new version directory.

---

## Pre-Discussion Research Tasks

### frame_type=2 removal ripple analysis

Before applying review note 06, the team should identify all locations in Docs 01-06 that reference `frame_type=2`, I-unchanged, or the byte-comparison rule. The v0.8 changelog, Section 7.3, Section 8.3, Appendix A hex dump, and the attach sequence descriptions (already referencing `frame_type=1 or frame_type=2` after R4) all need updates. A grep for `frame_type=2`, `I-unchanged`, `unchanged`, and `byte-identical` across all 6 docs will produce the full ripple list.

### Cross-team request: daemon behavior extraction

The daemon team (v0.2) filed a cross-team request at `v0.10/cross-team-requests/01-daemon-behavior-extraction.md` requesting removal of daemon-side behavioral descriptions from all 6 protocol docs. 23 specific changes across docs 01-06 covering process management, flow control policies, multi-client resize logic, preedit ownership algorithms, coalescing internals, and PTY management. These changes MUST be applied simultaneously with daemon v0.3 absorbing the same content. See the cross-team request for the full change list.

### Idle suppression interaction

With frame_type=2 removed, the I-frame timer becomes a no-op during idle. Verify this doesn't break any assumption in Doc 06's adaptive coalescing model (especially the Idle tier transition rules and the "500ms after resize" grace period). The ring buffer must always contain at least one I-frame per pane — confirm this invariant holds when the timer stops writing during idle.
