# Verification Round 2 Issues

**Round**: 2
**Date**: 2026-03-08
**Verifiers**: cross-ref-v2, history-v2, term-v2, semantic-v2
**Consensus**: 4/4 unanimous on all issues
**Round 1 fixes**: All 5 verified correct

---

## Confirmed Issues

### V2-01 — critical

**Source documents**: Doc 04 §4.1 "Normative — Minimum rendering dimensions"

**Description**: The V1-02 fix introduced a reference to `PaneExited` message, which does not exist in the protocol. The text reads: "the client knows the pane exists from CreatePane and receives `PaneExited` when it terminates." No message named `PaneExited` appears in any message type registry. The actual termination signals are `ProcessExited` (0x0801) and `LayoutChanged` (0x0180).

**Expected correction**: Replace `PaneExited` with the correct existing message name(s). Either reference `ProcessExited` (doc 06 §5.2) or remove the specific message name and refer generically to the session/pane management protocol.

**Consensus note**: All 4 verifiers confirmed. Phantom message name, not defined anywhere.

---

### V2-02 — critical

**Source documents**: Doc 01 §9.3 vs. Doc 04 §8.1

**Description**: Doc 01 §9.3 I-Frame Bandwidth Overhead table still shows `120x40 (large CJK) | ~116 KB`. After Resolution 1 (16-byte CellData), the correct value is ~82 KB (per doc 04 §8.1). The derived bandwidth figures (~116 KB/s, ~464 KB/s) are also stale.

**Expected correction**: Update to `~82 KB | ~82 KB/s | ~328 KB/s`.

**Consensus note**: All 4 verifiers confirmed. Same root cause as V1-05 (not fully propagated).

---

### V2-03 — critical

**Source documents**: Doc 06 §2.1 ring buffer sizing vs. Doc 04 §8.1

**Description**: Doc 06 §2.1 sizing analysis uses `1 I-frame | ~116 KB` and derived `Minimum ring (2 I-frames) | ~232 KB`. These are stale 20-byte values. Correct: ~82 KB per I-frame, ~164 KB minimum ring.

**Expected correction**: Update all ~116 KB references in doc 06 §2.1 to ~82 KB and recalculate derived values.

**Consensus note**: All 4 verifiers confirmed.

---

### V2-04 — minor

**Source documents**: Doc 04 Appendix A hex dump

**Description**: GraphemeTable is shown at offset 0x005F and UnderlineColorTable at 0x0061, but 5 cells × 16 bytes = 80 bytes from 0x002F gives 0x007F. The offsets are 32 bytes too early.

**Expected correction**: GraphemeTable at 0x007F, UnderlineColorTable at 0x0081. Also update JSON Metadata Blob offset accordingly.

**Consensus note**: All 4 verifiers confirmed. Arithmetic error.
