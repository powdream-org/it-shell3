# Step 5: Verification

## Anti-Patterns

- Do NOT tell Phase 1 or Phase 2 agents to "read files" or "analyze documents
  directly." Provide file paths only — agents delegate to Gemini via
  `/invoke-agent:prompt` per their agent definitions.
- Do NOT assign areas or direct verifier work — each agent covers its full
  domain.
- Do NOT leave Phase 1 or Phase 2 agents alive after they report. Disband
  immediately.
- (Round 2+) Do NOT spawn Phase 1 agents without the Dismissed Issues Registry.

## Action

### 5a. Context check

Before spawning, check if context window is **25% or below**. If so, ask owner
to `/compact` first.

### 5b. Phase 1 — Issue Discovery

Spawn **both** Phase 1 agents from `.claude/agents/verification/phase1/`
(sonnet):

- `consistency-verifier` — structural integrity, cross-references, terminology
- `semantic-verifier` — logical contradictions, behavioral inconsistencies

Provide:

- List of all newly written/updated document paths
- Resolution document path
- **Round 2+ only:** Dismissed Issues Registry — structured data from all
  previous `round-{N}-issues.md` dismissed sections. Format:

  ```
  ## Dismissed Issues Registry
  - V1-03: [description] — Dismissed: [reason]
  - V1-05: [description] — Dismissed: [reason]
  - V2-01: [description] — Dismissed: [reason]
  ```

- **Cascade analysis instruction:** "For each issue, include an `impact_chain`
  listing all other documents/sections that would need coordinated changes if
  this issue is fixed."
- **Pre-existing issue flagging:** "For each issue, check whether it existed in
  the previous version (`draft/vX.Y-r<prev>/`). Flag pre-existing issues
  explicitly. Pre-existing issues MAY be deferred at owner discretion without
  counting toward the round threshold."

Collect both agents' issue lists. **Disband Phase 1 agents immediately.**

### 5c. Phase 2 — Double-Check

Spawn **both** Phase 2 agents from `.claude/agents/verification/phase2/`:

- `issue-reviewer-fast` (sonnet)
- `issue-reviewer-deep` (opus)

Provide:

- Combined Phase 1 issue list (merged from both Phase 1 agents)
- Document paths

Collect both agents' verdicts. **Disband Phase 2 agents immediately.**

### 5d. Apply outcome rules

For each issue:

- Both `confirm` → **confirmed** (true alarm)
- Both `dismiss` → **dismissed**
- One each → **contested** → report to owner with both reasons, request binding
  decision

### 5e. Cascaded re-raise monitoring (Round 3+)

Check whether newly raised issues are:

1. Re-raises of settled items from previous rounds
2. Minor cascading inconsistencies from previous fixes
3. Explanatory note cascades

If suspected, report to owner with evidence and let the owner decide.

## Gate

- [ ] Phase 1 agents spawned, reported, disbanded
- [ ] Phase 2 agents spawned, reported, disbanded
- [ ] All issues have a verdict (confirmed / dismissed / owner-decided)

## State Update

Update TODO.md:

- `Current State` → `Step: 6 (Fix Round Decision)`
- `Verification Round` → N (increment from previous)
- `Active Team` → (none)
- Mark `Step 5` as `[x]` (or `Step 5: Verification (Round N)` for Round 2+)

## Next

- If **any confirmed issues** → Read `steps/06-fix-round.md`
- If **all dismissed** → Read `steps/07-commit-and-report.md`
