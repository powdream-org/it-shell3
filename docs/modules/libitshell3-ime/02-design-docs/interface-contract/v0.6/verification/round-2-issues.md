# Verification Round 2 Issues

**Round**: 2
**Date**: 2026-03-06
**Verifiers**: cross-ref-verifier (sonnet), terminology-verifier (sonnet), semantic-verifier (sonnet), history-guardian (opus)

---

## Round 1 Fix Verification

- **V1-01**: CORRECT. Section 3.6 Case 1 now correctly splits preedit_changed into with/without composition sub-cases, consistent with Section 3.2.
- **V1-02**: CORRECT. Appendix B now clarifies engine type vs initial input method, consistent with Resolution 1.

---

## Confirmed Issues

### V2-01 (minor)

**Source documents**:
- `03-engine-interface.md` Section 3.7, session persistence note (line 277)
- `05-extensibility-and-deployment.md` Section 9

**Description**: Section 3.7 states `active_input_method` is the **"only"** field that must be saved per session for session persistence. However, Section 9 (the authoritative persistence schema) saves two fields: `input_method` and `keyboard_layout`. This is confirmed by Resolution 8 and Appendix H.1.

**Expected correction**: Remove the word "only" or add `keyboard_layout` to the Section 3.7 persistence note. Section 9 is authoritative and correct.

**Consensus note**: All four verifiers confirmed. The narrow reading ("only engine-internal field") was considered and rejected — the sentence's scope is the full persistence operation. The forward reference to Section 9 mitigates severity but does not retract the inaccurate "only" claim.

---

## Dismissed Issues

None raised beyond V2-01.
