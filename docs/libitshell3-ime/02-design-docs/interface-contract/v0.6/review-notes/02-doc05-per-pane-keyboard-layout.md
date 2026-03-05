# Protocol Doc 05 Section 4.3 Still Describes keyboard_layout as Per-Pane

**Date**: 2026-03-05
**Raised by**: verification team (verifier-protocol)
**Severity**: LOW
**Affected docs**: `docs/libitshell3-ime/02-design-docs/interface-contract/v0.6/protocol-changes-for-v07.md`, protocol doc 05 Section 4.3
**Status**: open

---

## Problem

Protocol doc 05 v0.6, Section 4.3, line 496 states: "The `keyboard_layout` field (e.g., `"qwerty"`, `"azerty"`) is a separate, orthogonal **per-pane** property."

The IME contract v0.6, Section 3.4 states: "Physical keyboard layout (QWERTY/AZERTY/QWERTZ) is a separate **per-session** field."

`protocol-changes-for-v07.md` Change 7 addresses Section 4.3's heading and per-pane ownership text, but does not specifically call out the `keyboard_layout` per-pane reference in the same section.

## Analysis

This is captured implicitly by Change 7 ("Update all references from per-pane ownership to per-session ownership"), which should cover this line. The severity is LOW because the intent of Change 7 is clear enough that a v0.7 writer would catch this. However, explicitly listing it would eliminate any ambiguity.

## Proposed Change

No additional change file needed. Change 7 already covers this implicitly. For completeness, the v0.7 team should verify that all per-pane references in Section 4.3 (including the `keyboard_layout` sentence) are updated to per-session.

## Owner Decision

Left to designers for resolution.

## Resolution

