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
