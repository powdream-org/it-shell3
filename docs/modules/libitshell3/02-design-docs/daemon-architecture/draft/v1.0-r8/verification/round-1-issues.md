# Verification Round 1 Issues

- **Date**: 2026-03-25
- **Round**: 1
- **Phase 1 agents**: consistency-verifier (sonnet), semantic-verifier (sonnet)
- **Phase 2 agents**: issue-reviewer-fast (sonnet), issue-reviewer-deep (opus)

---

## Confirmed Issues

### C1-01 | minor | FlatCell in 01-module-structure §1.2

**Location**: `daemon-architecture/.../01-module-structure.md` §1.2, ghostty/
helper table, row "Cell data export"

**Description**: Uses "Produce `FlatCell[]` for wire transfer." Resolution 6
mandates `CellData` as canonical wire-format name in architecture docs.

**Expected correction**: Change `FlatCell[]` to `CellData[]`.

**Impact chain**: 01-module-structure §1.2; cross-check
03-integration-boundaries §4.5 (already correct).

**Pre-existing**: no

---

### C1-02 | minor | FlatCell in 02-state-and-types §3.1

**Location**: `daemon-architecture/.../02-state-and-types.md` §3.1, sequence
diagram line `G-->>S: ExportResult (FlatCell[])`

**Description**: Architecture doc Mermaid diagram uses `FlatCell[]` instead of
`CellData[]` per Resolution 6.

**Expected correction**: Change `FlatCell[]` to `CellData[]`.

**Impact chain**: 02-state-and-types §3.1 only.

**Pre-existing**: no

---

### C1-03 | minor | FlatCell in 02-state-and-types §4.1

**Location**: `daemon-architecture/.../02-state-and-types.md` §4.1, sizing table
row "I-frame (120x40, 16-byte FlatCells)"

**Description**: Uses `FlatCells` instead of `CellData` in architecture doc
sizing table. Violates Resolution 6.

**Expected correction**: Change "16-byte FlatCells" to "16-byte CellData
entries".

**Impact chain**: 02-state-and-types §4.1 only.

**Pre-existing**: no

---

### C1-04 | minor | Wrong section reference in 02-state-and-types §4.2

**Location**: `daemon-architecture/.../02-state-and-types.md` §4.2, first
paragraph

**Description**: References "see Section 1.3" for `dirty_mask` on
`SessionEntry`, but §1.3 only contains a redirect to impl-constraints. The class
diagram showing `SessionEntry` with `dirty_mask` is in §1.2.

**Expected correction**: Change "see Section 1.3" to "see Section 1.2".

**Impact chain**: 02-state-and-types §4.2 only.

**Pre-existing**: no

---

### C1-05 | critical | Malformed list in 02-event-handling §3.2

**Location**: `daemon-behavior/.../02-event-handling.md` §3.2, Observable
Effects, conditional suffix for last pane

**Description**: Items 5b and 6b are concatenated on the same line without a
line break, making 6b invisible as a separate numbered entry.

**Expected correction**: Insert line break before "6b." so it starts its own
list item.

**Impact chain**: 02-event-handling §3.2.

**Pre-existing**: no

---

### C1-06 | minor | Wrong doc reference in 02-event-handling §9

**Location**: `daemon-behavior/.../02-event-handling.md` §9, last sentence

**Description**: Says the 5-tier input processing priority table is in "the
architecture docs." The table is in `03-policies-and-procedures.md` §6 (a
behavior doc).

**Expected correction**: Change "architecture docs" to "daemon behavior docs
(`03-policies-and-procedures.md` Section 6)".

**Impact chain**: 02-event-handling §9; 01-module-structure §2.4 (already
correct).

**Pre-existing**: no

---

### C1-07 | minor | InputMethodAck parameter name inconsistency

**Location**: `daemon-behavior/.../02-event-handling.md` §8.4 vs
`daemon-behavior/.../03-policies-and-procedures.md` §8.6

