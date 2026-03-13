# Handover: IME Interface Contract v0.8 to v0.9

**Date**: 2026-03-10
**Author**: team leader

---

## Insights and New Perspectives

v0.8 was a pure extraction — daemon behavioral content was removed and replaced with references to daemon v0.3 docs. The IME contract now focuses exclusively on what the engine does: the vtable API, type definitions, composition rules, and extensibility points. The engine does not know about ghostty, PTYs, or preedit display — those are all daemon responsibilities.

The `design-resolutions-per-tab-engine.md` file (v0.6) was confirmed as a historical record that must not be modified. It is correctly referenced from daemon doc 02 for the per-session engine design rationale.

Verification round 1 fix V1-08 converted doc 04 (ghostty-integration) §5 into a reference stub. This created a ripple effect: daemon docs 01 and 02 had cross-references pointing to §5 for press+release pair rationale, which became stale (R2-06, R2-07). These were fixed by removing the stale citations. The lesson: when converting a section to a stub, grep all other modules for cross-references to that section.

## Design Philosophy

**IME contract = engine API contract only**. The IME engine is a pure function: KeyEvent in, ImeResult out. It has no knowledge of the daemon, protocol, or display layer. This boundary was sharpened in v0.8 and must be maintained.

## Owner Priorities

Review note 01 (Surface API references in comments) is LOW severity. The references in `02-types.md` line 118 and `03-engine-interface.md` line 289 are in explanatory context, not normative text. Fix when convenient.

## New Conventions and Procedures

None.

## Pre-Discussion Research Tasks

None required — v0.9 scope is minimal (1 LOW review note).
