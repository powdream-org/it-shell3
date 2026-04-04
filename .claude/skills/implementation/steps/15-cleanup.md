# Step 15: Cleanup & ROADMAP Update

## Anti-Patterns

- **Don't batch-delete TODO.md files across modules.** Each module may be in a
  different cycle stage. Verify the cycle status of each TODO.md before deletion
  — only delete files belonging to the cycle being cleaned up.
- **Don't skip the ROADMAP update.** The ROADMAP is the project's master index.
  If it still says "Not started" after a plan is done, the next session will not
  know the work was completed.

## Action

### 15a. Update TODO.md

Update TODO.md: set **Step** to 15 (Cleanup & ROADMAP Update), mark Step 14 as
`[x]`.

### 15b. Update ROADMAP.md

Update `docs/superpowers/plans/ROADMAP.md`:

1. **Plan Index table**: Set the plan's Status to `**Done**`
2. **Current Status table**: Update source file count, test count, and coverage
   numbers for all affected modules
3. **Dependency Graph**: Add `✅` to the completed plan's node label
4. **Plan Summary**: Change the heading from `(Not Started)` to `(Done)` and
   update the summary with key deliverables if needed

### 15c. Delete implementation artifacts

1. Delete `<target>/TODO.md`
2. Delete `<target>/retrospective/` (SIPs have been processed in Step 14)

### 15d. Commit and push

```bash
git add -u docs/superpowers/plans/ROADMAP.md
git commit -m "$(cat <<'EOF'
chore(<target>): clean up artifacts and update ROADMAP

Remove TODO.md and processed SIPs. Update ROADMAP.md: plan status,
test counts, dependency graph.
EOF
)"
git push
```

## Gate

- [ ] ROADMAP.md Plan Index status updated to Done:
      `grep '<plan-name>' docs/superpowers/plans/ROADMAP.md` → contains "Done"
- [ ] ROADMAP.md Current Status table has correct numbers:
      `grep -A3 'Current Status' docs/superpowers/plans/ROADMAP.md` →
      file/test/coverage numbers match actual
- [ ] ROADMAP.md dependency graph has checkmark on completed plan:
      `grep '<plan-name>' docs/superpowers/plans/ROADMAP.md` → node label
      includes completion marker
- [ ] TODO.md deleted: `ls <target>/TODO.md 2>/dev/null` → exit code non-zero
      (file gone)
- [ ] retrospective/ deleted: `ls <target>/retrospective/ 2>/dev/null` → exit
      code non-zero (directory gone)
- [ ] Committed and pushed: `git log -1 --oneline` → commit message references
      cleanup; `git status` → clean working tree
