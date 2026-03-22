# Step 2: Team Discussion & Consensus

## Anti-Patterns

- Do NOT proxy messages between agents — they talk peer-to-peer directly.
- Do NOT prompt the consensus reporter to deliver. Wait for unprompted delivery.
- Do NOT judge whether discussion has converged. Only the consensus reporter
  decides when consensus is reached.
- Do NOT choose a subset of team members. Spawn ALL core members listed in the
  team's agent directory.

## Action

1. Spawn **ALL** core members (opus) from the team directory. Use `ls -la` to
   discover members (symlinks!).
2. Designate one agent as the **consensus reporter** (typically the architecture
   lead or principal architect). This agent will autonomously decide when
   consensus is reached and deliver the report unprompted.
3. Pass all input materials (requirements, review notes, handover, CTRs,
   previous spec docs) to the team.
4. Facilitate: set the goal, relay owner instructions when they come, report
   progress and opinion summaries to the owner. Do NOT do research, make design
   decisions, or write documents.
5. **Wait.** The consensus reporter delivers when ready. Do not rush this.

## Gate

- [ ] Consensus reporter has delivered the consensus report unprompted
- [ ] All agreed positions, caveats, and unresolved items are clearly stated

## State Update

Update TODO.md:

- `Current State` → `Step: 3 (Resolution)`
- `Active Team` → team name
- `Team Directory` → team directory path
- Mark `Step 2` as `[x]`

## Next

Read `steps/03-resolution.md`.
