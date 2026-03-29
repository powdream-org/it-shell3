# Step 9: Commit & Report

## Anti-Patterns

- **Don't commit without verifying all gates.** Run through the checklist below
  — every item must be true before committing.
- **Don't skip reviewing the staged diff.** Read the diff before committing.
  Agent-written code may contain surprises — the team leader is the last
  checkpoint before the owner sees it. (Lesson from IME v0.7 cycle)
- **Don't commit the TODO.md.** It's a process artifact, not a deliverable. It
  stays in the module directory for the owner review (Step 10) and is deleted
  after the owner accepts.
- **Don't commit coverage reports.** They are gitignored and regenerated on
  demand.

## Action

### 9a. Update TODO.md

Update TODO.md: set **Step** to 9 (Commit & Report), mark Step 8 as `[x]`.

### 9b. Final gate verification

ALL of these must be true:

- [ ] All tests pass in Debug (`mise run test:macos`)
- [ ] All tests pass in ReleaseSafe (`mise run test:macos:release-safe`)
- [ ] Code formatted (`(cd <target> && zig fmt --check src/)`)
- [ ] Library builds without warnings (`zig build` with no diagnostics)
- [ ] Coverage targets met (line >= 95%, branch >= 90%, function = 100%) — or
      module-level exemption granted
- [ ] Over-engineering review: clean pass (no open findings)
- [ ] Spec compliance review: clean pass (no open issues)
- [ ] Test count matches expected total from implementer + QA reports (verify
      the actual count from `mise run test:macos` against the sum of both
      agents' reported test counts — missing tests indicate lost files)

If any gate fails, return to the appropriate step.

### 9b. Disband the implementation team

Send shutdown to all team members (implementer, QA reviewer, over-engineering
reviewer). Wait for confirmation.

Update TODO.md:

- **Active Team**: (none)
- **Team Directory**: (none)

### 9c. Review staged diff

Stage all source files and tests (NOT TODO.md, NOT coverage reports):

```bash
cd <target>
git add src/ build.zig build.zig.zon
```

Read the diff:

```bash
git diff --cached
```

Scan for:

- Accidentally committed secrets or credentials
- Debug prints or TODO comments left in code
- Files that shouldn't be committed (coverage reports, temporary files)

### 9d. Commit

Commit with a descriptive message following the project's commit convention (see
`docs/conventions/commit-messages.md`):

```bash
git commit -m "$(cat <<'EOF'
feat(<module>): implement <brief description>

<what was implemented, test count, coverage numbers>
EOF
)"
```

### 9e. Report to owner

Present to the owner:

1. What was implemented (module, spec version, file count)
2. Test summary (total tests, integration test categories covered)
3. Coverage numbers (or scenario-matrix count if exempted)
4. Spec gaps discovered (from TODO.md's Spec Gap Log) — if any
5. Any owner decisions recorded during implementation

## Gate

- [ ] All final gates verified (9a)
- [ ] Team disbanded (9b)
- [ ] Diff reviewed (9c)
- [ ] Code committed (9d)
- [ ] Owner notified (9e)

## State Update

Update TODO.md:

- **Step**: 10 (Owner Review)
- Mark Step 9 as `[x]`

## Next

Read `steps/10-owner-review.md`.
