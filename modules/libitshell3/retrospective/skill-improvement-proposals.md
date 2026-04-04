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
