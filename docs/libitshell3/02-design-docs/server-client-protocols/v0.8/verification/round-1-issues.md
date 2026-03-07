# Verification Round 1 Issues

- **Round**: 1
- **Date**: 2026-03-07
- **Verifiers**: cross-reference-verifier, history-guardian, semantic-verifier, terminology-verifier

## Confirmed Issues

### V1-01 — Missing `01-overview.md` and `99-appendices.md` in IME v0.7

- **Severity**: critical
- **Source documents**: IME Contract v0.7 — `02-types.md` (lines 5-6), `03-engine-interface.md` (lines 5-6, line 246), `04-ghostty-integration.md` (lines 5-6), `05-extensibility-and-deployment.md` (lines 5-6)
- **Description**: All four v0.7 IME documents contain header links to `01-overview.md` and `99-appendices.md#appendix-i-changes-from-v06`. Neither file exists in the v0.7 directory. Additionally, `03-engine-interface.md` line 246 has a body link to the missing `01-overview.md`. Total: 9 broken links (8 header + 1 body).
- **Expected correction**: Copy `01-overview.md` from v0.6 to v0.7, updating version references and document index. Create `99-appendices.md` in v0.7 with v0.6 appendices carried forward plus a new Appendix I documenting changes from v0.6.
- **Consensus note**: All 4 verifiers confirmed. Broken navigation links in current documents that readers are expected to follow.

### V1-02 — Doc 05 Section 14.2 stale dual-channel ordering statement

- **Severity**: critical
- **Source documents**: Protocol v0.8 `05-cjk-preedit-protocol.md` Section 14.2
- **Description**: Section 14.2 states "The PreeditUpdate is sent before FrameUpdate" then says "clients MUST NOT depend on this ordering — either message may arrive first due to buffering." These are normatively incompatible. In v0.8, PreeditUpdate goes via the direct message queue (priority 1) and FrameUpdate via the ring buffer (priority 2) per doc 06 Section 2.2. The priority model guarantees PreeditUpdate arrives first. The "MUST NOT depend" clause is a stale residual from the removed dual-channel design.
- **Expected correction**: Remove the "clients MUST NOT depend on this ordering" clause. Replace with a note that the socket write priority model (doc 06 Section 2.2) deterministically delivers PreeditUpdate before FrameUpdate for a given socket-writable event.
- **Consensus note**: All 4 verifiers confirmed. The clause contradicts the priority model established in doc 06 Section 2.2 and is a residual from the removed dual-channel architecture.

### V1-03 — Doc 05 Section 4.3 line 311 wrong cross-reference label

- **Severity**: critical
- **Source documents**: Protocol v0.8 `05-cjk-preedit-protocol.md` Section 4.3 line 311
- **Description**: Line 311 reads "see IME Interface Contract, Section 9 for the per-session engine architecture." IME Contract Section 9 is titled "Session Persistence" and covers session snapshot schema — not per-session engine architecture. The per-session engine architecture is in Sections 3.5-3.7. Line 317 in the same section correctly references Section 9 as "session snapshot schema".
- **Expected correction**: Change "Section 9 for the per-session engine architecture" to either "Sections 3.5-3.7 for the per-session engine architecture" or reword to match the actual Section 9 content.
- **Consensus note**: All 4 verifiers confirmed. Line 317 proves the correct label for Section 9 was known; line 311 uses the wrong label.

### V1-04 — Unchanged doc 02 has stale preedit capability semantics

- **Severity**: critical
- **Source documents**: Protocol v0.7 `02-handshake-capability-negotiation.md` lines 380, 901, 903
- **Description**: The unchanged v0.7 doc 02 describes the `"preedit"` capability as enabling "preedit section in the JSON metadata blob" in FrameUpdate messages. This directly contradicts v0.8 Resolution 2 which completely removed the preedit JSON section from FrameUpdate. Lines 380, 901, and 903 all contain this stale description. A reader consulting doc 02 for preedit capability behavior gets incorrect information.
- **Expected correction**: Copy doc 02 to v0.8 and update preedit capability semantics. The `"preedit"` capability controls only the dedicated 0x04xx messages (PreeditStart/Update/End/Sync). Preedit rendering is always available through cell data in I/P-frames regardless of capability negotiation.
- **Consensus note**: All 4 verifiers confirmed. These are current normative capability semantics (not changelog entries) that contradict the v0.8 architecture.

### V1-05 — Doc 06 overview paragraph duplicate "doc 04" reference

- **Severity**: minor
- **Source documents**: Protocol v0.8 `06-flow-control-and-auxiliary.md` Overview paragraph
- **Description**: The sentence "input forwarding (doc 04), and render state streaming (doc 04)" lists "doc 04" twice. Both references are technically correct but read as a copy-paste error.
- **Expected correction**: Rephrase to "input forwarding and render state streaming (both in doc 04)" or similar.
- **Consensus note**: All 4 verifiers confirmed. Pre-existing from v0.7, not a v0.8 regression, but still an editorial issue in the current document.

## Dismissed Issues

| Issue | Reason for dismissal |
|-------|---------------------|
| D (Section 8.2 Rule 1 parenthetical) | Names event triggers, not routing destinations. Section 14.1 provides unambiguous context. |
| E (Section 7.1 vs 7.2 opposite behaviors) | Intentionally different behaviors with explicit rationale in each section. No logical contradiction. |
| H (Resolution doc abbreviated frame_type names) | Resolution document is non-normative. Abbreviated names in a decision record are informal shorthand. |
