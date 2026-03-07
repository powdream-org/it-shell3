# Verification Round 10 Issues

- **Round**: 10
- **Date**: 2026-03-07
- **Verifiers**: cross-reference-verifier, history-guardian, semantic-verifier, terminology-verifier

## Confirmed Issues

### V10-01 — Doc 02 Section 10.1 preedit_sync fallback table row 3 "opts out of preedit broadcast" contradicts Section 5.1

- **Severity**: minor
- **Source documents**: Protocol v0.8 `02-handshake-capability-negotiation.md` Section 10.1 (line 912, row 3: client=no, server=yes); same document Section 5.1 (line 395) and Section 10.1 line 911 (V9-01-corrected row 2)
- **Description**: Row 3 reads: "This client opts out of preedit broadcast. Server does not send `PreeditSync` to this client. Other clients may still see synced preedit." The phrase "opts out of preedit broadcast" implies the client opts out of all preedit messages, contradicting Section 5.1's normative statement that `PreeditStart/Update/End` (0x0400-0x0402) are "always broadcast to all clients that negotiated `'preedit'`" and the V9-01-corrected row 2 which explicitly states PreeditStart/Update/End still broadcast. `preedit_sync` gates only `PreeditSync` (0x0403), not the other 0x04xx messages.
- **Expected correction**: Replace "This client opts out of preedit broadcast. Server does not send `PreeditSync` to this client. Other clients may still see synced preedit." with: "This client does not receive `PreeditSync` (0x0403) late-joining snapshots. `PreeditStart`/`Update`/`End` (0x0400-0x0402) are still delivered if the client negotiated `\"preedit\"`. Other clients with `\"preedit_sync\"` = yes still receive synced preedit."
- **Consensus note**: All 4 verifiers confirmed.

## Dismissed Issues

None.
