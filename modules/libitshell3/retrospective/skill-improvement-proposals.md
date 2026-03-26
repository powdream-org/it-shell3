# Skill Improvement Proposals

## SIP-1: Spec-code divergence dismissed without investigation

**Discovered during**: Step 1d (Plan verification against spec)

**What happened**: Verifiers reported 4 pre-existing spec-code divergences
(PaneSlot u4 vs u8, keyboard_layout naming, keyboard layout default "us" vs
"qwerty", SessionEntry.latest_client_id missing). The team leader dismissed all
4 as "Plan 5 scope 밖" and proceeded to fix the plan's own gaps. Step 1d
explicitly requires: investigate (read spec rationale, check ADRs, understand
why code differs) → determine which side is wrong → escalate to owner if unable
to determine. None of these steps were performed.

**Root cause**: The team leader treated "out of scope" as a valid resolution for
spec-code divergence. Step 1d's convergence loop has no "out of scope" exit —
divergences must be investigated and resolved (or escalated) regardless of
whether the current plan intends to fix them. The team leader conflated "this
plan won't fix it" with "this doesn't need investigation."

**Affected steps**: `steps/01-requirements-intake.md` (Step 1d)

**Proposed changes**:

1. Add anti-pattern to Step 1d: "Don't dismiss divergences as 'out of scope.'
   Every spec-code divergence must be investigated and either resolved or
   escalated to the owner — even if the fix belongs to a different plan. 'Out of
   scope for this plan' is a valid conclusion AFTER investigation, not a reason
   to skip investigation."
2. Add to Step 1d convergence loop: a third issue category alongside
   plan-vs-spec gap and plan-vs-code redundancy: "Pre-existing spec-code
   divergence → investigate, determine which side is wrong, record finding. If
   fix belongs to a different plan, log it in TODO.md Spec Gap Log with
   investigation result. If unable to determine, escalate to owner before
   proceeding."

## SIP-2: "Plan covers it" used as substitute for investigation

**Discovered during**: Step 1d (Plan verification against spec)

**What happened**: Verifier reported Session missing IME fields (ime_engine,
current_preedit, preedit_buf, last_preedit_row) as a spec-code divergence. The
team leader dismissed it as "Plan Task 2가 정확히 커버. 문제 아님" without
investigating whether the omission was an intentional deferral from Plan 1 or a
missed requirement. This is the same failure mode as SIP-1 but with a different
rationalization: instead of "out of scope" the excuse was "the plan already
handles it."

**Root cause**: The team leader conflated "the plan will fix this" with "this
divergence has been investigated." Knowing that Task 2 adds the fields does not
answer the question of WHY they are missing — was it intentional deferral (like
latest_client_id → Plan 6), or a Plan 1 implementation bug? The investigation
step exists to answer that question, not to confirm the plan covers the fix.

**Affected steps**: `steps/01-requirements-intake.md` (Step 1d)

**Proposed changes**:

1. Add anti-pattern to Step 1d: "Don't treat 'the plan covers it' as
   investigation. Even when the current plan will fix a divergence, investigate
   WHY the code diverges from spec — was it intentional deferral, a prior plan's
   bug, or a spec update the code hasn't caught up to? The answer affects
   whether a simple fix suffices or whether there are deeper issues."

## SIP-3: "Intentional deferral" assumed without explicit documentation

**Discovered during**: Step 1d (Divergence investigation)

**What happened**: When investigating 5 spec-code divergences, the team leader
concluded 3 were "intentional deferrals" (Session IME fields → Plan 5,
latest_client_id → Plan 6, PaneSlot u4 vs u8 → "correct improvement"). These
conclusions were based on circumstantial evidence (plan scope statements, git
timestamps, ROADMAP entries) rather than explicit deferral documentation. The
owner corrected: unless there is an explicit document stating "intentionally
diverged from spec because X," do not trust the implementation. If an agent
diverged from spec during implementation, it was likely cutting corners — the
owner would have changed the spec, not silently diverged.

