# Verification Round 2 Issues

- **Round**: 2
- **Date**: 2026-03-07
- **Verifiers**: cross-reference-verifier, history-guardian, semantic-verifier, terminology-verifier

## Confirmed Issues

### V2-01 — Doc 01 not updated for v0.8: 12+ stale normative locations

- **Severity**: critical
- **Source documents**: Protocol v0.8 `01-protocol-overview.md`
- **Description**: Doc 01 was never updated for v0.8. Its version header reads "Draft v0.7" (line 3) and its changelog has no v0.8 entry. The document contains at least 12 stale normative body-text statements (not changelog entries) that directly contradict v0.8 resolutions:
  1. Line 24: "JSON metadata blob for cursor, **preedit**, colors, and dimensions" — contradicts Resolution 2
  2. Line 164: Same text in encoding convention table — contradicts Resolution 2
  3. Line 277: FrameUpdate (0x0300) entry "(includes **preedit section**)" — contradicts Resolution 2
  4. Line 394: Hybrid encoding table row "Cursor, **Preedit**, Colors, Dimensions | JSON blob" — contradicts Resolution 2
  5. Line 403: PreeditUpdate described as "Server pushes current **composition state**" — contradicts Resolution 1
  6. Lines 411-415: Full "**Preedit dual-channel design**" normative block with "Clients MUST use FrameUpdate's preedit section for rendering" — contradicts Resolution 3
  7. Line 683: Stale health table row "None (**except preedit bypass**)" — contradicts Resolution 7
  8. Line 713: Full "**Preedit bypass**" paragraph describing per-client latest-wins priority buffer — contradicts Resolution 7
  9. Line 863: Bandwidth estimate includes "**preedit overlay**" in JSON metadata — contradicts Resolution 2
  10. Line 900: Coalescing tier table Preedit row "**Bypasses all coalescing**" — contradicts Resolution 7
  11. Line 919: "**Preedit bypasses everything**" paragraph — contradicts Resolution 7
  12. Line 1013: Design decisions table "backward wire-compatible (**frame_type values 1/2 match old dirty values 1/2**)" — factually false after Resolution 8 renumbering from 4 values to 3
- **Root cause**: The resolution document's "Spec Documents Requiring Changes" table omitted doc 01 and doc 03.
- **Expected correction**: Update doc 01 to v0.8. Add v0.8 changelog entry. Remove or update all 12+ stale locations to reflect the v0.8 architecture: preedit is cell data in I/P-frames, no JSON metadata preedit section, no bypass path, no dual-channel design, frame_type renumbered to 3 values {0=P-partial, 1=I-frame, 2=I-unchanged}.
- **Consensus note**: All 4 verifiers confirmed.

### V2-02 — Doc 03 not updated for v0.8: 2 stale preedit bypass references

- **Severity**: critical
- **Source documents**: Protocol v0.8 `03-session-pane-management.md`
- **Description**: Doc 03 was never updated for v0.8. Its version header reads "Version: v0.7" (line 3) and its changelog ends at v0.7. Two normative body-text statements reference "preedit bypass frames" — eliminated by Resolution 7:
  - Line 947 (Section 5.4 resize debounce algorithm, step 6): "Preedit bypass frames are still sent." — contradicts doc 06 Section 2.3 ("All frames go through the ring — there are no bypass paths")
  - Line 1062 (Section 8 Client Health): "stop receiving grid frames (but **continue receiving preedit bypass frames**)" — contradicts doc 06 Section 2.8 (stale clients receive "None (ring cursor stagnant)")
- **Root cause**: Same as V2-01 — doc 03 omitted from resolution's writing scope.
- **Expected correction**: Update doc 03 to v0.8. Add v0.8 changelog entry. Remove "preedit bypass frames" references at lines 947 and 1062.
- **Consensus note**: All 4 verifiers confirmed.

### V2-03 — IME contract responsibility matrix stale "preedit overlay" description

- **Severity**: minor
- **Source documents**: IME Contract v0.7 `01-overview.md` line 162 (Section 4 responsibility matrix)
- **Description**: The row "Rendering preedit overlay on screen" states "Client receives preedit from server, renders via Metal." Under v0.8, preedit is cell data rendered uniformly — the client has no concept of which cells are preedit (protocol doc 05 Section 10.1: "The client renders all cells uniformly — it has no concept of which cells are preedit and which are terminal content"). The phrase "preedit overlay" implies a distinct client-side rendering pass, and "receives preedit from server" implies preedit as a distinct data type — both are stale v0.7 concepts. The high-level ownership (client owns rendering) remains correct; only the mechanism description is wrong.
- **Expected correction**: Update the responsibility description to reflect the v0.8 model, e.g., "Client renders cell data (which includes preedit cells injected server-side via `ghostty_surface_preedit()`) via Metal."
- **Consensus note**: All 4 verifiers confirmed.

## Dismissed Issues

| Issue | Reason for dismissal |
|-------|---------------------|
| R2-C (IME contract Section 9 "preedit not saved" vs protocol doc 05 commit-on-restore) | No unanimous consensus reached. Verifier positions shifted repeatedly during cross-validation. Not confirmed per unanimous consensus rule. |
| R2-TERM-04 (snapshot `session_id` vs wire `preedit_session_id` naming) | Intentional abbreviated naming convention. Resolution document Section 13 "After" snapshot uses `session_id` inside nested `preedit` object — same as doc 05 Section 9.1. Wire messages use prefixed `preedit_session_id` for flat JSON disambiguation. |
| V2-03-meta (resolution traceability gap as standalone issue) | Not a standalone document content issue. Folded into V2-01 and V2-02 descriptions as root cause explanation. |
