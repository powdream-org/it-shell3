# Verification Round 1 Issues

**Round**: 1
**Date**: 2026-03-06
**Verifiers**: semantic-verifier, terminology-verifier, cross-reference-verifier
**Consensus**: All issues below were unanimously confirmed (3/3) during cross-validation (step 3.7).

---

## Confirmed Issues

### V1-01: PreeditEnd `reason` conflict for `commit_current=false` on InputMethodSwitch

**Severity**: critical
**Source documents**: Doc 05 — Section 2.3 (line 227), Section 4.1 (line 466), Section 7.9 (line 748)
**Description**: Sections 2.3 and 4.1 say `commit_current=false` on InputMethodSwitch produces `reason="cancelled"`. Section 7.9 says InputMethodSwitch always produces `reason="input_method_changed"` regardless of `commit_current` value. An implementer cannot satisfy both — these are contradictory normative statements within the same document.
**Expected correction**: Design decision required — either Section 7.9 must differentiate by `commit_current` value (using `"cancelled"` when `commit_current=false`), or Sections 2.3 and 4.1 must use `"input_method_changed"` for the `commit_current=false` case. All three sections must agree.
**Consensus note**: All three verifiers independently identified the conflict. Sections 2.3/4.1 agree with each other but contradict Section 7.9. The intent is ambiguous — needs an explicit design decision.

**Owner decision (binding)**: Sections 2.3 and 4.1 are correct. The `reason` value depends on `commit_current`:
- `commit_current=true` → `reason="committed"` (preedit text is committed before switch)
- `commit_current=false` → `reason="cancelled"` (preedit is discarded)

Section 7.9 must be updated to differentiate by `commit_current` value instead of unconditionally using `"input_method_changed"`. If `"input_method_changed"` has no remaining use case after this fix, remove it entirely from the reason value catalog in Section 2.3.

### V1-02: `frame_sequence` scope — resolution doc summary table inaccuracy

**Severity**: minor
**Source documents**: Design-resolutions `01-i-p-frame-ring-buffer.md` — Wire Protocol Changes Summary table (line 374) vs Resolution 19 body (line 320)
**Description**: The summary table says `frame_sequence` is "incremented only for grid-state frames (section_flags bit 4 set)." Resolution 19 body and doc 04 normative note (line 473) both say ALL ring frames — including `frame_type=0` cursor-only entries (which do NOT have section_flags bit 4 set) — increment `frame_sequence`. The summary table's shorthand incorrectly excludes `frame_type=0` ring entries.
**Expected correction**: Change the summary table entry to "incremented for all frames written to the ring buffer" or enumerate all four `frame_type` values explicitly. Spec documents (doc 04) are already correct — only the resolution doc's summary table needs fixing.
**Consensus note**: Raised independently by both semantic-verifier and cross-reference-verifier. The normative spec text is correct; only the resolution doc's non-normative summary table is wrong.

### V1-03: PreeditSync `preedit_session_id` description ambiguity

**Severity**: minor
**Source documents**: Doc 05 — PreeditSync field table (line 260)
**Description**: `preedit_session_id` is described as "Current session ID." The term "session ID" is heavily overloaded in this protocol — `session_id` (u32) refers to the terminal session. The `preedit_session_id` is a different concept (monotonic composition counter per pane). Other occurrences in the same document (PreeditStart line 158, PreeditUpdate, PreeditEnd) use clearer descriptions like "Unique ID for this composition session" or "Matches PreeditStart."
**Expected correction**: Change the PreeditSync field description to "Current preedit composition session ID (matches PreeditStart)."
**Consensus note**: All three verifiers agreed the ambiguity is real, though low severity since the field name itself includes the "preedit_" prefix and surrounding context clarifies the meaning.

### V1-04: Doc 06 v0.5 changelog stale "per-pane" IME reference

**Severity**: minor
**Source documents**: Doc 06 — v0.5 changelog entry (line 1258) vs Section 4.4 body text (lines 726-732)
**Description**: The v0.5 changelog entry says "per-pane ImeEngine" and "persist `input_method` per pane." The body text (Section 4.4) has been correctly updated to "per-session IME engine" and "at session level." The changelog entry is stale from before the v0.7 per-session change and contradicts the current normative body text.
**Expected correction**: Update the v0.5 changelog entry to reflect the current per-session model, or annotate it with "(superseded by v0.7 per-session model)."
**Consensus note**: All three verifiers confirmed. The changelog is historical but could mislead readers since it contradicts the current body text.

---

## Dismissed Issues

### Issue C: Doc 02 "doc 01 Section 7" cross-reference for `active_` prefix convention
**Dismissed**: The `active_` prefix convention IS defined in doc 01 Section 7 (line 803, "Field name direction convention" table row). The cross-reference is valid. Initially raised by terminology-verifier who missed the table row; withdrawn after cross-reference-verifier pointed it out.

### Issue F: Reserved range table detail level (doc 01 vs doc 06 Section 9)
**Dismissed**: Doc 01 gives high-level "Reserved for future use" summary; doc 06 Section 9 provides provisional sub-range assignments. These are compatible — normal multi-document spec layering, not a contradiction.
