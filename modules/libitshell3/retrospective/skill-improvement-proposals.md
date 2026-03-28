# Skill Improvement Proposals

## SIP-1: Sonnet model fails to catch spec-vs-plan divergences in verification

**Discovered during**: Step 1 (Requirements Intake) — plan verification (1d)

**What happened**: Sonnet verifiers ran two rounds of plan-vs-spec verification
and reported "CLEAN PASS" both times. The owner then discovered three
significant issues that all verifiers missed:

1. **ClientEntry vs ClientState**: The plan used `ClientEntry` (the current
   code's non-spec name) instead of `ClientState` (the spec-defined name in
   `03-integration-boundaries.md` §6.2). Sonnet verifiers checked type names
   against the spec but failed to flag this mismatch.
2. **Implementation-prescriptive API in ClientManager**: The plan specified
   concrete API signatures (`addClient(UnixTransport)`, `findByFd(socket_fd)`,
   `removeClient(client_idx)`) that mirror the current broken `ClientEntry`
   design rather than deriving from the spec. Sonnet treated these as valid
   verification criteria instead of flagging them as code-biased prescriptions.
3. **connection/ namespace placement**: The plan placed `ClientState` in a new
   `server/connection/` subdirectory. The design resolution
   (`design-resolutions-r8.md`) specifies `server/client_state.zig` (flat under
   server/). While the actual subdirectory structure is an implementation
   decision (Plan 5.5 introduced namespace subdirs for cyclic dependency
   prevention), Sonnet did not raise the question at all.

**Root cause**: Sonnet model lacks the depth to cross-reference spec type
definitions against plan language when the plan plausibly echoes existing code.
It validates surface-level consistency (field counts, message names) but does
not detect when plan terminology is derived from the wrong source (current code
vs spec). The model is biased toward confirming what looks reasonable rather
than rigorously checking each name against the spec's canonical definitions.

**Affected steps**: `steps/01-requirements-intake.md` — Step 1d (plan
verification)

**Proposed changes**:

- Add anti-pattern to Step 1d: "Don't use sonnet for plan verification. Sonnet
  is biased toward existing code patterns and misses spec-vs-plan name
  divergences. Use opus for all plan verification rounds."
- Update the model selection guidance in the skill's cross-cutting rules: plan
  verification is a writing-quality task (opus), not a mechanical check
  (sonnet).
- Add verification checklist item: "For modification cycles, verify that ALL
  type names, struct names, and field names in the plan match the SPEC, not the
  current code. Flag any plan language that mirrors existing code names not
  found in the spec."

## SIP-2: Team leader must not triage spec-code divergences without owner escalation

**Discovered during**: Step 1 (Requirements Intake) — plan verification (1d)

**What happened**: Opus verifier reported that the spec's
`ClientState.conn: transport.Connection` type was ambiguous — the spec names a
Layer 4 type `transport.Connection`, but the code has `transport.Transport`
(Layer 4) and `connection.Connection` (Layer 3). The team leader unilaterally
decided it mapped to `connection.Connection` (Layer 3) and instructed the plan
revision subagent to add a note stating this mapping. This was wrong — the
spec's semantic (recv/send/close byte stream) clearly maps to
`transport.Transport` (Layer 4). The owner caught the error and corrected it.

**Root cause**: The team leader treated the spec-code divergence as a mechanical
fix ("just clarify the mapping") instead of recognizing it as a judgment call
requiring owner escalation. Step 1d explicitly says: "If unable to determine
which side is correct, escalate to owner before proceeding" and "spec may need
updating → escalate." The team leader bypassed this by making the determination
themselves — and got it wrong.

**Affected steps**: `steps/01-requirements-intake.md` — Step 1d (plan
verification), specifically the spec-code divergence handling

**Proposed changes**:

- Add anti-pattern to Step 1d: "Don't resolve spec-code type/name divergences
  yourself. When a verifier reports that a spec type name doesn't match the
  code's type name, ALWAYS escalate to the owner — even if you think the mapping
  is obvious. The team leader is not qualified to determine which layer a type
  belongs to or which side of the divergence is correct."
- Strengthen the escalation gate: the autonomous convergence loop may fix
  plan-vs-spec gaps (missing tasks, wrong references) without owner approval,
  but spec-code divergences involving type semantics (not just typos) MUST be
  escalated.
