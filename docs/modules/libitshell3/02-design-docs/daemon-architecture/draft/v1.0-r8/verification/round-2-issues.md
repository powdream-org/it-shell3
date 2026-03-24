# Verification Round 2 Issues

- **Date**: 2026-03-25
- **Round**: 2
- **Phase 1 agents**: consistency-verifier-r2 (sonnet), semantic-verifier-r2
  (sonnet)
- **Phase 2 agents**: reviewer-fast-r2 (sonnet), reviewer-deep-r2 (opus)

---

## Confirmed Issues

### C2-01 | minor | `session_id` vs `preedit_session_id` in policies §7.2

**Location**: `daemon-behavior/.../03-policies-and-procedures.md` §7.2

**Description**: Uses `session_id=N` and `Client_B` (capital C) in
PreeditEnd/PreeditStart observable effects. All other occurrences use
`preedit_session_id` and `client_B` (lowercase c).

**Expected correction**: Change `session_id` → `preedit_session_id` and
`Client_B` → `client_B`.

**Impact chain**: 03-policies-and-procedures §7.2.

**Pre-existing**: yes

---

### C2-02 | minor | Flag casing: `PANE_EXITED`/`PTY_EOF` vs `pane_exited`/`pty_eof`

**Location**: `daemon-behavior/.../02-event-handling.md` §1.3, §2.1, §2.2 vs
`daemon-architecture/.../02-state-and-types.md` §1.4

**Description**: Behavior doc uses uppercase (`PANE_EXITED`, `PTY_EOF`);
architecture doc uses lowercase (`pane_exited`, `pty_eof`). Same flags, different
casing.

**Expected correction**: Standardize on uppercase (`PANE_EXITED`, `PTY_EOF`) in
02-state-and-types §1.4.

**Impact chain**: 02-state-and-types §1.4.

**Pre-existing**: yes

---

### S2-01 | minor | §3.2 item 6b self-contradictory wording

**Location**: `daemon-behavior/.../02-event-handling.md` §3.2 item 6b

**Description**: "to each attached client other than the auto-destroy path (no
requester exists)" — "other than" implies exclusion but no requester exists to
exclude. §4.4 correctly says "Sent to each attached client (no requester
exists)".

**Expected correction**: Change to "to each attached client (no requester exists
in the auto-destroy path)" or match §4.4 wording.

**Impact chain**: 02-event-handling §3.2.

**Pre-existing**: yes

---

### S2-02 | minor | Mouse click path missing preedit constraints

**Location**: `daemon-behavior/.../02-event-handling.md` §8.5 and
`daemon-behavior/.../03-policies-and-procedures.md` §8.8

**Description**: Mouse click preedit-ending path lacks explicit `preedit.owner`
clear and `preedit.session_id` increment constraints. Other preedit-ending paths
(§8.1, §8.2, §8.4) include these. The universal invariant in
02-state-and-types §3.2 requires them for all preedit-ending paths including
mouse click.

**Expected correction**: Add ordering constraints for owner clear and session_id
increment to both §8.5 and §8.8.

**Impact chain**: 02-event-handling §8.5, 03-policies-and-procedures §8.8.

**Pre-existing**: yes

---

## Dismissed Issues

| ID    | Dismiss Reason                                                                    |
| ----- | --------------------------------------------------------------------------------- |
| S2-03 | Cascade from G1-06 fix — PreeditEnd exemption makes "First" technically correct. |
