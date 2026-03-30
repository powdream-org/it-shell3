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

### 6b. Pre-fix analysis

Before spawning fix writers, perform the following analyses. Include all results
in the fix writers' input.

#### 6b.1. Same-class sweep (MANDATORY for cross-doc issues)

If a confirmed issue belongs to a class that could repeat across other files
(e.g., stale cross-module links, stale section references, incorrect metadata
format, API naming in diagrams), spawn a sweep agent to check ALL files for the
same class before spawning fix writers. This prevents whack-a-mole discovery
across multiple rounds.

**Do NOT skip this for "simple" fixes.** Even an apparently trivial cross-doc
fix (e.g., renaming an API call in a diagram) can diverge when parallel writers
make independent judgment calls. Every cross-doc confirmed issue MUST trigger a
sweep to identify all related locations, which then become a single issue
cluster assigned to one writer (see Step 4, §4b).

#### 6b.2. Cross-document cascade analysis

Spawn a cascade analysis agent (opus) to assess each confirmed issue's fix
impact across all documents. The cascade report identifies:

- Other documents/sections that need coordinated changes
- Risk level (none / low / medium / high) per fix
- Whether fixes can safely be applied in parallel

#### 6b.3. Intra-procedure ordering check

**MANDATORY when a fix changes step ordering or adds conditional branches.** For
each fix that defers, reorders, or conditionally skips a step within a
procedure:

1. List all resources/state consumed by the deferred/moved step (fd, engine
   state, session fields, etc.)
2. Check whether any intervening step between the old and new position
   invalidates, closes, or frees those resources.
3. If yes, flag as a cascade risk and include in the fix writer's instructions.

### 6c. Decide next step

| Condition              | Action                                                                                                                      |
| ---------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| **Round 1–3**          | Automatic fix round. Go to Step 4.                                                                                          |
| **Round 4+ non-CLEAN** | **STOP.** Invoke `/triage` with all outstanding issues. Dispositions: Fix (another round), Declare clean, Declare deferred. |
|                        | → **Proceed**: Go to Step 4 for another fix round                                                                           |
|                        | → **Declare clean**: Remaining issues are acceptable. Go to Step 7.                                                         |
|                        | → **Declare deferred**: Known issues deferred to future version. Go to Step 7.                                              |

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

Checkpoint: commit all changed artifacts (TODO.md, issues file).

## Next

**Auto-proceed** — for Rounds 1-3. **Owner input required** for Round 4+.

- Fix round → Read `steps/04-writing.md`
- Clean/deferred → Read `steps/07-commit-and-report.md`
