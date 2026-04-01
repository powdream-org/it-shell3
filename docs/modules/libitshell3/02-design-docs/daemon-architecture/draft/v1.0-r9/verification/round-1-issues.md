# Verification Round 1 — Plan 15 Unified Cycle

- **Round**: 1
- **Date**: 2026-03-31
- **Phase 1 agents**: consistency-verifier (sonnet), semantic-verifier (sonnet)
- **Phase 2 agents**: issue-reviewer-fast (sonnet), issue-reviewer-deep (opus)

## Confirmed Issues

### S-1 [critical, new] — Stale AttachOrCreate in daemon-behavior timeout table

- **Location**: daemon-behavior `03-policies-and-procedures.md` Section 13, line
  850
- **Description**: Timeout table row says
  `READY -> AttachSession/CreateSession/AttachOrCreate`. AttachOrCreate
  (0x010C/0x010D) was deleted by Resolution 17. Must remove the reference.
- **impact_chain**: daemon-behavior 03 only (self-contained).

### S-2/C-3 [critical, partially new] — KeyEvent field name/type mismatch across 3 docs

- **Location**:
  - daemon-arch `02-state-and-types.md` Section 1.3: `keycode: u32`
  - IME contract `02-types.md` Section 1: `hid_keycode: u8`
  - protocol `04-input-and-renderstate.md` Section 2.1: `keycode: u16`
- **Description**: Three normative type definitions for the same USB HID usage
  code disagree on both field name and integer width. The daemon-arch `u32` was
  introduced in r9 (Resolution 16 cascade). IME contract uses `hid_keycode: u8`
  (bounded by `HID_KEYCODE_MAX = 0xE7`). Protocol wire uses `keycode: u16`.
- **impact_chain**: daemon-arch 02 (fix field name/type), daemon-arch 03
  (wire-decompose table references), protocol 04 (wire field name).

### S-4 [minor, new] — Stale mouse_encode in Mermaid diagram

- **Location**: daemon-arch `02-state-and-types.md` Section 3.2, lines 511, 516
- **Description**: Mermaid diagram uses `mouse_encode.encode()` (stale); prose
  at line 491 correctly uses `mouse_encoder.encode()`. Missed during Correction
  1 application.
- **impact_chain**: daemon-arch 02 only (self-contained).

### C-1 [critical, new] — Doc 04 "16-byte" header references (4 locations)

- **Location**: protocol `04-input-and-renderstate.md` lines 30, 330, 984, 1022
- **Description**: Four locations say "16-byte" header. Resolution 19 changed
  header from 16 to 20 bytes (u64 sequence). Doc 01 correctly says 20 bytes.
- **impact_chain**: protocol 04 only (self-contained).

### C-2 [critical, new] — Doc 05 "16-byte" header reference

- **Location**: protocol `05-cjk-preedit-protocol.md` line 654
- **Description**: Says "16-byte binary header" — should be 20-byte per
  Resolution 19.
- **impact_chain**: protocol 05 only (self-contained).

### C-5 [minor, new] — Protocol doc says "no connection limit"

- **Location**: protocol `01-protocol-overview.md` Section 5.5.3, lines 682-685
- **Description**: Says "No protocol-level limit on simultaneous connections."
  Resolution 7 established MAX_CLIENTS = 64. The protocol doc contradicts the
  daemon-behavior doc.
- **impact_chain**: protocol 01 only (self-contained).

## Dismissed Issues

### S-3 [minor, pre-existing] — DISMISSED (misread context)

- **Location**: daemon-arch `02-state-and-types.md` Section 1.5
- **Reason**: The "depth 15" parenthetical is a mathematical aside explaining
  why 31 node slots are needed for the array, not a normative claim that depth
  15 is reachable under MAX_TREE_DEPTH=4 enforcement. Both reviewers
  independently identified this as a misread.

### C-4 [minor, new] — DISMISSED (redundant with C-1)

- **Location**: protocol `04-input-and-renderstate.md` line 30-31
- **Reason**: Subset of C-1. The anchor target is correct
  (`#31-frame-header-20-bytes-fixed`) but the prose says "16-byte". Fixing C-1
  resolves this automatically.
