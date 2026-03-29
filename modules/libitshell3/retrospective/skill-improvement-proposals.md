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

## SIP-5: Checkpoint commit after each step's state update

**Discovered during**: Step 5 (Scaffold & Build Verification)

**What happened**: Steps 1 through 5 completed with TODO.md and ROADMAP.md
updates at each step boundary, but no checkpoint commits were made until the
owner explicitly requested one after Step 5. By that point, 7 files had
accumulated across 5 steps worth of changes. If context had been lost or the
session interrupted, all progress tracking artifacts (TODO.md state, ROADMAP
status, plan file, CTR, SIPs) would have been uncommitted and potentially lost.

**Root cause**: No step file includes a "commit checkpoint" instruction in its
State Update section. The skill assumes commits happen only at Step 12 (Commit &
Report). Intermediate state changes (TODO.md step markers, ROADMAP status
updates, CTRs, SIPs) are left uncommitted across multiple steps.

**Affected steps**: All step files in both `/implementation` and
`/design-doc-revision` skills — specifically the "State Update" section of each
step.

**Proposed changes**:

- Add a cross-cutting rule in the main SKILL.md (Cross-Cutting Rules section):
  "After completing a step's State Update (TODO.md + ROADMAP changes), create a
  checkpoint commit with all changed files. Use prefix `chore(<target>):` and
  include the step number. This prevents progress loss on session interruption."
- Alternatively, add a "Checkpoint commit" instruction at the end of each step's
  State Update section: "Commit all changed files (TODO.md, ROADMAP.md, any
  artifacts created in this step)."

## SIP-6: Unnecessary owner confirmation requests between steps

**Discovered during**: Step 6 (Implementation Phase)

**What happened**: At multiple step boundaries (Step 3→4, Step 5→6), the team
leader asked "진행할까요?" or "다음 그룹 어디로 가시겠습니까?" and waited for
the owner to respond before continuing. This happened even when the step's gate
was fully satisfied and no owner decision was required. The only steps that
require explicit owner input are: Step 3b (triage dispositions), Step 4e (owner
approval before implementation), and Step 13 (owner review). All other step
transitions should proceed automatically when the gate is met.

**Root cause**: The step files' "Next" sections say "Read `steps/XX.md`" which
the team leader interpreted as needing owner permission before reading the next
step. Additionally, the team leader defaulted to a cautious "ask before
proceeding" posture even when no gate condition requires owner input.

**Affected steps**: Main SKILL.md (Cross-Cutting Rules section)

**Proposed changes**:

- Add a cross-cutting rule: "Auto-proceed between steps when the gate is fully
  satisfied and the step does not explicitly require owner input. Only pause for
  owner when: (1) triage requires dispositions (Step 3b), (2) cycle setup
  requires owner approval (Step 4e), (3) owner review (Step 13), or (4) the step
  file explicitly says 'wait for owner.' Do NOT ask 'proceed?' or '진행할까요?'
  at routine step boundaries."
- Add anti-pattern: "Don't ask permission to proceed to the next step when all
  gate conditions are met. Unnecessary confirmation requests waste the owner's
  time and break flow."

## SIP-7: Single implementer for parallelizable tasks — extremely slow

**Discovered during**: Step 6 (Implementation Phase)

**What happened**: The plan's dependency graph explicitly identifies
parallelizable task groups: Tasks 1, 2, 3, 4, 6 are all independent; Tasks 8, 9,
11, 12, 13 can run in parallel after Task 7. Despite this, the team leader
spawned a single implementer agent to work through all 15 tasks serially. This
makes the implementation phase far slower than necessary — tasks that could
execute concurrently are instead queued behind each other.

**Root cause**: Step 6 (06-implementation.md) section 6d says "Spawn implementer
and QA engineer in parallel" — singular implementer. The step file does not
mention spawning multiple implementer instances for independent task groups. The
plan's parallelizable groups information is not utilized at spawn time.

**Affected steps**: `steps/06-implementation.md`

**Proposed changes**:

- In section 6c (Prepare spawn context), add: "Analyze the plan's dependency
  graph for parallelizable task groups. For each independent group of 2+ tasks
  that touch different files, prepare a separate implementer spawn."
- In section 6d, change from spawning one implementer to: "Spawn one implementer
  per parallelizable task group. Each implementer receives only its assigned
  tasks and file list. Use worktree isolation if tasks touch overlapping files."
- Add example: "If the plan shows Tasks 1, 2, 3, 4, 6 as independent, spawn 5
  implementers in parallel (or group small tasks). Then spawn the next wave
  (Tasks 8, 9, 11, 12, 13) once their dependencies complete."
- Add anti-pattern: "Don't serialize parallelizable tasks into one implementer.
  The plan's dependency graph exists precisely to enable concurrent execution."

## SIP-8: Team leader attempted to self-triage instead of presenting to owner

**Discovered during**: Step 9 (Fix Cycle)

**What happened**: After the QA reviewer reported 8 [CODE] + 9 [TEST] issues,
the team leader began self-triaging: classifying issues as "바로 Fix 가능",
"구현 누락", "판단 필요" and making disposition recommendations (e.g., "Skip?"
for [CODE-8], "defer?" for [CODE-4]). Per `docs/work-styles/06-issue-triage.md`,
the team leader should group issues by component/area, present the group index
to the owner, and let the owner triage each issue one at a time. The team leader
does NOT pre-decide dispositions — presenting recommendations is a form of
pre-deciding that biases the owner's judgment.

**Root cause**: `steps/09-fix-cycle.md` section 9c says "Route issues to the
correct agent" without referencing the triage procedure. The team leader
interpreted Step 9 as "classify and fix" rather than "triage with owner first,
then route." The triage procedure from `06-issue-triage.md` applies to ALL
discovered issues, not just Step 3 verification issues.

**Affected steps**: `steps/09-fix-cycle.md`

**Proposed changes**:

- In section 9c, add: "Before routing issues, triage them with the owner per
  `docs/work-styles/06-issue-triage.md`. Group by component/area, present the
  index, and let the owner decide dispositions. Only after triage is complete
  should issues be routed to agents."
- Add anti-pattern: "Don't self-triage. The team leader groups and presents
  issues; the owner decides dispositions. Pre-classifying issues as 'fix',
  'defer', or 'skip' bypasses the owner's judgment."
