# Protocol v0.5 Cross-Document Consistency Review

**Date**: 2026-03-05
**Consensus Reporter**: protocol-architect
**Reviewers**: protocol-architect, systems-engineer, cjk-specialist
**Scope**: All 6 docs in `server-client-protocols/draft/v1.0-r5/`

## Summary

**Total issues**: 20 (6 HIGH, 6 MEDIUM, 8 LOW)

All issues are documentation inconsistencies -- no structural protocol design flaws
were found. The protocol's core design (header format, message type taxonomy,
encoding strategy, lifecycle state machines) is internally consistent.

### Verified Consistent Items

The following areas were explicitly verified as consistent across all 6 docs:

- Message type numbers: no conflicts, all IDs unique within their ranges
- Preedit bypass: docs 04, 05, 06 all consistently describe preedit bypassing
  coalescing, PausePane, and power throttling
- `input_method` identifier: consistently uses canonical string throughout docs 02-05
- `active_` prefix convention: correctly applied (C->S bare names, S->C `active_` prefix)
- CellData struct: doc 05 correctly references doc 04, does not redefine
- Key event encoding: doc 05 correctly references doc 04 KeyEvent format
- Modifier bitmask: consistent between doc 04 (wire definition) and doc 05 (IME processing)
- Cross-reference accuracy: all "see doc X section Y" references checked point to existing
  sections (with exceptions noted as issues below)

---

## HIGH Severity

### Issue 1 -- Doc 01 registry missing message types from docs 03 and 06

**Affects**: doc 01 Section 3
**Authority**: docs 03, 06

Doc 01 message type registry is incomplete:

- Missing all pane response types: 0x0141, 0x0143, 0x0145, 0x0147, 0x0149, 0x014B,
  0x014D, 0x014F, 0x0151, 0x0153 (defined in doc 03)
- Missing `WindowResizeAck` (0x0191) (defined in doc 03 Section 3.4)
- No per-message rows for doc 06 ranges: 0x0500-0x05FF (Flow Control), 0x0600-0x06FF
  (Clipboard), 0x0700-0x07FF (Persistence), 0x0800-0x08FF (Notifications),
  0x0A00-0x0AFF (Extensions)

Note: session messages (0x0100-0x010D) include all request/response pairs, but pane
messages (0x0140-0x0152) list only request types. This asymmetry is confusing.

**Fix**: Add all missing message types. The doc 01 registry must be the single
exhaustive index of all protocol message types.

### Issue 2 -- ERR_PROTOCOL_ERROR referenced but undefined in doc 01

**Affects**: doc 01 (lines 227, 851)
**Authority**: doc 01 (should be self-consistent)

Doc 01 references `ERR_PROTOCOL_ERROR` for reserved COMPRESSED flag violations, but
Section 6.3 (error code table) does not define this error code. No numeric code is
assigned.

**Fix**: Add `ERR_PROTOCOL_ERROR` to doc 01 Section 6.3 with a specific error code value.

### Issue 3 -- Doc 04 references removed ERR_DECOMPRESSION_FAILED

**Affects**: doc 04 Section 9 (line 929)
**Authority**: doc 01

Doc 01 changelog explicitly states "ERR_DECOMPRESSION_FAILED removed" for v0.5.
However, doc 04 line 929 still says: "Receivers that encounter COMPRESSED=1 SHOULD
send `ERR_DECOMPRESSION_FAILED`."

Doc 01 already uses the correct replacement: `ERR_PROTOCOL_ERROR`.

**Fix**: Replace `ERR_DECOMPRESSION_FAILED` with `ERR_PROTOCOL_ERROR` in doc 04
Section 9.

### Issue 4 -- DetachSession field drift between docs 02 and 03

**Affects**: doc 02 Section 9.5
**Authority**: doc 03

Three sub-issues:

**4a. DetachSessionRequest extra fields**: Doc 02 adds a `reason` field with values
`"client_request"`, `"session_switch"`, `"client_shutdown"`. Doc 03 Section 1.7 has
only `session_id`. The `reason` field is extraneous -- the client does not need to
declare why it is detaching.

**4b. DetachSessionResponse schema mismatch**: Doc 02 has `session_id`,
`session_alive`, `reason`. Doc 03 has `status`, `reason`, `error`. The
`session_alive` field is redundant -- sessions always survive client detach (they
persist until explicitly destroyed or daemon exits).

