# Skill Improvement Proposals — Daemon r8

## SIP-01: Dismissed Issues Registry too weak — same topic re-raised across rounds

**Observed in**: Round 3 (C3-01/S3-01)

**Problem**: The PreeditEnd ordering topic was raised in every round:

- Round 1: G1-06 (response-before-notification vs PreeditEnd) → confirmed, fixed
- Round 2: S2-03 (§4.4 "First" vs PreeditEnd) → dismissed as cascade from G1-06
- Round 3: C3-01/S3-01 (resolution doc example vs behavior doc PreeditEnd
  placement) → dismissed again

The Dismissed Issues Registry lists individual issue IDs and descriptions, but
verifiers keep finding new surface manifestations of the same underlying topic.
The registry's format (ID + one-line description) doesn't convey the settled
**principle** — only the specific instance that was dismissed.

**Proposed fix**: Extend the Dismissed Issues Registry format to include
**settled principles**, not just individual issues. For example:

```
## Settled Principles
- PreeditEnd is an IME composition-resolution preamble, NOT a protocol
  notification. It precedes the response in the three-phase model
  (IME cleanup → response → notifications). Any issue that questions
  PreeditEnd's position relative to responses or notifications is settled
  by G1-06 (Round 1). Do NOT re-raise in any form.

## Dismissed Issues
- G1-01: ...
- S2-03: ...
```

Verifiers would check both the dismissed list AND the settled principles before
raising an issue. This prevents re-raises that are structurally different but
topically identical.

**Affected skill file**: `steps/05-verification.md` — the Dismissed Issues
Registry format in §5b should include a "Settled Principles" section for
Round 3+.
