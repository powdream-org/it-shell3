# Handover: Server-Client Protocols v0.11 to v0.12

**Date**: 2026-03-10
**Author**: team leader

---

## Insights and New Perspectives

v0.11 was a pure extraction — no new protocol features, no wire format changes. The protocol docs are now significantly leaner, containing only wire format definitions, message semantics, and enum values. All daemon behavioral descriptions (coalescing tiers, health timelines, ring buffer architecture, preedit ownership algorithms, resize policies, etc.) have been moved to daemon v0.3 docs.

One verification finding (V1-06) revealed that the RLIMIT_NOFILE implementation note in §5.5.4 had survived the extraction — a reminder that "implementation notes" embedded in protocol docs tend to be daemon behavior in disguise. Future protocol revisions should be vigilant about this pattern.

The section renumbering fix (V1-09, §5.7→5.8 gap in doc 03) suggests that previous extraction passes may have left similar gaps. A full section numbering audit would be prudent.

## Design Philosophy

**Protocol docs = wire-observable behavior only**. After v0.11, the protocol docs should describe what goes on the wire and what each message means to the receiver. How the server *implements* those semantics is the daemon docs' responsibility. This boundary was formalized in v0.11 and must be maintained.

## Owner Priorities

The 6 carry-over review notes (01-06) from v0.10 are all MEDIUM/LOW and none are blocking. They represent genuine design gaps (mouse+preedit interaction, zoom+split, pane auto-close, hyperlink encoding, frame_type=2 removal) that should be addressed when implementation approaches.

**Incoming cross-team requests** (see `draft/v1.0-r11/cross-team-requests/`):

- `01-daemon-surface-references.md` (daemon v0.4): Remove stale `ghostty_surface_preedit()` references in `05-cjk-preedit-protocol.md` §4.2 (~lines 361, 383, 396). Protocol docs must not describe server-side implementation details.

## New Conventions and Procedures

None.

## Pre-Discussion Research Tasks

- **Section numbering audit**: Check all 6 protocol docs for section numbering gaps or inconsistencies introduced by the v0.11 extraction.
- **frame_type=2 removal** (review note 06): Research whether any existing design references depend on frame_type=2 before removing it.