**4c. Reason string terminology drift**: Doc 02 uses `"client_request"` while doc 03
uses `"client_requested"`. Doc 03's full reason enum: `"client_requested"`,
`"force_detached_by_other_client"`, `"session_destroyed"`, `"connection_lost"`.

**Fix**: Align doc 02 to doc 03:
1. Remove `reason` field from DetachSessionRequest
2. Adopt doc 03's `status`/`reason`/`error` schema for DetachSessionResponse
3. Use doc 03's exact reason string values
4. Drop `"session_switch"` and `"client_shutdown"` reasons entirely

### Issue 18 -- Doc 05 missing ko_vowel_only state transitions

**Affects**: doc 05 Sections 3.2 and 3.3
**Authority**: doc 05 (internal consistency)

The `ko_vowel_only` composition state is defined in Section 3.1 (line 246) as a valid
`composition_state` value, but it appears in neither the state transition diagram
(Section 3.2) nor the transition table (Section 3.3). No transitions into or out of
this state are specified. This is an incomplete state machine.

Cross-doc impact: if a client receives `composition_state: "ko_vowel_only"` in a
PreeditUpdate/FrameUpdate, there is no specification for what inputs cause transitions
into or out of this state.

**Fix**: Add `ko_vowel_only` transitions to both the state diagram and transition
table in doc 05.

### Issue 19 -- display_width missing from FrameUpdate preedit section

**Affects**: docs 04 and 05
**Authority**: needs resolution

Doc 04 Section 4.2 (lines 548-553) defines the FrameUpdate preedit JSON fields as:
`active`, `cursor_x`, `cursor_y`, `text`. There is no `display_width` field.

However, doc 05 Section 10.1 (line 824) says "use `display_width` from PreeditUpdate
for cell count" for overlay rendering.

This contradicts the rendering rule (doc 05 line 82): "Clients MUST use FrameUpdate's
preedit JSON for rendering, NOT PreeditUpdate's text field." The rendering path is
broken -- the client needs `display_width` for overlay sizing but FrameUpdate does not
carry it.

**Recommendation**: Add `display_width` (u8) to the FrameUpdate preedit section.
Rationale:
- The server already computes it (doc 05 Section 2.2, lines 156-160)
- 1 byte overhead -- negligible
- Makes FrameUpdate self-contained for rendering
- Eliminates client-side UAX #11 dependency for preedit rendering

**Fix**: Add `display_width` field to doc 04 FrameUpdate preedit section. Update doc 05
Section 10.1 to reference FrameUpdate's `display_width` instead of PreeditUpdate's.

---

## MEDIUM Severity

### Issue 5 -- pixel_width/pixel_height in doc 02 but not doc 03

**Affects**: doc 02
**Authority**: doc 03

Doc 02's CreateSessionRequest and AttachSessionRequest include `pixel_width` and
`pixel_height` fields that are absent from doc 03's versions of these messages.

Doc 03's WindowResize (Section 5.1) includes `pixel_width`/`pixel_height` as optional
fields. The design intent is that pixel dimensions are provided at resize time, not at
session creation/attach time.

Note: ClientHello (doc 02 Section 2.1) also has pixel fields for initial handshake
info -- those are separate and should stay.

**Fix**: Remove `pixel_width`/`pixel_height` from doc 02's CreateSessionRequest and
AttachSessionRequest. Pixel dimensions come via WindowResize.

### Issue 6 -- Dual ClientDisplayInfo definition (doc 02 vs doc 06)

**Affects**: docs 02 and 06
**Authority**: needs resolution

ClientDisplayInfo (0x0505) is defined in both doc 02 (handshake context) and doc 06
(flow control context). The schemas differ. Doc 06 is the runtime definition; doc 02
references it for initial capability exchange.

**Fix**: Designate doc 06 as authoritative for the payload schema (it is a flow
control message at 0x0505). Doc 02 should cross-reference doc 06 rather than redefine
the schema.

### Issue 7 -- ConnectionClosing references in doc 06 should be Disconnect

**Affects**: doc 06 (lines 984, 991)
**Authority**: doc 01

Doc 06 Section 7 changelog (line 1056) acknowledges the rename from
`ConnectionClosing` (0x0902) to `Disconnect` (0x0005), but two references remain:
- Line 984: "send ConnectionClosing with reason"
- Line 991: "Client may resend or ConnectionClosing"

**Fix**: Replace with `Disconnect` (0x0005) in both locations.

### Issue 8 -- Terminology drift: num_dirty_rows vs dirty_row_count

**Affects**: docs 04, 05, 06

