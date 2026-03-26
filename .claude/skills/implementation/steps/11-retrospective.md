# Step 11: Retrospective & Cleanup

## Anti-Patterns

- **Don't skip this step.** Every implementation cycle produces lessons — even
  smooth ones confirm that existing practices work. Skipping loses institutional
  knowledge.
- **Don't edit skill or doc files without owner approval.** Present proposals,
  wait for approval, then apply.
- **Don't clean up before the retrospective.** TODO.md contains the cycle
  history needed for review. Delete it after, not before.

## Action

### 11a. Review the cycle

Read TODO.md's Progress section end-to-end. Answer these questions:

1. **Toolchain issues** — Did we hit any Zig, build system, or vendored C
   problems? Are they already in `docs/insights/implementation-learnings.md`?
2. **Spec gaps** — Were spec gaps discovered (check the Spec Gap Log)? Have they
   been reported for the design revision cycle?
3. **Process issues** — Were there steps that were unclear, gates that didn't
   catch problems, or anti-patterns we hit anyway?
4. **Review rounds** — How many compliance/fix/coverage/over-engineering loops
   did we go through? Were any avoidable?
5. **Team dynamics** — Did peer-to-peer communication work? Was the team leader
   bottlenecking or micromanaging?
6. **What worked well** — Approaches that should be preserved or reinforced.

### 11b. Update implementation-learnings.md

For any new toolchain or testing lessons discovered during this cycle, update
`docs/insights/implementation-learnings.md`:

- Add new rows to the appropriate table (Zig Toolchain, Testing, or create a new
  category if needed)
- Each entry needs: lesson number, lesson title, origin module, and impact
  description
- Do NOT duplicate existing entries — check first

### 11c. Review and finalize accumulated proposals

Review SIPs accumulated via `/sip` during the cycle at
`<target>/retrospective/skill-improvement-proposals.md`.

For each problem identified in 11a that is not already captured, run
`/sip <description>` to add it now.

- Draft a specific edit to the relevant step file:
  - Add a new anti-pattern if one was discovered
  - Clarify a gate condition if it was ambiguous
  - Add a missing instruction if a step was unclear
  - Remove unnecessary steps if they wasted tokens

Present each proposal to the owner with rationale. Wait for owner approval
before editing any skill files. If approved: apply the change and commit with
reason.

### 11d. Cleanup

After retrospective is complete:

1. Delete `<target>/TODO.md`
2. Delete `<target>/retrospective/` (SIPs have been processed in 11c)
3. Delete the implementation plan (`.claude/plan/<name>.md`)
4. Commit:

```bash
git add -u
git commit -m "$(cat <<'EOF'
chore(<target>): clean up implementation artifacts

Remove TODO.md, processed SIPs, and implementation plan after owner acceptance.
EOF
)"
```

## Gate

- [ ] Cycle reviewed (11a)
- [ ] `implementation-learnings.md` updated (or confirmed no new lessons)
- [ ] Skill improvements proposed and applied (or confirmed none needed)
- [ ] TODO.md and plan deleted, cleanup committed

## State Update

Implementation is **Complete**. No further TODO.md updates (it's been deleted).

## Next

**Done.** Report completion to the owner.
