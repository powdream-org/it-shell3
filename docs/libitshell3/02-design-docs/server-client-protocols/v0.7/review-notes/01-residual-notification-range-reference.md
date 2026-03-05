# Residual Notification Range Reference in Doc 03 Section 4.6

**Date**: 2026-03-05
**Raised by**: verification team (round 1)
**Severity**: LOW
**Affected docs**: doc 03 (03-session-pane-management.md)
**Status**: open

---

## Problem

In doc 03 Section 4.6 (ClientHealthChanged), line 868, the "Always-sent" note reads:

> **Always-sent**: No subscription required. Follows the same always-sent convention as 0x0180-0x018**4**. See the introductory note in Section 4.

This should say `0x0180-0x0185` (not `0x0184`). The Section 4 introductory note (line 738) was correctly updated in v0.7 to use `0x0180-0x0185`, and the v0.7 changelog (line 1104) explicitly records this update. However, this secondary reference within the ClientHealthChanged section itself was not updated to match.

The issue is that `0x0180-0x0184` excludes ClientHealthChanged (`0x0185`) -- the very message whose section contains this text. The note effectively says "this message follows the convention of a range that does not include this message." While the intended meaning is clear (it follows the same always-sent convention), the range is technically wrong and inconsistent with the Section 4 introductory note.

The v0.6 changelog entry at line 1114 also references `0x0180-0x0184`, but that is a historical changelog entry describing v0.6 behavior (before ClientHealthChanged existed), so it is correct in that context and should not be changed.

## Proposed Fix

In doc 03, line 868, change:

```
**Always-sent**: No subscription required. Follows the same always-sent convention as 0x0180-0x0184. See the introductory note in Section 4.
```

to:

```
**Always-sent**: No subscription required. Follows the same always-sent convention as 0x0180-0x0185. See the introductory note in Section 4.
```