Doc 04 (the FrameUpdate binary format authority) uses `num_dirty_rows` (lines 608,
611, 1007). Docs 05 and 06 use `dirty_row_count` throughout.

**Fix**: Standardize on `num_dirty_rows` (doc 04 is authoritative for the binary wire
format). Update docs 05 and 06.

### Issue 9 -- Dangling FrameAck reference in doc 02

**Affects**: doc 02
**Authority**: none (FrameAck does not exist)

Doc 02 references `FrameAck` but this message type is never defined in any document.
It appears to be a vestigial reference from an earlier protocol version.

**Fix**: Remove the `FrameAck` reference or replace with the correct message name.

### Issue 10 -- KeyInput vs KeyEvent naming in doc 02

**Affects**: doc 02
**Authority**: doc 04

Doc 02 uses `KeyInput` but the authoritative message name in doc 04 is `KeyEvent`
(0x0201).

**Fix**: Replace `KeyInput` with `KeyEvent` in doc 02.

---

## LOW Severity

### Issue 11 -- PreeditEnd reason CANCELLED in doc 02 vs doc 05

**Affects**: doc 02
**Authority**: doc 05

Doc 02 uses PreeditEnd reason `CANCELLED` in an example. Doc 05 Section 2.4 defines
the valid reasons; `"cancelled"` is not among them. The closest match is
`"replaced_by_other_client"`.

**Fix**: Align with doc 05's defined reason values.

### Issue 12 -- Readonly cross-references in docs 04/05 point to doc 02 instead of doc 03

**Affects**: docs 04, 05

Doc 04 line 334 says "see doc 02, AttachSessionRequest" and doc 05 line 84 says
"see doc 02" for readonly client behavior. While doc 02 defines the `readonly` flag
field, the authoritative readonly permissions table is in doc 03 Section 9.

**Fix**: Update cross-refs to "see doc 03 Section 9" (for permissions) or "see doc 02
for the flag, doc 03 Section 9 for permissions."

### Issue 13 -- Readonly permissions and heartbeat payload defined redundantly

**Affects**: docs 03, 04, 05 (readonly); docs 01, 02, 06 (heartbeat)
**Maintenance risk**

Readonly permissions are partially defined in:
1. Doc 03 Section 9 (authoritative)
2. Doc 04 Section 2.8
3. Doc 05 Section 1 line 84

Heartbeat payload is defined in:
1. Doc 01 Section 5.4 (authoritative)
2. Doc 02 (referenced)
3. Doc 06 Section 7 (redefined)

All instances are consistent today, but redundancy creates maintenance risk if the
definitions change.

**Fix**: Docs 04 and 05 should cross-reference doc 03 Section 9 as authoritative
rather than restating permissions inline. Doc 06 should cross-reference doc 01 for
heartbeat payload rather than redefining it.

### Issue 14 -- Heartbeat direction inconsistency in doc 01

**Affects**: doc 01 Section 5.4

The prose in Section 5.4 implies heartbeat is server-initiated only, but the message
type table marks Heartbeat (0x0003) / HeartbeatAck (0x0004) as bidirectional.

**Fix**: Clarify whether heartbeat is server-initiated-only or truly bidirectional, and
make prose and table consistent.

### Issue 15 -- Doc 05 state diagram uses non-canonical identifiers

**Affects**: doc 05 Section 3.2

The state diagram uses short identifiers (e.g., `2set`, `3f`) for Korean input method
variants rather than the canonical `input_method` names established by the identifier
consensus (`"korean_2set"`, `"korean_3set_final"`).

Additionally, the state diagram uses parenthetical hex codes `(0x00)-(0x03)` for
composition states. Since `composition_state` is a string on the wire (settled
decision), these numeric codes are misleading.

**Fix**: Use canonical `input_method` strings and remove or relabel the hex codes as
"informational internal identifiers."

### Issue 16 -- PaneMetadataChanged overlap with opt-in notifications undocumented

**Affects**: docs 03, 06

PaneMetadataChanged (0x0181, doc 03) is always-sent, while doc 06 defines opt-in
notification subscriptions (0x0800-0x0806 range). The relationship between always-sent
notifications and opt-in notifications is not explicitly documented.

**Fix**: Add a brief note in either doc 03 or doc 06 clarifying the distinction between
always-sent notifications (0x0180-0x0184) and opt-in notifications (0x0800+).

### Issue 17 -- Doc 02 preedit_sync description is ambiguous

**Affects**: doc 02 Section 5

