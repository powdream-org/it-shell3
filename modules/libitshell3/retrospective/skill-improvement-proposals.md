# Skill Improvement Proposals

## SIP-1: ROADMAP status not updated to "In progress" when plan starts

**Discovered during**: Step 2 (Plan Writing)

**What happened**: After the plan was written and TODO.md was created, the
ROADMAP.md Plan Index table still showed Plan 7 as "Not started". The owner had
to manually point this out. The plan writing subagent updated the Plan 7 summary
section but did not change the status column.

**Root cause**: Neither Step 1 (Requirements Intake) nor Step 2 (Plan Writing)
instructs the team leader to update the ROADMAP status to "In progress". The
`/writing-impl-plan` skill updates the ROADMAP summary and plan file path but
does not touch the status column. Step 4 (Cycle Setup) mentions ROADMAP updates,
but by that point the plan has been in progress for multiple steps.

**Affected steps**: `steps/01-requirements-intake.md` or
`steps/02-plan-writing.md`

**Proposed changes**:

- Add an instruction to Step 1 (section 1d, after creating TODO.md): "Update the
  ROADMAP Plan Index table status from `Not started` to `**In progress**`."
- Alternatively, add it to Step 2 after the plan is written (since that is when
  work is visibly underway).
- Add a gate condition: "ROADMAP status updated to In progress."

## SIP-2: Triage started without issue grouping — skipped straight to Issue 1

**Discovered during**: Step 3 (Plan Verification)

**What happened**: After verifiers reported issues, the team leader said "Let me
triage" and immediately presented Issue 1 with full context, skipping the
grouping step required by `docs/work-styles/06-issue-triage.md`. The triage
procedure requires grouping all issues by component/area first, presenting the
group index to the owner, and letting the owner pick which group to triage
first. Instead, the team leader jumped straight into detailed issue
presentation, forcing the owner to stop and point out the skipped step.

**Root cause**: `steps/03-plan-verification.md` section 3b says "triage per
`docs/work-styles/06-issue-triage.md`" but does not repeat the grouping
requirement inline. The team leader treated triage as "present issues one at a
time" without re-reading the referenced doc's pre-procedure section.

**Affected steps**: `steps/03-plan-verification.md`

**Proposed changes**:

- In section 3b, add explicit instruction: "Group all issues by component/area
  per the triage doc's Pre-procedure section. Present the group index to the
  owner BEFORE presenting any individual issue."
- Add anti-pattern: "Don't skip grouping. Presenting the first issue immediately
  after verifiers report bypasses the owner's ability to choose triage order."

## SIP-3: Triage issue presentation lacks sufficient detail for owner decision-making

**Discovered during**: Step 3 (Plan Verification)

**What happened**: When presenting triage issues to the owner, the team leader
provided compressed one-or-two-line summaries instead of the full context
required by `docs/work-styles/06-issue-triage.md`. The triage doc explicitly
requires four sections per issue — (1) Spec says: exact spec text quoted with
section name and line content, (2) Code does: exact code with file path, line
numbers, and relevant snippet, (3) History: prior CTRs/ADRs/decisions, (4)
Impact: concrete description of what breaks. Instead, issues were presented with
brief paraphrases like "daemon-behavior §4.2 step 5" without quoting the actual
spec text, and "Plan Task 9 verification" without showing the full verification
text. The owner had to ask "자세히" and then again reference the triage doc
before receiving adequate detail.

**Root cause**: The team leader treated the triage format as optional guidance
rather than a mandatory template. The `steps/03-plan-verification.md` says
"triage per `docs/work-styles/06-issue-triage.md`" but does not repeat the
detail requirements. The team leader's instinct to be concise conflicted with
the triage doc's explicit requirement to "show the full context without
compression."

**Affected steps**: `steps/03-plan-verification.md`

**Proposed changes**:

- In section 3b, add explicit instruction: "When presenting issues, follow the
  full 4-section format from the triage doc (Spec says / Code does / History /
  Impact) with exact quotes and line numbers. Do NOT summarize or compress."
- Add anti-pattern: "Don't compress issue presentations. One-line summaries
  belong in the group index only. Once triage begins on a group, each issue must
  have full spec quotes, exact code snippets, and concrete impact statements.
  The owner should never have to ask for more detail."

## SIP-4: Attempted to apply fixes during triage

**Discovered during**: Step 3 (Plan Verification)

**What happened**: After receiving the owner's disposition "플랜을 수정" for
Issue #2 (missing ClientDetached in DestroySessionRequest), the team leader
immediately read the plan file and started editing it. The owner interrupted:
"왜 지금 수정하지? 지금은 triage인데?" The triage doc
(`docs/work-styles/06-issue-triage.md`) line 118 explicitly states: "CRITICAL:
Do NOT apply fixes during triage. Triage determines dispositions only. Fixes are
collected and applied after all groups are triaged, unless the owner explicitly
says to fix something right now."

**Root cause**: The team leader interpreted the owner's "플랜을 수정" as an
instruction to fix now, rather than as a disposition statement (Fix — plan needs
revision). The triage doc's prohibition on mid-triage fixes was not top-of-mind
despite having read it earlier in the session.

**Affected steps**: `steps/03-plan-verification.md`

**Proposed changes**:

- In section 3b, add anti-pattern: "Don't apply fixes during triage. When the
  owner says 'fix this' or 'plan 수정', record it as a Fix disposition and move
  to the next issue. Only apply fixes after all groups are triaged, unless the
  owner explicitly says 'fix it right now.'"
- Consider adding a bolded reminder at the top of section 3b: "Triage is for
  dispositions only. Fixes come after."
