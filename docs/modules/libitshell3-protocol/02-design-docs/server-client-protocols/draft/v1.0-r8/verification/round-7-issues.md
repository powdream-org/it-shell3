# Verification Round 7 Issues

- **Round**: 7
- **Date**: 2026-03-07
- **Verifiers**: cross-reference-verifier, history-guardian, semantic-verifier, terminology-verifier

## Confirmed Issues

### V7-01 — Doc 01 Section 9.1 stale binary frame header size and component descriptions

- **Severity**: minor
- **Source documents**: Protocol v0.8 `01-protocol-overview.md` Section 9.1 (lines 851–859); `04-input-and-renderstate.md` Section 4.1 (lines 462–468) and Section 4.3 (lines 606–623)
- **Description**: Doc 01 Section 9.1 ("FrameUpdate Size Estimates") contains three factual errors relative to the authoritative wire format in doc 04:
  1. "Binary frame header | 8 B" — doc 04 Section 4.1 specifies 20 bytes (session_id=4 + pane_id=4 + frame_sequence=8 + frame_type=1 + screen=1 + section_flags=2).
  2. "Pane ID, frame_type, screen, row/col counts" — doc 04's binary header has session_id, pane_id, frame_sequence, frame_type, screen, section_flags; "row/col counts" do not appear in the binary header (dimensions are in the JSON metadata blob per doc 04 Section 4.2).
  3. "DirtyRows bitmap | 4 B | 24 rows = 3 bytes, padded to 4" — doc 04 Section 4.3 uses `num_dirty_rows` (u16, 2 bytes) followed by variable-length RowData entries, not a fixed-size bitmap.
- **Expected correction**: Update doc 01 Section 9.1 to reflect the actual binary frame header size (20 bytes), correct component names (session_id, pane_id, frame_sequence, frame_type, screen, section_flags), and replace "DirtyRows bitmap" with the actual count+list encoding from doc 04 Section 4.3.
- **Consensus note**: All 4 verifiers confirmed.

## Dismissed Issues

| Issue | Reason for dismissal |
|-------|---------------------|
| R7-T01 ("P-partial" vs "P-frame, partial" naming inconsistency in doc 04 line 489, doc 01 line 1009) | No unanimous consensus. cross-reference-verifier dismissed as abbreviation variance (parenthetical shorthand in code blocks and summary tables, not a canonical name conflict). 3 confirmed, 1 dismissed. |