**Description**: `02-event-handling.md` uses `InputMethodAck(input_method=...)`;
`03-policies-and-procedures.md` uses `InputMethodAck(new_method=...)`. Different
parameter names for the same message field.

**Expected correction**: Standardize on the protocol spec's field name. Update
both docs to match.

**Impact chain**: 02-event-handling §8.4, 03-policies-and-procedures §8.6.

**Pre-existing**: no

---

### S1-01 | critical | §4.4 comparison table incomplete

**Location**: `daemon-behavior/.../02-event-handling.md` §4.4 comparison table

**Description**: The comparison table for shared teardown (pane-exit vs
explicit-destroy) does not list `DetachSessionResponse` for the SIGCHLD
last-pane path. §3.2 item 6b sends it to attached clients, but §4.4 omits it
entirely.

**Expected correction**: Add `DetachSessionResponse` row to §4.4 comparison
table, clarifying it is sent in §3.2 last-pane path but not in §4 explicit
destroy path (or vice versa, per the intended design).

**Impact chain**: 02-event-handling §3.2, §4.4.

**Pre-existing**: yes

---

### S1-02 | minor | Missing HANDSHAKING failure arc in state diagram

**Location**: `daemon-architecture/.../03-integration-boundaries.md` §6.1, state
diagram

**Description**: State diagram shows only HANDSHAKING → READY (success). Missing
the HANDSHAKING → [closed] failure arc (Invalid ClientHello / timeout). The
behavior doc §12 correctly specifies this transition.

**Expected correction**: Add `HANDSHAKING --> [*] : invalid / timeout` arc to
the Mermaid diagram.

**Impact chain**: 03-integration-boundaries §6.1.

**Pre-existing**: no

---

### S1-03 | minor | Shutdown trigger list incomplete

**Location**: `daemon-behavior/.../01-daemon-lifecycle.md` §2, trigger #2

**Description**: Trigger #2 ("The last remaining session's last pane exits")
only covers SIGCHLD auto-destroy. Does not cover `DestroySessionRequest`
explicitly destroying the last session leaving zero sessions.

**Expected correction**: Broaden trigger #2 to "No sessions remain" covering
both pane-exit auto-destroy and explicit DestroySessionRequest.

**Impact chain**: 01-daemon-lifecycle §2; 02-event-handling §4 (add cross-ref to
§2 shutdown).

**Pre-existing**: yes

---

### S1-04 | minor | PreeditEnd reason ambiguous in common prefix

**Location**: `daemon-behavior/.../02-event-handling.md` §3.2 common prefix item
4 vs §3.3 invariant

**Description**: Common prefix item 4 uses `reason="pane_closed"`
unconditionally, but §3.3 invariant requires `reason="session_destroyed"` for
the last-pane path. The common prefix applies to both paths, creating ambiguity.

**Expected correction**: Move PreeditEnd from common prefix to the conditional
branches with appropriate reason values: `"pane_closed"` for non-last,
`"session_destroyed"` for last pane.

**Impact chain**: 02-event-handling §3.2, §3.3.

**Pre-existing**: no (introduced by r8 common-prefix/conditional-suffix format)

---

### S1-05 | minor | Resolution 10 focus-change session_id not in arch docs

**Location**: Architecture docs (all three)

**Description**: Resolution 10 required adding `session_id` increment annotation
to the focus-change path in architecture docs. No architecture doc contains a
focus-change diagram or note with `session_id` increment.

**Expected correction**: Add a focus-change annotation in 02-state-and-types §3
(or appropriate section) showing `session_id` increment, consistent with all
other preedit-ending paths.

**Impact chain**: 02-state-and-types §3, design-resolutions-r8.md Resolution 10.

**Pre-existing**: no (Resolution 10 was created for r8)

---

### G1-04 | critical | Stale socket probe vs LaunchAgent socket activation

**Location**: `daemon-behavior/.../01-daemon-lifecycle.md` §1 startup constraint
#1 vs §5 LaunchAgent socket activation

