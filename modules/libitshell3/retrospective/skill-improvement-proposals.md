# Skill Improvement Proposals

## SIP-1: Target Resolution skill not invoked — team leader bypassed `/impl-resolve-target`

**Discovered during**: Step 1 (Requirements Intake)

**What happened**: SKILL.md explicitly says "Invoke `/impl-resolve-target` with
`<argument>`" as the very first action. Instead, the team leader manually read
the ROADMAP, identified the next plan, and performed target resolution by hand
without invoking the direct skill. The owner had to intervene and point out the
skip.

**Root cause**: The `/impl-resolve-target` skill is marked
`user-invocable:
false`, which means the `Skill` tool cannot invoke it. The team
leader interpreted this as needing to perform the resolution manually, but the
SKILL.md instruction was still an obligation. The ambiguity is: how should a
non-user-invocable direct skill be "invoked" by the team leader? The current
skill infrastructure does not provide a mechanism for internal-only skill
invocation — the team leader must read and follow the SKILL.md file manually,
which is what eventually happened, but only after being corrected.

**Affected steps**: `direct/impl-resolve-target/SKILL.md`, SKILL.md (top-level
Target Resolution section)

**Proposed changes**:

- Add an anti-pattern to SKILL.md Target Resolution section: "Don't skip the
  `/impl-resolve-target` procedure. Even though it is not user-invocable, the
  team leader MUST read `direct/impl-resolve-target/SKILL.md` and follow its
  steps before proceeding to the Entry Point."
- Add a note to `direct/impl-resolve-target/SKILL.md` clarifying execution
  model: "This skill is executed by the team leader directly — read this file
  and follow the steps. It is not invoked via the Skill tool."

## SIP-2: Triage presentation compressed below quality bar — team leader rewrote sub-agent draft

**Discovered during**: Step 7.5 (Convention Violation Triage)

**What happened**: The sub-agent prepared a full 5W1H presentation meeting the
triage quality bar (code examples, flow explanation, conflict point marking).
The team leader then compressed the draft when presenting to the owner —
stripping code examples, shortening the Why section, reducing Where to one-line
summaries. The owner had to intervene and point out the quality bar was not met.

**Root cause**: The team leader failed to apply the Instruction Priority defined
in using-superpowers: (1) user instructions > (2) superpowers skills > (3)
default system prompt. The triage skill (priority 2) defines an explicit quality
bar and anti-pattern against compressed summaries. The system prompt's "be extra
concise" directive (priority 3) should have been overridden. Instead, the team
leader applied the lower-priority conciseness directive over the higher-priority
skill quality bar, then reinterpreted "review for accuracy" as "rewrite for
brevity."

**Affected steps**: `/triage` skill (SKILL.md Section 0 Hard Gates, Section 4
Anti-patterns)

**Proposed changes**:

- Add explicit instruction to triage SKILL.md Hard Gates: "Review means verify
  accuracy and completeness. Do NOT compress, summarize, or rewrite the
  sub-agent's draft. Present it as-is with accuracy corrections only."
- Add to anti-patterns: "Rewriting the sub-agent's draft. The team leader
  reviews for accuracy, not brevity. If the sub-agent's draft is too long, it is
  calibrated to the quality examples — that length IS the quality bar."

## SIP-3: Convention fix delegated without reading the convention doc first

**Discovered during**: Step 7.5 (Convention Violation Triage)

**What happened**: After triage disposition (Fix), the team leader delegated the
convention fix to a sub-agent without first reading
`docs/conventions/zig-documentation.md` Section 5 to verify the exact rule. The
delegation prompt included ad-hoc example transformations based on the fork's
report instead of the authoritative convention text. The sub-agent happened to
read the convention doc on its own, but the team leader's delegation
instructions could have been inaccurate if the fork's description was imprecise.

**Root cause**: The team leader treated the fork's violation report as
authoritative instead of the convention document itself. Delegation should be
based on verified primary sources, not secondhand reports.

**Affected steps**: Step 7.5 (triage fix application), `/triage` skill
post-triage execution

**Proposed changes**:

