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