Doc 02 lines 392-394 describe `preedit_sync` (bit 3) as "broadcasts preedit state
changes to all attached clients via PreeditSync (0x0403)." This wording could be
misread as gating PreeditStart/Update/End broadcasts.

Per doc 05, the actual semantic is narrower: `preedit_sync` gates only PreeditSync
(0x0403) -- the full state snapshot sent to late-joining clients.
PreeditStart/Update/End (0x0400-0x0402) are gated by `preedit` (bit 0) alone.

**Fix**: Tighten doc 02 description to: "The server sends PreeditSync (0x0403)
full-state snapshots to clients that attach to a pane with an active composition
session."

### Issue 20 -- "4-tier" vs "5-state" coalescing terminology

**Affects**: docs 01, 04, 05, 06

The adaptive coalescing model is called "4-tier" throughout (doc 01 line 759, doc 04
line 921, doc 05 line 703, doc 06 line 51), but the tier table in doc 06 Section 1.1
lists 5 rows (Preedit, Interactive, Active, Bulk, Idle). Doc 06's own changelog
(line 1045) says "5-state" in parentheses while the heading says "4-tier."

The inconsistency is whether Idle counts as a "tier" (it produces no frames, so
arguably is not an active coalescing tier).

**Fix**: Either rename to "5-tier" or add a note explaining Idle is a state (not a
tier) and update the changelog to match.

---

## Issues by Document

| Doc | Owner | Issues | IDs |
|-----|-------|--------|-----|
| 01 (Protocol Overview) | protocol-architect | 5 | 1, 2, 3*, 14, 20* |
| 02 (Handshake) | protocol-architect | 7 | 4, 5, 6*, 9, 10, 11, 17 |
| 03 (Session/Pane) | systems-engineer | 1 | 16* |
| 04 (Input/RenderState) | cjk-specialist | 4 | 3, 8*, 12, 19* |
| 05 (CJK Preedit) | cjk-specialist | 5 | 8*, 12, 15, 18, 19* |
| 06 (Flow Control) | systems-engineer | 4 | 6*, 7, 8*, 16*, 20* |

(*) Issue spans multiple docs

## Issues by Severity

| Severity | Count | IDs |
|----------|-------|-----|
| HIGH | 6 | 1, 2, 3, 4, 18, 19 |
| MEDIUM | 6 | 5, 6, 7, 8, 9, 10 |
| LOW | 8 | 11, 12, 13, 14, 15, 16, 17, 20 |

## Action Items by Owner

### protocol-architect (docs 01, 02)

1. Add all missing message types to doc 01 registry (Issue 1)
2. Add ERR_PROTOCOL_ERROR to doc 01 error code table (Issue 2)
3. Remove DetachSessionRequest `reason` field from doc 02 (Issue 4a)
4. Adopt doc 03 DetachSessionResponse schema in doc 02 (Issue 4b)
5. Fix reason string values in doc 02 (Issue 4c)
6. Remove pixel fields from doc 02 CreateSession/AttachSession (Issue 5)
7. Cross-reference doc 06 for ClientDisplayInfo in doc 02 (Issue 6)
8. Remove dangling FrameAck reference in doc 02 (Issue 9)
9. Replace KeyInput with KeyEvent in doc 02 (Issue 10)
10. Fix PreeditEnd reason in doc 02 example (Issue 11)
11. Clarify heartbeat direction in doc 01 (Issue 14)
12. Tighten preedit_sync description in doc 02 (Issue 17)

### systems-engineer (docs 03, 06)

1. Replace ConnectionClosing with Disconnect in doc 06 (Issue 7)
2. Standardize dirty_row_count to num_dirty_rows in doc 06 (Issue 8)
3. Add always-sent vs opt-in notification note in doc 03 or 06 (Issue 16)
4. Fix "4-tier" terminology in doc 06 (Issue 20)

### cjk-specialist (docs 04, 05)

1. Replace ERR_DECOMPRESSION_FAILED in doc 04 (Issue 3)
2. Standardize dirty_row_count to num_dirty_rows in doc 05 (Issue 8)
3. Update readonly cross-references in docs 04, 05 (Issue 12)
4. Reduce redundant readonly permissions to cross-refs in docs 04, 05 (Issue 13)
5. Fix state diagram identifiers in doc 05 (Issue 15)
6. Add ko_vowel_only transitions in doc 05 (Issue 18)
7. Add display_width to doc 04 FrameUpdate preedit section (Issue 19)
8. Fix "4-tier" terminology in docs 04, 05 (Issue 20)