- Add instruction to triage post-disposition execution: "Before delegating a
  convention fix, read the cited convention doc section to verify the exact
  rule. Include the rule text or a direct reference in the delegation prompt."

## SIP-4: Triage grouping fragmented — one-issue groups are meaningless

**Discovered during**: Step 8.5 (Spec Compliance Triage)

**What happened**: The team leader created 5 groups for 7 issues, with 3 groups
containing only a single issue each. The triage skill says "Group issues by root
cause, not by symptom" — but the team leader grouped by surface-level component
(write handler, coalescing, resize, flow control, WAN bandwidth) instead of by
root cause. When re-examined, 4 of the 7 issues share the same root cause
(integration pipelines stubbed but not wired), and the remaining issues
naturally form 2 groups (missing tests, spec ambiguity). The initial 5-group
structure hid the relationship between issues and forced the owner to intervene.

**Root cause**: The team leader applied "group by component/area" literally
(each file = one component = one group) instead of asking "what underlying cause
connects these issues?" A single-issue group is a signal that the grouping
criterion is too fine-grained — if an issue has no peers under the chosen
grouping, the grouping is wrong. The triage skill's instruction says "root
cause" but the team leader defaulted to surface-level categorization.

**Affected steps**: `/triage` skill (SKILL.md Section 1, Step 1)

**Proposed changes**:

- Add to triage SKILL.md grouping instruction: "A group with only one issue is a
  smell — re-examine whether the grouping criterion is too fine-grained.
  Single-issue groups are acceptable only when the issue is genuinely unrelated
  to all others."
- Add anti-pattern: "Surface-level grouping. Grouping by file name or component
  instead of by root cause. Multiple files can share one root cause; one file
  can contain issues with different root causes. Ask 'what underlying cause
  connects these?' not 'which file is affected?'"

## SIP-5: Group index presented as flat issue list instead of group-level summary

**Discovered during**: Step 8.5 (Spec Compliance Triage)

**What happened**: Even after re-grouping into 3 root-cause groups, the team
leader presented the group index as a flat table listing all 7 issues with a
group column — effectively an issue-level index, not a group-level index. The
triage skill says "Present the group index" and "Owner picks the next group" —
the index should show groups (with issue counts and one-line root cause
descriptions), not individual issues. The owner had to intervene again to point
this out.

**Root cause**: The team leader confused "group index" with "issue index grouped
by column." A group index shows groups as the primary unit (3 rows for 3
groups), while an issue index shows issues as the primary unit (7 rows). The
triage skill's Step 2 says "compact table with one-line titles per issue" which
is ambiguous — it says "per issue" but the purpose is "birds-eye view" which is
better served by group-level rows when groups exist.

**Affected steps**: `/triage` skill (SKILL.md Section 1, Step 2)

**Proposed changes**:

- Clarify triage SKILL.md Step 2: "Present the group index as a group-level
  table: one row per group, with group name, issue count, and root cause
  summary. Individual issue titles go inside the group when it is selected — not
  in the index."
- Add example format to Step 2:
  ```
  | # | Group | Count | Root Cause |
  | A | Pipeline stubs | 4 | Utilities created but orchestration not wired |
  | B | Missing tests | 2 | No tests for unimplemented orchestration |
  ```

## SIP-6: Group index missing group IDs — owner cannot reference groups

**Discovered during**: Step 8.5 (Spec Compliance Triage)

**What happened**: The group index table had no group ID column (A, B, C or 1,
2, 3). When the owner is asked "which group would you like to start with?" they
need a short identifier to reference. Without IDs, the owner must type out the
full group name. This is a basic usability issue.

**Root cause**: The triage skill's Step 3 says "Owner picks the next group" but
does not specify that groups need identifiers. The team leader did not add IDs
because the skill didn't require them, but it's obvious that selectable items
need identifiers.

**Affected steps**: `/triage` skill (SKILL.md Section 1, Steps 2-3)

**Proposed changes**:

- Add to triage SKILL.md Step 2: "Assign each group a short ID (A, B, C or 1,
  2, 3) so the owner can reference it easily."
- Update the example format in Step 2 to include an ID column.

