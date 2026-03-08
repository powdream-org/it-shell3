# Verification Round 1 Issues

**Round**: 1
**Date**: 2026-03-08
**Verifiers**: cross-reference-verifier, history-guardian, semantic-verifier, terminology-verifier
**Consensus**: 4/4 unanimous on all issues

---

## Confirmed Issues

### V1-01 — critical

**Source documents**: Doc 04 §4.3 (RowData wire format table) vs. §7.1/§7.2 (size estimates) vs. Appendix A (hex dump)

**Description**: RowData header size is internally inconsistent across three sources within doc 04. §4.3 defines `selection_start` and `selection_end` as conditional ("if row_flags bit 0"), yielding either 5 bytes (no selection) or 9 bytes (with selection). §7.1 and §7.2 both state "7 header bytes" in size calculations (e.g., "per row: 7 header + 80*16 cells + 4 side tables = 1,291"). Appendix A hex dump always emits `selection_start` and `selection_end` at fixed offsets even when `row_flags=0x00`, implying a fixed 9-byte header. No combination of the defined fields produces 7 bytes. The three sources are irreconcilable.

**Expected correction**: Decide whether selection fields are conditional or always-present. Update §4.3 wire table, §7.1/§7.2 size calculations, and Appendix A to be consistent. The Appendix A approach (always-present, fixed 9-byte header) is the simplest wire format.

**Consensus note**: All 4 verifiers confirmed. The arithmetic inconsistency is verifiable: y(2) + row_flags(1) + num_cells(2) = 5; with selection: + 4 = 9. Neither produces 7.

---

### V1-02 — critical

**Source documents**: Doc 04 §4.1 "Normative — Minimum rendering dimensions" (Resolution 4) vs. §4.1 "Normative — `frame_type=2` unchanged rule" vs. §7.3

**Description**: The minimum dimensions normative instructs the server to SHOULD send `frame_type=2` (I-unchanged) when suppressing FrameUpdate for undersized panes, to maintain pane liveness. But `frame_type=2` requires the entire payload to be byte-identical to the most recent I-frame. A pane created at undersized dimensions from the start has no prior I-frame — the server cannot produce a byte-identical copy of something that does not exist. Additionally, §7.3 requires seeking clients to process `frame_type=2` as `frame_type=1`, which would cause rendering of CellData for an undersized terminal — the exact crash Resolution 4 prevents. The two normatives in the same section are logically incompatible in this edge case.

**Expected correction**: Change the liveness mechanism. Options: (a) remove `frame_type=2` from the minimum dimensions normative entirely — pane liveness is maintained through session/pane management (doc 03), not FrameUpdate; (b) specify that the server MUST send at least one valid I-frame before switching to suppression; (c) use a different signal for pane liveness (e.g., a pane-level heartbeat).

**Consensus note**: All 4 verifiers confirmed. The logical incompatibility is clear: `frame_type=2` presupposes an existing I-frame; the undersized-pane-from-creation scenario violates this presupposition.

---

### V1-03 — minor

**Source documents**: Doc 04 §4.3 ("if row_flags bit 0" annotation) vs. Appendix A (always-present at fixed offsets)

**Description**: §4.3 annotates `selection_start` and `selection_end` with "if row_flags bit 0", implying conditional wire presence (variable-length header). Appendix A shows these fields always present at fixed offsets with "(ignored)" annotation when bit 0 = 0. These two representations prescribe incompatible parsing strategies. This is the root cause of V1-01's arithmetic inconsistency.

**Expected correction**: Resolve as part of V1-01. If always-present (recommended), remove "if row_flags bit 0" from §4.3 wire format table and change to "(meaningful if row_flags bit 0)" or similar.

**Consensus note**: All 4 verifiers confirmed. Related to V1-01 but a distinct structural ambiguity about the wire format contract.

---

### V1-04 — critical

**Source documents**: Doc 01 §9.1 vs. Doc 04 §4.3

**Description**: Doc 01 §9.1 FrameUpdate Size Estimates still uses the field name `selection_flags` and states "y + selection_flags + num_cells = 5 B each". Resolution 3 renamed this field to `row_flags` in doc 04 §4.3. Doc 01 was not updated. The byte count (5 B) is also wrong per V1-01.

**Expected correction**: Update doc 01 §9.1 to use `row_flags` and the correct header byte count (matching the resolution of V1-01).

**Consensus note**: All 4 verifiers confirmed independently (cross-reference-verifier, terminology-verifier found this; semantic-verifier and history-guardian confirmed).

---

### V1-05 — critical

**Source documents**: Doc 01 §9.1 vs. Doc 04 §4.4 and §7.2

**Description**: Doc 01 §9.1 states "~20 bytes/cell" and "~38 KB" for a full 80x24 I-frame. Resolution 1 changed CellData to 16-byte fixed format; doc 04 §7.2 now computes ~32,722 bytes (~33 KB). Doc 01 was not updated.

**Expected correction**: Update doc 01 §9.1 to use 16 bytes/cell, ~33 KB total, and update all downstream arithmetic in the table.

**Consensus note**: All 4 verifiers confirmed independently (cross-reference-verifier, terminology-verifier found this; semantic-verifier and history-guardian confirmed).

---

## Dismissed Issues

- **Cross-reference-verifier Issue #6** (doc 01 §9.1 arithmetic ~122 B): Consolidated into V1-04 — same table row, same root cause. Not a separate alarm.
