# Daemon v0.4 Verification — Round 3 Issues

**Date**: 2026-03-11
**Team**: history-guardian (sonnet), cross-reference-verifier (sonnet), semantic-verifier (sonnet), terminology-verifier (sonnet)
**Verdict**: All Round 1 and Round 2 fixes confirmed clean. 1 new MINOR issue found — fix required.

---

## Round 1 Fixes — All Confirmed Clean

V1-1, V1-2, V1-3, V1-4: correctly applied.

## Round 2 Fixes — All Confirmed Clean

R2-1, R2-2, R2-3: correctly applied.

---

## New Issue (1, MINOR)

### SEM-R3-1 — MINOR: Doc 04 §7.6 references "ghostty surface" — contradicts headless architecture

**File**: `v0.4/04-runtime-policies.md`, §7.6, line 364
**Sources**: all four verifiers (unanimous)

Current text: "The ghostty surface handles preedit cursor repositioning internally."

This contradicts doc 01 §4.6, which explicitly establishes the daemon is headless ("no Surface, no App, no embedded apprt"). There is no ghostty Surface in the daemon. Preedit cursor positioning is handled by `overlayPreedit()` at export time (doc 01 §4.4), not by any Surface.

**Fix**: Replace the sentence with text that reflects the headless architecture — on resize, the daemon produces an I-frame via `bulkExport()` + `overlayPreedit()` with the updated cursor position from `ExportResult`. No Surface is involved.

---

## History-Guardian Assessment

Zero false alarms. SEM-R3-1 is a contradiction between two pieces of current normative body text (doc 01 §4.6 vs doc 04 §7.6), not a historical record comparison.