**Description**: Startup constraint #1 probes the socket and exits if connection
succeeds. Under LaunchAgent socket activation, launchd pre-binds the socket
before the daemon starts. The probe would succeed (launchd is listening),
causing the daemon to exit. The inherited-fd detection (§1 edge case) runs AFTER
the probe, so it can't prevent the premature exit.

**Expected correction**: Startup constraint must check for inherited fd BEFORE
the stale socket probe, or the probe must be skipped when launched via
LaunchAgent.

**Impact chain**: 01-daemon-lifecycle §1, §5.

**Pre-existing**: yes

---

### G1-05 | minor | DestroySessionRequest in client state transition table

**Location**: `daemon-behavior/.../03-policies-and-procedures.md` §12

**Description**: Client state transition table omits `DestroySessionRequest`.
When a client destroys its own attached session, the r7 pseudocode explicitly
transitions the client to READY.

**Expected correction**: Add row:
`OPERATING | DestroySessionRequest (own
session) | READY | Session destroyed, client detached`.

**Impact chain**: 03-policies-and-procedures §12.

**Pre-existing**: yes

---

### G1-06 | critical | §1.1 invariant needs PreeditEnd exemption

**Location**: `daemon-behavior/.../02-event-handling.md` §1.1

**Description**: §1.1 states "the response MUST be sent before the
notifications." But §4.1 and §8.2 require PreeditEnd (broadcast) BEFORE the
response. PreeditEnd is a composition-resolution preamble (IME cleanup phase),
not a protocol notification — but §1.1 wording is too broad to distinguish.

**Expected correction**: Add exemption clause to §1.1 clarifying that PreeditEnd
is an IME composition-resolution step, not subject to the response-before-
notification rule. E.g., "PreeditEnd is a composition-resolution preamble that
precedes the response; it is not a notification in this rule's scope."

**Impact chain**: 02-event-handling §1.1, §4.1, §8.2.

**Pre-existing**: yes (r7 handled via separate phases in pseudocode, implicit)

---

### G1-07 | minor | NavigatePaneResponse missing from policies §8.1

**Location**: `daemon-behavior/.../03-policies-and-procedures.md` §8.1

**Description**: Focus change observable effects list only PreeditEnd and
LayoutChanged. Missing NavigatePaneResponse between them, which
`02-event-handling.md` §8.2 explicitly lists.

**Expected correction**: Add `NavigatePaneResponse — to requester` between
PreeditEnd and LayoutChanged in §8.1 observable effects.

**Impact chain**: 03-policies-and-procedures §8.1, 02-event-handling §8.2.

**Pre-existing**: no

---

### G1-09 | minor | MRU tie-break without supporting data structure

**Location**: `daemon-architecture/.../02-state-and-types.md` §2.2

**Description**: Navigation algorithm Step 4 specifies MRU tie-break ("prefer
the most recently focused pane") but no data structure tracks focus history.
Session has `focused_pane` (current) but no MRU list. `findPaneInDirection()`
takes no MRU parameter.

**Expected correction**: Either add an MRU tracking field to Session state
(§1.2), or replace the MRU tie-break with a deterministic alternative (e.g.,
lowest pane_id).

**Impact chain**: 02-state-and-types §1.2, §2.1, §2.2.

**Pre-existing**: no

---

## Dismissed Issues

| ID    | Dismiss Reason                                                                                                                                |
| ----- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| G1-01 | Misread context — §12 is Client State Transitions, not Design Decisions Log. Log was correctly dropped per Resolution 5.                      |
| G1-02 | Misread context — No `mousePress()` found in §8.8. Resolution 11 correction was applied.                                                      |
| G1-03 | Misread context — No pseudocode in §8. Resolution 1 format correctly applied.                                                                 |
| G1-08 | Wrong section reference — §8.4 is Pane Close, not InputMethodSwitch. §8.6 correctly has owner clear + session_id increment per Resolution 10. |
