# Verification Round 3 Issues

- **Round**: 3
- **Date**: 2026-03-07
- **Verifiers**: cross-reference-verifier, history-guardian, semantic-verifier, terminology-verifier

## Confirmed Issues

### V3-01 — Doc 02 initial attach uses frame_type=2 without cross-referencing doc 04 MUST-ignore rule

- **Severity**: critical
- **Source documents**: Protocol v0.8 `02-handshake-capability-negotiation.md` Sections 9.2 (line 719) and 9.4 (line 779); `04-input-and-renderstate.md` Section 7.3
- **Description**: Doc 02 Sections 9.2 and 9.4 specify that the server sends a `frame_type=2` (I-frame, unchanged) to a newly attaching client as the initial frame. `frame_type=2` semantically means "byte-identical to the previous I-frame" — but a fresh-attaching client has no prior I-frame. Doc 04 Section 7.3 has a MUST-ignore rule covering exactly this scenario: "A client that arrived at this frame by seeking (ring buffer skip, ContinuePane recovery, **initial attach**) MUST ignore the unchanged hint and process the frame as `frame_type=1`." Doc 02 never cross-references this rule. A reader implementing initial attach from doc 02 alone receives incomplete behavioral specification.
- **Expected correction**: Add a cross-reference in doc 02 Sections 9.2 and 9.4 to doc 04 Section 7.3's MUST-ignore rule, noting that attaching clients must process the frame as frame_type=1 regardless of the frame_type=2 hint.
- **Consensus note**: All 4 verifiers confirmed.

### V3-02 — Doc 04 frame_type=2 unchanged rule lists "preedit state" as a change condition

- **Severity**: minor
- **Source documents**: Protocol v0.8 `04-input-and-renderstate.md` Section 4.1 (line 444) and Section 4.2 (line 557)
- **Description**: The frame_type=2 unchanged rule states: "If any field has changed — including cursor position, **preedit state**, terminal modes, colors, or dimensions — the server MUST use `frame_type=1`." Every other item in this list corresponds to a concrete field in the JSON metadata blob (Section 4.2). "Preedit state" does not — it was removed from FrameUpdate by Resolution 2. Section 4.2 explicitly states: "Note — No preedit section in JSON metadata." The phrase "preedit state" in the unchanged rule is a stale residual.
- **Expected correction**: Remove "preedit state" from the enumeration in the frame_type=2 unchanged rule, or replace with a reference to CellData changes (which already subsume preedit cell changes).
- **Consensus note**: All 4 verifiers confirmed.

## Dismissed Issues

| Issue | Reason for dismissal |
|-------|---------------------|
| R3-SEM-B (doc 05 Section 2.2 vs Section 7.5 PreeditUpdate frequency) | Complementary, not contradictory. Section 7.5 is a coalescing optimization for burst input that suppresses intermediate states within the same frame interval. |
| R3-SEM-C (doc 05 Section 7.2 30-second preedit timeout vs doc 06 health model) | Independent timeout mechanisms for orthogonal failure modes. Doc 06 fires on ring buffer lag; doc 05 fires on preedit owner input silence. |
| R3-02 (doc 05 bare `keyboard_layout` vs `active_keyboard_layout`) | Intentional naming convention. Bare name = session property; prefixed = wire field. |
| R3-03 (doc 06 tier name casing) | Section 5.4 normatively defines lowercase wire strings. Section 1.1 uses title-case display labels. |
| R3-04 (doc 04 "P-frame, partial" vs "P-partial") | Expanded form in formal table, abbreviated in prose. Standard documentation practice. |
