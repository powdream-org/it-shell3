# Round 1 Verification Issues

**Round**: 1
**Date**: 2026-03-10
**Verifiers**: cross-reference-verifier, history-guardian, semantic-verifier, terminology-verifier

---

## Confirmed Issues

### V1-01 — Doc 05 §4.1 commit path omits PreeditEnd

- **Severity**: minor
- **Source**: Doc 05 §4.1 step 1 (line ~266) vs §7.9 step 1 (line ~545)
- **Description**: §4.1 step 1 describes the commit path as "commit current preedit text to PTY" with no mention of sending PreeditEnd. §7.9 step 1 (updated by R2) explicitly says "Commit current preedit text to PTY, send PreeditEnd with reason='committed' to all clients." An implementer reading only §4.1 would not send PreeditEnd on the commit branch of InputMethodSwitch.
- **Expected correction**: §4.1 step 1 should explicitly state "send PreeditEnd with reason='committed' to all clients" to match §7.9.
- **Consensus note**: 4/4 unanimous. Both sections describe the same server behavior; the omission creates an ambiguity that could lead to misimplementation.

### V1-02 — Doc 04 §6.2 ScrollPosition direction not updated for R1

- **Severity**: minor
- **Source**: Doc 04 §6.2 ScrollPosition (line ~841)
- **Description**: §6.2 describes ScrollPosition as "Server -> client notification" (singular). R1 changed scroll from per-client to globally shared state, making ScrollPosition a broadcast to all attached clients. The §6.2 direction description was not updated to reflect R1's global model.
- **Expected correction**: §6.2 direction description should read "Server -> all clients" or equivalent to match R1's globally singleton model.
- **Consensus note**: 4/4 unanimous. R1's resolution rationale explicitly states ScrollPosition is broadcast; the spec text was a missed ripple.

### V1-03 — Resolution doc wrong section reference for tree depth

- **Severity**: minor
- **Source**: `design-resolutions/01-top-severity-fixes.md`, Resolution 3, line ~104
- **Description**: The resolution document states "Doc 03 Section 4.2 enforces a maximum tree depth of 16 levels." Doc 03 §4.2 is `PaneMetadataChanged (0x0181)`, not tree depth. The tree depth constraint is in an unnumbered subsection within §3 (Layout Tree Wire Format).
- **Expected correction**: Change reference to "Doc 03 Section 3 (Maximum Tree Depth subsection)".
- **Consensus note**: 4/4 unanimous. Factually wrong section reference.

---

## Dismissed Issues

| ID | Raised by | Reason for dismissal |
|----|-----------|---------------------|
| T-1 | terminology-verifier | `ERR_SESSION_ALREADY_ATTACHED (0x00000201)` is a protocol-level error_code in a separate namespace from status code 3. Two-layer error model is intentional (Doc 01 §6.3). |
| T-2 | terminology-verifier | Same reasoning as T-1 for `ERR_ACCESS_DENIED (0x00000203)` vs status code 5. |
| CR-02 | cross-reference-verifier | Stale version headers are a pre-existing convention gap (v0.9 precedent). Folder-level versioning, not per-doc header bumps. |