## SIP-8: Alive agent misidentified as zombie — killed working impl-review-r3

**Discovered during**: Step 8 Round 3 (Spec Compliance Review)

**What happened**: `impl-review-r3` was sending idle notifications while its
sub-agents performed the review. The team leader sent a status check message,
received idle notifications but no text reply, and concluded the agent was a
zombie. The team leader shut it down and spawned a replacement, wasting the
in-progress review work.

**Root cause**: The team leader confused "not responding to my text message"
with "zombie." An agent sending idle notifications is alive — it's busy waiting
for sub-agent results. A zombie is an agent that produces no output at all (no
idle notifications, no shutdown_approved, nothing). The correct action was to
wait longer, not to kill and respawn.

**Affected steps**: Not step-specific — general agent lifecycle management.

**Proposed changes**:

- Add to MEMORY.md zombie definition: "An agent sending idle notifications is
  ALIVE. Only agents producing zero output are potential zombies."
- Add to implementation SKILL.md zombie prevention: "Wait at least 5 minutes
  after the last idle notification before considering an agent a zombie. Idle
  notifications prove the agent process is running."

## SIP-9: context: fork steps executed as fresh Agent spawns without context inheritance

**Discovered during**: Step 8 Round 3 (Spec Compliance Review)

**What happened**: All `context: fork` steps (6, 7, 8 R1, 8 R2, 8 R3, 9) were
dispatched using the Agent tool with fresh spawns. Each time, the team leader
manually summarized context in the prompt instead of forking with full context
inheritance. The fork agents started from scratch — re-reading spec files,
re-discovering project structure, losing nuance from the team leader's
accumulated understanding. This caused:

- Shallower reviews (agents lacked context the team leader had built up)
- Inconsistent results between rounds (each agent had different understanding)
- The `spec-review-fresh` agent doing a grep-based check instead of a full dual
  review because it didn't inherit the understanding of what Step 8 requires

**Root cause**: The team leader did not understand what `context: fork` means.
It means spawning a subagent that inherits the parent's full context
(conversation history, file reads, accumulated state) — not a fresh agent with a
manual prompt summary. The Agent tool documentation says "Each Agent invocation
starts fresh" but `context: fork` requires context inheritance, which may need a
different invocation mechanism.

**Affected steps**: All fork steps — `isolated/impl-execute/SKILL.md`,
`isolated/impl-simplify/SKILL.md`, `isolated/impl-review/SKILL.md`,
`isolated/impl-fix/SKILL.md`

**Proposed changes**:

- Add to implementation SKILL.md fork dispatch instructions: "context: fork
  means the subagent inherits the team leader's full conversation context. Do
  NOT use a fresh Agent spawn with a manual summary prompt. Use the context fork
  mechanism to ensure the subagent has the same understanding as the team
  leader."
- Document the correct invocation mechanism for context forking in the skill
  infrastructure.

## SIP-10: Fork steps and target resolution must be invoked via Skill tool

**Discovered during**: Step 8 Round 3 (Spec Compliance Review)

**What happened**: Steps 1 (impl-resolve-target) and 6-9 (impl-execute,
impl-simplify, impl-review, impl-fix) all have dedicated skill files with
`context: fork` frontmatter. Throughout the entire Plan 9 cycle, the team leader
used the Agent tool with manual prompts instead of the Skill tool. This meant:

- No context inheritance (fork semantics lost)
- Manual prompt summaries instead of full context
- Shallower reviews due to missing accumulated understanding
- One instance (spec-review-fresh) where the skill procedure was completely
  bypassed, producing a shallow grep-based check instead of a full dual review

**Root cause**: Two issues combined:

1. The skills had `user-invocable: false` which prevented Skill tool invocation
2. The skills were nested under `.claude/skills/implementation/isolated/` which
   the Skill tool doesn't discover (only `.claude/skills/` direct children) The
   fix was: remove `user-invocable: false` and create symlinks from
   `.claude/skills/` to the nested skill directories. After a session restart,
   the Skill tool recognized and correctly context-forked the skills.

