# Verification Round 4 Issues

- **Round**: 4
- **Date**: 2026-03-07
- **Verifiers**: cross-reference-verifier, history-guardian, semantic-verifier, terminology-verifier

## Confirmed Issues

### V4-01 — Doc 03 Sections 1.6 and 1.14 missing MUST-ignore cross-reference for initial-attach frame_type=2

- **Severity**: minor
- **Source documents**: Protocol v0.8 `03-session-pane-management.md` Section 1.6 (line 200) and Section 1.14 (line 348); `04-input-and-renderstate.md` Section 7.3 (line 896)
- **Description**: Doc 03 Section 1.6 says "A full `FrameUpdate` (I-frame) for each visible pane" with no mention of the MUST-ignore rule. Section 1.14 says "the same post-attach sequence applies as for AttachSessionResponse: LayoutChanged, FrameUpdate (I-frame)..." — which chains back to Section 1.6, also without the rule. Doc 02 Sections 9.2 and 9.4 both have explicit cross-references to doc 04 Section 7.3 ("client MUST ignore the `frame_type=2` unchanged hint and process the frame as `frame_type=1`"), added by V3-01. A developer implementing either initial-attach path from doc 03 alone would not find the MUST-ignore rule.
- **Expected correction**: Add a cross-reference in doc 03 Sections 1.6 and 1.14 to doc 04 Section 7.3's MUST-ignore rule, consistent with the cross-references already present in doc 02 Sections 9.2 and 9.4.
- **Consensus note**: All 4 verifiers confirmed.

### V4-02 — Doc 04 Section 7.3 "no preedit changes" stale category inconsistent with V3-02 corrected Section 4.1

- **Severity**: minor
- **Source documents**: Protocol v0.8 `04-input-and-renderstate.md` Section 7.3 (line 898) and Section 4.1 (line 444)
- **Description**: Section 7.3 (informal explanatory text) states: "When `frame_type=2` fires: Only during true terminal idle — no cursor movement, **no preedit changes**, no mode changes, no color changes." Section 4.1 (normative rule, corrected by V3-02) lists: "If any field has changed — including cursor position, terminal modes, colors, or dimensions — the server MUST use `frame_type=1`." Section 4.1 deliberately omits "preedit state" (removed by V3-02). Section 7.3's informal text still names "preedit changes" as a distinct category, implying preedit is still tracked as a separate metadata quantity.
- **Expected correction**: Remove "no preedit changes" from the enumeration in Section 7.3, or replace with a reference to CellData changes, consistent with V3-02's correction in Section 4.1.
- **Consensus note**: All 4 verifiers confirmed. Independently identified by cross-reference-verifier and terminology-verifier.

## Dismissed Issues

None.
