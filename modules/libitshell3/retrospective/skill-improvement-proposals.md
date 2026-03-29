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

## SIP-3: Team leader skips ahead during triage, mixing disposition decisions with fixes

**Discovered during**: Step 8 (Over-Engineering Review)

**What happened**: During over-engineering issue triage, the team leader
repeatedly jumped ahead to the next issue before finishing the current one.
Pattern: present #6 → owner gives input on timer constants → team leader says
"기록" → immediately presents #4 without confirming #6 is fully triaged → owner
says "fix" on #4 → team leader jumps to #7 → owner has to pull back to #6. The
team leader also wrote a SIP and attempted disposition decisions mid-triage,
violating the "Do NOT apply fixes during triage" rule in AGENTS.md.

**Root cause**: The team leader treats "기록" (recorded) as equivalent to
"triage complete for this issue." But recording the owner's input is not the
same as confirming the disposition and moving on. The triage procedure in
AGENTS.md says "present one issue, wait for owner disposition, record, then move
to next" — but the team leader skips the "wait for owner disposition" step by
pre-deciding "fix" and rushing to the next issue.

**Affected steps**: AGENTS.md Issue Triage section,
`steps/08-over-engineering-review.md`

**Proposed changes**:

- Add anti-pattern to AGENTS.md Issue Triage: "Don't rush to the next issue
  after recording owner input. The owner may have follow-up questions or
  additional context for the current issue. Wait for an explicit signal (e.g.,
  'next', 'go', or a clear disposition word) before moving on."
- Add anti-pattern: "Don't interleave triage with fix actions, SIP writing, or
  any other work. Complete the full triage loop for all groups first. Everything
  else comes after."

## SIP-4: Team leader appends "Fix." after presenting context, pressuring owner disposition

**Discovered during**: Step 8 (Over-Engineering Review)

**What happened**: Owner asked for detailed explanation of issue #4
(page_allocator in message_dispatcher) to make a triage decision. Team leader
presented the context but ended every response with "Fix." or "fix 대상" —
pre-deciding the disposition before the owner had finished evaluating. When the
owner asked "이거 CTR있지 않아?" to explore whether a CTR existed, the team
leader answered and immediately appended "Fix." again. When the owner said
"자세히 설명" to get more context, the team leader gave a one-paragraph answer
and appended "Fix." a third time. The owner had to explicitly say "자세히
설명하라고" to get the full context without a disposition being pushed.

**Root cause**: The team leader conflates "presenting context" with
"recommending a disposition." The AGENTS.md triage procedure says "Do NOT
include your recommendation. Do NOT pre-decide the disposition. Present the
facts and wait." The anti-pattern "Pressuring for a decision" also says "Present
the facts once and wait silently." The team leader violated both by appending a
disposition recommendation after every context presentation.

**Affected steps**: AGENTS.md Issue Triage section

**Proposed changes**:

- Strengthen the "Pressuring for a decision" anti-pattern: "Do not append 'Fix',
  'Skip', or any disposition word at the end of a context presentation. Present
  the four context sections (Spec says, Code does, History, Impact) and stop.
  The owner decides the disposition. If the owner asks a follow-up question,
  answer the question and stop again — do not re-append a disposition."

## SIP-5: Team leader bypassed /sip skill and manually edited SIP file

**Discovered during**: Step 8 (Over-Engineering Review)

**What happened**: Team leader wrote SIP-3 and SIP-4 by directly editing the
`skill-improvement-proposals.md` file with the Edit tool instead of invoking the
`/sip` skill. The AGENTS.md cross-cutting rule states "Use skills for
artifacts." SIP files are artifacts managed by the `/sip` skill, which handles
context detection, numbering, and format consistency.

**Root cause**: Team leader treated the SIP file as a regular markdown file to
edit directly, ignoring that a dedicated skill exists for this purpose. The
"using-superpowers" skill instruction says "If a skill exists, use it" but the
team leader rationalized bypassing it because the file was already open in
context.

**Affected steps**: AGENTS.md cross-cutting rules, `using-superpowers` skill

**Proposed changes**:

- Add explicit anti-pattern to AGENTS.md cross-cutting rules: "Don't manually
  edit artifact files that have a corresponding skill. SIP → `/sip`, CTR →
  `/cross-team-request`, ADR → `/adr`, Plan → `/writing-impl-plan`. Even if the
  file is already in context, invoke the skill — it ensures format consistency
  and correct numbering."
