# Cross-Team Request: Remove Stale Surface API References in §4.2

**Date**: 2026-03-13
**Source team**: daemon
**Source version**: daemon v0.4
**Source resolution**: N/A — discovered during daemon v0.4 verification (SEM-R3 observation)
**Target docs**: `draft/v1.0-r11/05-cjk-preedit-protocol.md` §4.2
**Status**: open

---

## Context

The daemon architecture (doc 01 §4.6) uses a headless API: `overlayPreedit()` is called at export time via `ExportResult`. There is no ghostty Surface in the daemon. This was established in daemon v0.3 and confirmed in v0.4.

Protocol doc v0.11 §4.2 still references `ghostty_surface_preedit()` for preedit injection, which contradicts the canonical daemon behavior.

## Required Changes

1. **§4.2 (~line 361)**: Remove "the server calls `ghostty_surface_preedit()`" — the protocol doc should describe wire semantics, not server-side implementation details.

2. **§4.2 (~line 383)**: Same — remove or replace the `ghostty_surface_preedit()` reference.

3. **§4.2 (~line 396)**: Same — remove or replace the `ghostty_surface_preedit()` reference.

## Summary Table

| Target Doc | Section | Change Type | Source |
|-----------|---------|-------------|--------|
| `05-cjk-preedit-protocol.md` | §4.2 ~line 361 | Remove stale Surface API reference | daemon v0.4 verification |
| `05-cjk-preedit-protocol.md` | §4.2 ~line 383 | Remove stale Surface API reference | daemon v0.4 verification |
| `05-cjk-preedit-protocol.md` | §4.2 ~line 396 | Remove stale Surface API reference | daemon v0.4 verification |
