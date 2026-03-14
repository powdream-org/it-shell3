# Round 2 Verification Issues — IME Interface Contract v1.0-r9

**Date**: 2026-03-15
**Round**: 2
**Phase 1 agents**: consistency-verifier-r2, semantic-verifier-r2
**Phase 2 agents**: history-guardian-r2, issue-reviewer-r2
**Outcome**: All issues dismissed — CLEAN

---

## Confirmed Issues

None.

---

## Dismissed Issues

### R2-MINOR-01 — MockImeEngine deactivate no-op vs vtable MUST-flush

- **Severity**: minor
- **File**: `03-engine-interface.md`
- **Location**: §1 VTable `deactivate` entry vs. §3 MockImeEngine `.deactivate = deactivateNoOp`
- **Phase 1 finding**: vtable contract states "Engine MUST flush pending composition before returning" but MockImeEngine maps deactivate to a no-op, which does not flush.
- **Phase 2 verdict**: **CONTESTED** — history-guardian `confirm`, issue-reviewer `dismiss`
- **Owner decision**: **dismiss** — MockImeEngine (§3 "For Testing") is non-normative. The vtable MUST-flush requirement applies to production ImeEngine implementations, not test doubles.

---

## Dismissed Issues Summary (for Round 3 Phase 1 agents, if needed)

- **R2-MINOR-01**: Dismissed. Reason: MockImeEngine is a non-normative test helper (§3 "For Testing"). MUST requirements in the vtable spec apply to production implementations only. Treating normative MUST requirements as applying to mock stubs is a false alarm.