**Root cause**: The investigation process treated "the plan said X was out of
scope" as proof of intentional deferral. But a plan scoping something out does
not make the divergence intentional — it just means the plan didn't cover it.
The correct default is: **spec is authoritative unless an explicit decision
document (ADR, design resolution, owner instruction) says otherwise.** Code that
diverges from spec without such a document is a bug, not a feature.

**Affected steps**: `steps/01-requirements-intake.md` (Step 1d)

**Proposed changes**:

1. Add to Step 1d investigation procedure: "When code diverges from spec, the
   spec wins by default. 'Intentional deferral' requires explicit documentation
   (ADR, design resolution, or owner instruction). A plan's out-of-scope list
   does not count — it explains what the plan skipped, not what the spec permits
   skipping. Without explicit documentation, report the divergence as a bug and
   escalate to the owner."
2. Add anti-pattern to Step 1d: "Don't infer intent from circumstantial evidence
   (git timestamps, plan scope). AI agents may have silently diverged from spec
   during implementation. The owner's rule: if spec and code disagree and
   there's no ADR/resolution, the spec is right."

## SIP-4: Plan writing consumes too much team leader context

**Discovered during**: Step 1c (Find or write the implementation plan)

**What happened**: The `/writing-impl-plan` skill directs the team leader to
read all spec documents, analyze existing source code, and write the plan
directly. For Plan 5 this required reading 5+ spec files (200+ lines each), 35
source files, build.zig, and libitshell3-ime's public API — all loaded into the
team leader's context window. Combined with the subsequent verification loop
(Step 1d), this consumed a large fraction of the team leader's available context
before any implementation work began.

**Root cause**: The `/writing-impl-plan` skill does not distinguish between the
team leader and a subagent. Plan writing is research-heavy work (reading specs,
analyzing code, cross-referencing) that is well-suited for delegation. The team
leader's role is facilitation — providing paths and constraints, not doing the
research.

**Affected steps**: `steps/01-requirements-intake.md` (Step 1c), and the
`/writing-impl-plan` skill itself

**Proposed changes**:

1. Step 1c should say: "Delegate plan writing to a subagent. Provide the
   subagent with spec paths, source directory, ROADMAP entry, and any
   constraints. The team leader reviews the result, not writes it."
2. The `/writing-impl-plan` skill should be invocable by a subagent, not assumed
   to run in the team leader's context.

## SIP-5: Verification loop not autonomous — team leader asked owner for permission

**Discovered during**: Step 1d (Plan verification convergence loop)

**What happened**: After fixing plan issues from R2 verifiers, the team leader
asked the owner "다시 verification loop 돌릴까요?" instead of automatically
re-spawning verifiers. Step 1d explicitly says "Repeat until clean pass" — it is
an autonomous convergence loop, not a step that requires owner permission at
each iteration.

**Root cause**: The team leader treated each verification round as a discrete
step requiring owner approval, rather than as iterations within a single
autonomous loop. The gate for Step 1d is "clean pass" — until that gate is met,
the team leader should keep iterating without asking.

**Affected steps**: `steps/01-requirements-intake.md` (Step 1d)

**Proposed changes**:

1. Add to Step 1d: "This is an autonomous convergence loop. Do NOT ask the owner
   for permission to re-verify. Keep iterating (fix → re-verify) until clean
   pass or until you hit a divergence that requires owner escalation."

## SIP-6: Team leader directly edits plan instead of delegating to subagent

**Discovered during**: Step 1d (Plan fixes after verification)

**What happened**: When verifiers found issues in the plan, the team leader
directly edited the plan file (reading sections, making Edit calls) instead of
delegating the fixes to a subagent. This consumed significant team leader
context for mechanical text editing. The team leader's role is facilitation — it
should describe what needs to change and let a subagent make the edits.

**Root cause**: Step 1d's convergence loop says "re-invoke `/writing-impl-plan`
with the issue list" for plan-vs-spec gaps, but does not explicitly say to
delegate the editing. The team leader interpreted "fix the plan" as "edit the
plan myself" rather than "tell a subagent to edit the plan."

