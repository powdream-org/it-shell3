# Verification Round 9 Issues

- **Round**: 9
- **Date**: 2026-03-07
- **Verifiers**: cross-reference-verifier, history-guardian, semantic-verifier, terminology-verifier

## Confirmed Issues

### V9-01 — Doc 02 Section 10.1 preedit_sync fallback table row 2 contradicts "always available" principle

- **Severity**: minor
- **Source documents**: Protocol v0.8 `02-handshake-capability-negotiation.md` Section 10.1 (line 911); same document Section 5.1 (lines 381, 393–395)
- **Description**: The `preedit_sync` fallback table row 2 (client=yes, server=no) reads: "Single-client preedit: only the composing client sees its own preedit. Server does not broadcast." This contradicts the normative principle stated in Section 5.1: "Preedit rendering is always available through cell data in I/P-frames regardless of capability negotiation." The `preedit_sync` capability gates only `PreeditSync` (0x0403) late-joining snapshots. `PreeditStart/Update/End` (0x0400–0x0402) are gated by `"preedit"` alone and still broadcast. Preedit cell data in FrameUpdate is never gated by any capability. The phrase "only the composing client sees its own preedit" implies observer clients cannot see preedit, which is false under v0.8.
- **Expected correction**: Replace with: "No `PreeditSync` (0x0403) late-joining snapshots. Preedit cells are still visible in FrameUpdate cell data for all attached clients. `PreeditStart`/`PreeditUpdate`/`PreeditEnd` still broadcast to all clients that negotiated `\"preedit\"`."
- **Consensus note**: All 4 verifiers confirmed.

## Dismissed Issues

None.
