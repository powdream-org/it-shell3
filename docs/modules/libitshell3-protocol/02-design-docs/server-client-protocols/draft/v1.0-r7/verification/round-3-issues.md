# Verification Round 3 Issues

## Round Metadata

- **Round**: 3
- **Date**: 2026-03-06
- **Verifiers**: semantic-verifier (sonnet), terminology-verifier (sonnet), cross-reference-verifier (sonnet), history-guardian (opus)

## Issue List

### V3-01 — Scroll-response I-frame `frame_sequence` ambiguity

| Field | Value |
|-------|-------|
| Issue ID | V3-01 |
| Severity | minor |
| Source document(s) | Doc 04 Section 6.1 and Section 7.3 vs. Resolution 19, Doc 04 Section 4.1 normative note |
| Description | Doc 04 §6.1 routes scroll-response I-frames through the direct queue (bypassing the ring). Resolution 19 and the §4.1 normative note define `frame_sequence` as ring-only. §7.3 says "the client records this frame's `frame_sequence` as the current I-frame reference." The spec is silent on what `frame_sequence` value a direct-queue I-frame carries and how the client handles it. |
| Expected correction | §6.1 or §7.3 should specify whether scroll-response I-frames carry a `frame_sequence` value and how client I-frame reference tracking applies. |
| Consensus note | All 4 verifiers unanimously confirmed. Design gap introduced by the V2-04 fix (scroll I-frame via direct queue). |
| **Owner decision** | **V2-04 fix was fundamentally wrong.** The entire design is globally singleton — all clients share the same viewport state. Per-client independent scroll positions contradict this principle. Scroll-response I-frames go through the ring buffer like any other I-frame, receiving a normal `frame_sequence`. **Action: revert V2-04 text (remove "direct message queue" language from Doc 04 §6.1). V3-01 is resolved automatically once scroll I-frames use the ring.** |

### V3-02 — Contradictory PreeditEnd reasons for `commit_current=false` InputMethodSwitch

| Field | Value |
|-------|-------|
| Issue ID | V3-02 |
| Severity | minor |
| Source document(s) | Doc 05 Section 4.1 server behavior steps 2 and 3 |
| Description | §4.1 for `InputMethodSwitch` with `commit_current=false` gives two contradictory PreeditEnd reasons in the same server behavior list: step 2 says `reason="cancelled"`, step 3 says `reason="input_method_changed"` unconditionally. These are two different reason values for the same code path. |
| Expected correction | One consistent PreeditEnd reason for the `commit_current=false` path. |
| Consensus note | All 4 verifiers unanimously confirmed. |
| **Owner decision** | **Use `"cancelled"` for `commit_current=false` path.** The `"input_method_changed"` reason carries no distinct semantic from the client's perspective. Remove `"input_method_changed"` as a PreeditEnd reason constant entirely — it no longer exists in the protocol. |

### V3-03 — Resolution 19 ToC title mismatch

| Field | Value |
|-------|-------|
| Issue ID | V3-03 |
| Severity | minor |
| Source document(s) | `design-resolutions/01-i-p-frame-ring-buffer.md` ToC line 36 vs. heading line 314 |
| Description | ToC entry reads "Resolution 19: frame_sequence incremented only for grid-state frames." The section heading reads "Resolution 19: frame_sequence tracks ring frames only." Textually inconsistent, and "grid-state frames" is substantively narrower than "ring frames" (would exclude cursor-only frames in the ring). |
| Expected correction | ToC entry should match heading: "Resolution 19: frame_sequence tracks ring frames only." |
| Consensus note | All 4 verifiers unanimously confirmed. Pre-existing issue noted in Round 1 by protocol-architect. |

### V3-04 — Resolution doc "Spec Documents Requiring Changes" table missing Doc 05

| Field | Value |
|-------|-------|
| Issue ID | V3-04 |
| Severity | minor |
| Source document(s) | `design-resolutions/01-i-p-frame-ring-buffer.md` "Spec Documents Requiring Changes" table (lines 396-403) |
| Description | Table lists only Doc 01, 03, 04, 06. Doc 05 is absent despite having I/P-frame-driven changes: `dirty=full` → `frame_type=2` in §7.3/§7.4 (Resolutions 3-4), preedit bypass model references in §8.2/§8.4 (Resolutions 17-19), and dedicated preedit messages note in §14 (Resolution 20). |
| Expected correction | Add Doc 05 entry to the table describing these changes. |
| Consensus note | All 4 verifiers unanimously confirmed. Downgraded from critical to minor — omission in resolution doc summary table, no impact on spec docs themselves. |

## Dismissed Issues Summary

| Issue | Reason for Dismissal |
|-------|---------------------|
| SV3-3: ContinuePane recovery missing LayoutChanged | Dismissed unanimously. PausePane does not suppress the direct message queue. LayoutChanged is enqueued and delivered during the pause window. No catch-up needed on ContinuePane. |
| CR3-2: Doc 05 changelog reference to "design-resolutions-resize-health.md Addendum B" | Dismissed unanimously. The file exists at `v0.6/design-resolutions-resize-health.md` and Addendum B is present at lines 360-366. The reference is version-unqualified but the target exists and is correct. |

## Verification Termination

**Decision**: Owner terminated the verification loop after Round 3.

**Reason**: V3-01 and V3-02 are design-level issues requiring architectural decisions, not text fixes amenable to the 3.4→3.5 fix loop. V3-01 traces back to a fundamentally wrong premise in V2-04 (per-client scroll in a globally singleton design). V3-02 requires removing a protocol constant (`"input_method_changed"`).

**Disposition**: All 4 confirmed issues (V3-01 through V3-04) are deferred to the Review Cycle for review note creation and resolution in the next revision cycle (v0.8).
