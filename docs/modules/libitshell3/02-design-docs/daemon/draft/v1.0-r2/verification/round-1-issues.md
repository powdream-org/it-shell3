# Verification Round 1 Issues

**Round**: 1
**Date**: 2026-03-10
**Verifiers**: cross-reference-verifier, semantic-verifier, terminology-verifier, history-guardian

---

## Confirmed Issues

### V1-01: Version headers on docs 02 and 03 still say `v0.1`

**Severity**: minor
**Source documents**: `draft/v1.0-r2/02-integration-boundaries.md` (line 3), `draft/v1.0-r2/03-lifecycle-and-connections.md` (line 3)
**Description**: Both documents reside in the `v0.2/` directory and reflect v0.2 changes, but their metadata headers still declare `**Version**: v0.1`. Doc 01 correctly declares `**Status**: Draft v0.2`.
**Expected correction**: Update both headers to declare v0.2.
**Consensus note**: All 4 verifiers confirmed. Documents have v0.2 content (R2 applied to doc 02, R1 applied to doc 03) but stale headers.

---

### ~~V1-02: Protocol spec cited as `v0.9` in doc 02, `v0.10` elsewhere~~ — DISMISSED (owner)

**Dismissed by**: Owner during issue review.
**Reason**: Prior Art references indicate the version consulted when the document was designed. Doc 02 was written during v0.1 against protocol spec v0.9 — that reference is accurate. Doc 01 cites v0.10 because it was heavily revised in v0.2. Mechanically updating Prior Art versions without actually reviewing against the new version would be misleading.

---

### V1-03: v0.1 resolution doc R1/R3/R9 changes not applied

**Severity**: critical
**Source documents**: `draft/v1.0-r2/design-resolutions/01-v0.2-review-note-resolutions.md` Resolution 1 "Affected docs" vs `draft/v1.0-r1/design-resolutions/01-daemon-architecture.md` body (R1 line 55, R3 lines 87–96, R9 line 462)
**Description**: The v0.2 resolution's "Affected docs" claims R1/R3/R9 were applied to the v0.1 resolution doc. Only R2 (ime/ → input/ rename) was actually applied. The v0.1 resolution doc still contains pre-v0.2 structures: `HashMap(PaneId, *Pane)` (R1), `root: ?*SplitNode` with pointer children (R3), `ring_cursors: HashMap(PaneId, RingCursor)` (R9).
**Expected correction**: Apply R1, R3, and R9 structural changes to the v0.1 resolution doc to match the current v0.2 normative state. The v0.1 resolution doc is a living document (proven by R2 having been applied to it).
**Consensus note**: All 4 verifiers confirmed, including history-guardian who verified it is NOT a historical-record false alarm (R2 application proves living-doc status).

---

### V1-04: Broken relative link in doc 02 header

**Severity**: critical
**Source documents**: `draft/v1.0-r2/02-integration-boundaries.md` line 4
**Description**: The link `[Design Resolutions — Daemon Architecture](design-resolutions/01-daemon-architecture.md)` resolves to `draft/v1.0-r2/design-resolutions/01-daemon-architecture.md`, which does not exist. The actual target is `draft/v1.0-r1/design-resolutions/01-daemon-architecture.md`.
**Expected correction**: Update the relative path to `../v1.0-r1/design-resolutions/01-daemon-architecture.md`.
**Consensus note**: All 4 verifiers confirmed. Link broke when doc was copied from v0.1/ to v0.2/ without path adjustment.

---

### V1-05: Doc 03 Section 1.6 uses v0.1 data model terms

**Severity**: critical
**Source documents**: `draft/v1.0-r2/03-lifecycle-and-connections.md` Section 1.6 (~line 119) vs `draft/v1.0-r2/01-internal-architecture.md` Sections 3.2–3.3
**Description**: Section 1.6 reads: "The Session's `root` SplitNode is a single leaf pointing to `pane_id = 1`. The `focused_pane` is set to `pane_id = 1`." After v0.2 R1: (a) `root: ?*SplitNode` was removed — tree is `tree_nodes[0]`; (b) type is `SplitNodeData`, not `SplitNode`; (c) `focused_pane` is `?PaneSlot` (u8, 0..15), not `?PaneId` (u32). This section was not in the v0.2 TODO and was missed.
**Expected correction**: Update to use v0.2 terminology: `tree_nodes[0]` as initial leaf (`SplitNodeData`), `focused_pane` set to `PaneSlot` value (slot index 0).
**Consensus note**: All 4 verifiers confirmed. The initialization description contradicts the v0.2 data model specified in doc 01.

---

### V1-06: `dirty_mask` placement — resolution says `server/`, spec says `core/`

**Severity**: minor
**Source documents**: `draft/v1.0-r2/design-resolutions/01-v0.2-review-note-resolutions.md` Section 1.5 vs `draft/v1.0-r2/01-internal-architecture.md` Sections 3.2 and 3.3
**Description**: The resolution doc Section 1.5 says "Add a per-session dirty tracking bitmap **in `server/`**:" but doc 01 places `dirty_mask: u16` inside the `Session` struct in `core/session.zig`. The spec is internally self-consistent (dirty_mask in Session/core); the resolution doc has the stale placement.
**Expected correction**: Update resolution doc Section 1.5 to say `core/` (inside `Session`) to match the spec.
**Consensus note**: All 4 verifiers confirmed. The spec (doc 01) is the authoritative source; the resolution doc's "in server/" is the outlier.

---

### V1-07: `SplitNode` (v0.1 type name) in doc 03 Section 3.2

**Severity**: minor
**Source documents**: `draft/v1.0-r2/03-lifecycle-and-connections.md` Section 3.2 (child process exit pseudocode)
**Description**: The pseudocode says "remove pane from session's SplitNode tree". After v0.2, the type is `SplitNodeData` and the structure is the `tree_nodes` array. `SplitNode` is the v0.1 pointer-based type that was replaced.
**Expected correction**: Replace `SplitNode` with `SplitNodeData` or use neutral phrasing ("split tree" / "`tree_nodes` array").
**Consensus note**: All 4 verifiers confirmed. All other v0.2 documents use `SplitNodeData` exclusively.

---

## Dismissed Issues

### Issue 8: Terminal state label inconsistency (`[conn.close(), state freed]` vs `[closed]`)

**Dismissed by**: 3 of 4 verifiers (cross-reference-verifier, terminology-verifier, history-guardian). Semantic-verifier confirmed as minor.
**Reason**: Neither label is a formally defined state name. The formal enum is `{ handshaking, ready, operating, disconnecting }`. Both are informal editorial annotations for the end-of-connection condition. Not unanimously resolved — excluded from confirmed list.

### Issue 9: `MAX_PANES_PER_SESSION` heading vs `MAX_PANES` identifier

**Dismissed by**: All 4 verifiers unanimously.
**Reason**: The section heading is prose description, not an identifier declaration. `MAX_PANES_PER_SESSION` appears only in that one heading. The actual identifier `MAX_PANES` is defined consistently in all code blocks across all documents.
