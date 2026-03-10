# Surface API References in Comments

**Date**: 2026-03-10
**Raised by**: verification team
**Severity**: LOW
**Affected docs**: IME v0.8 02-types.md, 03-engine-interface.md
**Status**: open

---

## Problem

`02-types.md` line 118 and `03-engine-interface.md` line 289 contain references to Surface APIs (`ghostty_surface_key()`, `ghostty_surface_preedit()`) in explanatory comments. These were not addressed by the v0.8 extraction (which targeted different sections per the cross-team request).

## Analysis

Low impact — these are explanatory/contextual references, not normative descriptions. The v0.8 extraction focused on removing daemon behavioral procedures (I1-I9), not every mention of Surface APIs in comments. Fixing these is straightforward but was out of scope for v0.8.

## Proposed Change

Update or remove the Surface API references to align with the headless architecture established in daemon docs.

## Owner Decision

Left to designers for resolution.

## Resolution

