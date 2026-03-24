# Verification Round 2 Issues — Daemon v1.0-r6

- **Date**: 2026-03-23
- **Phase 1 agents**: consistency-verifier (sonnet), semantic-verifier (sonnet)
- **Phase 2 agents**: issue-reviewer-fast (sonnet), issue-reviewer-deep (opus)

---

## Confirmed Issues

### CRX-06 (minor) — doc01 §5.2 references "§8.1" but doc01 has no §8

- **Location**: `01-internal-architecture.md` §5.2, line ~1043
- **Expected correction**: "§8.1 flush sequence" → "doc04 §8.1 flush sequence"
- **Impact chain**: doc01 §5.2 only.

### CRX-07 (minor) — doc02 §4.5 references "Resolution 2" (stale)

- **Location**: `02-integration-boundaries.md` §4.5, line ~589
- **Expected correction**: "Resolution 2" → "doc01 §2"
- **Impact chain**: doc02 §4.5 only.

### CRX-08 (minor) — doc03 §4.5 references "Resolution 6" (stale)

- **Location**: `03-lifecycle-and-connections.md` §4.5, line ~611
- **Expected correction**: "Resolution 6" → "doc02 §4.2"
- **Impact chain**: doc03 §4.5 only.

### CRX-09 (minor) — doc03 §1 and §4.5 reference "Resolution 2" (stale, 2 locations)

- **Location**: `03-lifecycle-and-connections.md` §1 line ~175, §4.5 line ~616
- **Expected correction**: "Resolution 2" → "doc01 §2" at both locations
- **Impact chain**: doc03 only.

### CRX-10 (critical) — doc04 §8.3 focus change calls §8.1 steps 1-5, skipping session_id increment

- **Location**: `04-runtime-policies.md` §8.3 focus change, line ~671
- **Expected correction**: Change "steps 1-5" to "steps 1-7" (matching all other
  procedures). Remove redundant step 2 (manual owner clear) since §8.1 step 7
  already handles it.
- **Impact chain**: doc04 §8.3 only. Correctness bug — stale session_id breaks
  client preedit correlation.

### SEM-04 (critical) — doc02 §4.2 still says "MUST hold the per-session lock"

- **Location**: `02-integration-boundaries.md` §4.2, line ~489
- **Expected correction**: Remove lock language. Replace with: "The
  single-threaded event loop guarantees atomicity — both calls execute within a
  single event handler iteration."
- **Impact chain**: doc02 §4.2 only. Residual lock language missed in Round 1.

### SEM-05 (minor) — doc01 §5.2 and doc02 §4.8 diagrams show raw PTY write instead of terminal.mousePress()

- **Location**: `01-internal-architecture.md` §5.2 line ~1067,
  `02-integration-boundaries.md` §4.8 line ~706
- **Expected correction**: Update diagrams to show `terminal.mousePress()`
  instead of `write(pty_fd, mouse escape sequence)`.
- **Impact chain**: doc01 §5.2, doc02 §4.8.

### SEM-06 (minor) — doc04 §8.2 session detach sends duplicate PreeditEnd

- **Location**: `04-runtime-policies.md` §8.2 session detach, line ~650
- **Expected correction**: Remove step 2 ("Send PreeditEnd to remaining
  clients") — §8.1 step 5 already broadcasts PreeditEnd to all attached clients.
- **Impact chain**: doc04 §8.2 only.

### SEM-08 (minor) — doc03 §4.1 state diagram missing OPERATING→OPERATING self-loop

- **Location**: `03-lifecycle-and-connections.md` §4.1 state diagram
- **Expected correction**: Add
  `OPERATING --> OPERATING : AttachSessionRequest (different session)` to the
  mermaid state diagram.
- **Impact chain**: doc03 §4.1 only.

---

## Dismissed Issues

| Issue  | Dismiss reason                                                  |
| ------ | --------------------------------------------------------------- |
| TRM-01 | Non-normative pseudocode — fixed by team leader (pty→pty_fd).   |
| SEM-05 | ~~dismissed~~ Owner confirmed. Moved to confirmed issues above. |
| SEM-07 | Duplicate of CRX-10. Merged.                                    |
