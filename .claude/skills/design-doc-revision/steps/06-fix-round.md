# Step 6: Fix Round Decision

## Anti-Patterns

- Do NOT skip issue recording — the issues file is the structured input for the
  fix team.
- Do NOT write issues to `review-notes/` — verification issues go to
  `verification/round-{N}-issues.md`.
- Do NOT auto-proceed past Round 3. Round 4+ requires owner escalation.
- Do NOT forget to include the Dismissed Issues Summary in the issues file — it
  prevents re-raises in subsequent rounds.

## Action

### 6a. Record confirmed issues

Write confirmed issues to `draft/vX.Y-rN/verification/round-{N}-issues.md`.
Format follows the verification issues convention. Include:

- Round metadata (round number, date, verifier agents)
- Each confirmed issue with: ID, severity, source docs, description, expected
  correction, impact chain (from Phase 1 cascade analysis)
- **Dismissed Issues Summary** (mandatory): all dismissed issues with dismiss
  reasons — this section is passed to Phase 1 agents in subsequent rounds

### 6b. Decide next step

| Condition              | Action                                                                                                                         |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| **Round 1–3**          | Automatic fix round. Go to Step 4.                                                                                             |
| **Round 4+ non-CLEAN** | **STOP.** Report all outstanding issues to the owner. Request triage: which issues are blocking vs. acceptable. Owner decides: |
|                        | → **Proceed**: Go to Step 4 for another fix round                                                                              |
|                        | → **Declare clean**: Remaining issues are acceptable. Go to Step 7.                                                            |
|                        | → **Declare deferred**: Known issues deferred to future version. Go to Step 7.                                                 |

## Gate

- [ ] Issues file written to `verification/round-{N}-issues.md`
- [ ] Round number checked against threshold (1–3 auto, 4+ owner)
- [ ] If Round 4+: owner has responded with decision

## State Update

Update TODO.md:

- If fix round → `Current State` → `Step: 4 (Writing)`, add
  `Step 5:
  Verification (Round N+1)` to Progress
- If clean/deferred → `Current State` → `Step: 7 (Commit)`
- Mark `Step 6` as `[x]`

## Next

- Fix round → Read `steps/04-writing.md`
- Clean/deferred → Read `steps/07-commit-and-report.md`
