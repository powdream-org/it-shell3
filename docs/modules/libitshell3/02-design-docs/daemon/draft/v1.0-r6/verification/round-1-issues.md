# Verification Round 1 Issues — Daemon v1.0-r6

- **Date**: 2026-03-23
- **Phase 1 agents**: consistency-verifier (sonnet), semantic-verifier (sonnet)
- **Phase 2 agents**: issue-reviewer-fast (sonnet), issue-reviewer-deep (opus)

---

## Confirmed Issues

### SEM-01 (critical) — doc04 §8 "per-session lock" contradicts single-threaded no-lock architecture

- **Location**: `04-runtime-policies.md` §8.1, §8.3, §8.4
- **Description**: doc04 §8.1 step 1 says "Acquire the per-session lock" and
  step 10 says "Release the per-session lock." Same lock language appears in
  §8.3 (focus change) and §8.4 (InputMethodSwitch). However, the architecture is
  explicitly single-threaded with no locks: doc01 §2.1 ("No threads, no locks,
  no mutexes"), doc01 §2.3, doc02 §4.5, doc03 §1.2. These statements are
  irreconcilable.
- **Expected correction**: Remove all lock acquire/release steps from §8
  procedures. Replace with a note that the single-threaded event loop provides
  implicit serialization — no lock is needed or possible.
- **Impact chain**: doc04 §8.1, §8.3, §8.4. No impact on other docs (doc01,
  doc02, doc03 already state the correct no-lock architecture).
- **Pre-existing**: No. New in r6 via CTR-11.

### SEM-02 (minor) — doc04 §8 inconsistent lock ownership pattern across procedures

- **Location**: `04-runtime-policies.md` §8.1, §8.2, §8.3, §8.4
- **Description**: §8.2 procedures call §8.1 steps 1-8 (including lock
  acquire/release). §8.3 focus change acquires its own lock then calls §8.1
  steps 2-6 (skipping lock steps). §8.4 InputMethodSwitch acquires its own lock.
  The lock ownership pattern is inconsistent — some callers delegate lock to
  §8.1, others acquire independently.
- **Expected correction**: Follows from SEM-01 fix. When lock language is
  removed, the ownership ambiguity disappears. The step references (e.g.,
  "Execute §8.1 steps 2-6") should be reviewed for correctness after lock steps
  are removed and renumbered.
- **Impact chain**: doc04 §8.1, §8.2, §8.3, §8.4. Internal to §8 only.
- **Pre-existing**: No. New in r6 via CTR-11.

### CRX-01 (HIGH) — PreeditState missing from doc01 §3.2 class diagram and §3.3 Session struct

- **Location**: `01-internal-architecture.md` §3.2, §3.3
- **Description**: Resolution 2 mandates adding `preedit: PreeditState` to the
  Session struct. doc04 §6.1 references `session.preedit.owner` and
  `session.preedit.session_id`. But doc01 §3.2 (class diagram) and §3.3 (Session
  struct code block) do not include the `PreeditState` sub-struct or the
  `preedit` field.
- **Expected correction**: Add `preedit: PreeditState` field to the Session
  struct in §3.3 code block. Add `PreeditState` struct definition (owner: ?u32,
  session_id: u32). Update §3.2 class diagram to include the field.
- **Impact chain**: doc01 §3.2, §3.3. doc04 §6.1 already references the field
  correctly — no change needed there.
- **Pre-existing**: No. New in r6 (resolution applied to doc04 but missed in
  doc01).

### CRX-02 (HIGH) — doc01 §5.2 mouse data flow contradicts doc02 §4.8

- **Location**: `01-internal-architecture.md` §5.2
- **Description**: doc01 §5.2 states "Mouse events follow a simpler path — no
  IME involvement." But doc02 §4.8 (updated per CTR-04) now states "MouseButton
  events MUST commit preedit before processing." doc04 §8.4 also documents the
  mouse click procedure. Direct contradiction.
- **Expected correction**: Update doc01 §5.2 to state that MouseButton events
  trigger a preedit flush before forwarding. Update the sequence diagram to
  include the preedit check. MouseScroll/MouseMove remain exempt.
- **Impact chain**: doc01 §5.2. doc02 §4.8 and doc04 §8.4 are already correct.
- **Pre-existing**: No. New in r6 (CTR-04 updated doc02 but not doc01).

### CRX-05 (LOW, pre-existing) — "itshell3-daemon" vs "it-shell3-daemon" in doc03

- **Location**: `03-lifecycle-and-connections.md` §1.3, §7
- **Description**: The unhyphenated form `itshell3-daemon` appears in §1.3
  (fork+exec table) and §7 (SSH example), but the project name uses the
  hyphenated form `it-shell3-daemon` (as seen in §6.1 LaunchAgent plist).
- **Expected correction**: Replace `itshell3-daemon` with `it-shell3-daemon` in
  §1.3 and §7.
- **Impact chain**: doc03 only. Two locations.
- **Pre-existing**: Yes. Same inconsistency existed in v1.0-r5.

---

## Dismissed Issues

| Issue  | Dismiss reason                                                                     |
| ------ | ---------------------------------------------------------------------------------- |
| CRX-03 | Resolution doc process artifact — §3.5→§3.2 reference error. Fixed by team leader. |
| CRX-04 | Resolution doc process artifact — CTR-12 target doc01→doc02. Fixed by team leader. |
| SEM-03 | Resolution doc process artifact — procedure count 9→12. Fixed by team leader.      |