**Affected steps**: `steps/01-requirements-intake.md` (Step 1d)

**Proposed changes**:

1. Add to Step 1d convergence loop: "All plan edits MUST be delegated to a
   subagent. The team leader provides the issue list and the plan path; the
   subagent reads the plan, applies fixes, and reports back. The team leader
   does not edit the plan directly."
2. Add anti-pattern: "Don't edit the plan yourself. You are a facilitator.
   Describe the required changes and delegate."

## SIP-7: Plan revision did not use /writing-impl-plan skill

**Discovered during**: Step 1d (Plan fixes after verification)

**What happened**: When verifiers found issues and the plan needed updating, the
team leader (and later, directly editing) did not re-invoke the
`/writing-impl-plan` skill in "Revise" mode. Step 1c created the plan using the
skill, but Step 1d's fix iterations bypassed it entirely — making ad-hoc Edit
calls instead of re-invoking the skill with the issue list as the skill's
"Revise" mode prescribes.

**Root cause**: The `/writing-impl-plan` skill explicitly defines two modes:
"Create" (no plan exists) and "Revise" (plan exists but verifiers found issues —
"Read the existing plan and the issue list, then fix the plan"). Step 1d says
"re-invoke `/writing-impl-plan` with the issue list" for plan-vs-spec gaps. The
team leader ignored this instruction and edited the plan manually.

**Affected steps**: `steps/01-requirements-intake.md` (Step 1d)

**Proposed changes**:

1. Add to Step 1d convergence loop: "Plan fixes MUST go through
   `/writing-impl-plan` in Revise mode. Do NOT make ad-hoc edits to the plan
   file. Pass the issue list to the skill and let it produce the revised plan."
2. Add anti-pattern: "Don't bypass the skill. The skill exists to ensure plan
   format consistency and completeness. Ad-hoc edits skip the skill's validation
   logic."

## SIP-8: Subagent model selection — sonnet used for writing tasks

**Discovered during**: Step 1d (CTR writing delegation)

**What happened**: The team leader delegated CTR writing to a sonnet subagent.
The owner corrected: sonnet is insufficient for writing tasks that require
understanding design context and producing spec-quality documents. Writing tasks
(plans, CTRs, ADRs, design documents) should use opus.

**Root cause**: No guidance in the implementation skill about which model to use
for which subagent task. The team leader defaulted to sonnet for cost efficiency
without considering task complexity.

**Affected steps**: All steps that delegate to subagents

**Proposed changes**:

1. Add model selection guidance to the implementation skill: "Verification
   subagents can use sonnet (mechanical checking). Writing subagents (plan
   revisions, CTRs, ADRs) MUST use opus (requires design understanding)."

## SIP-9: CTR written without /cross-team-request skill

**Discovered during**: Step 1d (CTR creation)

**What happened**: The team leader wrote CTRs by manually creating files and
delegating content to a subagent, instead of using the `/cross-team-request`
skill which handles placement rules, naming conventions, and format
automatically. The first CTR was even placed in the wrong directory (inbox
instead of active draft) — exactly the kind of error the skill prevents.

**Root cause**: The team leader did not check the available skill list before
writing CTRs. The `/cross-team-request` skill exists precisely for this task but
was bypassed entirely. This is not limited to Step 1d — the same problem
occurred during ROADMAP work (Plans 1-4 produced 4 CTRs without the skill, all
with filename and metadata convention violations).

**Affected steps**: `steps/01-requirements-intake.md` (Step 1d), and any
workflow step that produces CTRs (implementation, design-doc-revision, ROADMAP)

**Proposed changes**:

1. Add to Step 1d AND the implementation skill's general instructions: "When
   creating cross-team requests, ALWAYS use the `/cross-team-request` skill. Do
   NOT manually create CTR files. The skill handles placement rules, naming
   conventions, and format automatically — bypassing it causes convention
   violations."