**Affected steps**: `direct/impl-resolve-target/SKILL.md`,
`isolated/impl-execute/SKILL.md`, `isolated/impl-simplify/SKILL.md`,
`isolated/impl-review/SKILL.md`, `isolated/impl-fix/SKILL.md`

**Proposed changes**:

- Remove `user-invocable: false` from all fork skill frontmatters
- Add symlinks from `.claude/skills/` to each nested fork skill directory
  (already done: impl-execute, impl-simplify, impl-review, impl-fix)
- Add to implementation SKILL.md Cross-Cutting Rules: "Fork steps (6-9) MUST be
  dispatched via the Skill tool (`/impl-execute`, `/impl-review`, etc.), NOT via
  the Agent tool. The Skill tool invokes `context: fork` which inherits the team
  leader's full context. Agent tool starts fresh."
- Add symlink for impl-resolve-target as well

## SIP-11: Team leader overrode sub-agent quality bar with "keep it brief" instruction

**Discovered during**: Step 11 (Over-Engineering Review)

**What happened**: When spawning the triage prep sub-agent for 10
over-engineering findings, the team leader included the instruction: "These are
mostly low-severity findings so keep presentations proportional — don't
over-elaborate simple dead code removals." This overrode the quality bar that
the sub-agent should have derived from reading the quality examples. The triage
skill says the sub-agent reads quality examples to calibrate depth — the team
leader's job is to point the sub-agent to the examples and the skill file, not
to pre-judge severity or dictate depth.

**Root cause**: The team leader treated the sub-agent as an executor of
instructions rather than a calibrated reviewer. The triage skill's design is:
sub-agent reads examples → sub-agent determines appropriate depth. The team
leader's role is to provide the issues and point to the skill/examples — not to
summarize the skill's quality requirements in their own words. When the team
leader paraphrases or overrides, the sub-agent never reads the actual examples
and the quality bar is whatever the team leader guessed.

**Affected steps**: `/triage` skill (sub-agent spawning in Step 4)

**Proposed changes**:

- Add to triage SKILL.md Step 4: "The team leader MUST NOT include quality
  guidance in the sub-agent prompt. Point the sub-agent to the skill file and
  examples directory — let it read and calibrate directly. Instructions like
  'keep it brief' or 'these are simple' override the quality bar."
- Add anti-pattern: "Paraphrasing the quality bar. Telling the sub-agent what
  depth to use instead of letting it read the examples. The examples ARE the
  teaching mechanism — the team leader cannot substitute for them."

## SIP-12: Team leader modified sub-agent's How section to be prescriptive

**Discovered during**: Step 11 (Over-Engineering Review)

**What happened**: When presenting finding [10], the team leader changed the
sub-agent's How section from an open question ("The owner may wish to
disposition [9] and [10] together") to a prescriptive recommendation ("Delete
the test"). The team leader also added content not in the sub-agent's draft
(behavioral tests reference, exhaustive switch mention). This violates two
triage rules simultaneously:

1. SIP-2: "Do NOT compress, summarize, or rewrite the sub-agent's draft. Present
   it as-is with accuracy corrections only."
2. Triage anti-pattern: "Pressuring the owner. Adding urgency markers, severity
   opinions, or recommendations to the presentation."

**Root cause**: The team leader has a persistent habit of modifying sub-agent
drafts during presentation — sometimes compressing (SIP-2), sometimes adding
content and changing tone (this SIP). Both violate the same principle: the
sub-agent's draft is the presentation, not raw material for the team leader to
edit. The team leader's review step is accuracy verification only.

**Affected steps**: `/triage` skill (SKILL.md Section 0 Hard Gates, Section 2
How, Section 4 Anti-patterns)

**Proposed changes**:

- Strengthen triage SKILL.md Hard Gate: "Present the sub-agent's draft VERBATIM.
  The only allowed modifications are factual corrections (wrong line numbers,
  incorrect quotes). Adding opinions, recommendations, extra context, or
  rewording the How section is prohibited."
- Add anti-pattern: "Editing the draft. Adding content, changing wording, or
  reframing the How section. The sub-agent calibrated against quality examples —
  the team leader's edits decalibrate the presentation."
