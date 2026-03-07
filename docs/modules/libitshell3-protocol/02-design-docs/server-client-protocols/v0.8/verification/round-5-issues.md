# Verification Round 5 Issues

- **Round**: 5
- **Date**: 2026-03-07
- **Verifiers**: cross-reference-verifier, history-guardian, semantic-verifier, terminology-verifier

## Confirmed Issues

### V5-01 — Doc 03 Section 1.14 missing MUST-ignore cross-reference (incomplete V4-01 fix)

- **Severity**: minor
- **Source documents**: Protocol v0.8 `03-session-pane-management.md` Section 1.14 (line 348); `04-input-and-renderstate.md` Section 7.3
- **Description**: The V4-01 fix added an explicit MUST-ignore note to Section 1.6 but not to Section 1.14. Section 1.14 (AttachOrCreateResponse) reads: "On success, the same post-attach sequence applies as for AttachSessionResponse: LayoutChanged, FrameUpdate (I-frame), PreeditSync (if applicable), ClientAttached notification." There is no explicit note that the client MUST ignore the `frame_type=2` unchanged hint and process the frame as `frame_type=1`. A developer implementing the AttachOrCreate path from Section 1.14 alone would still miss the MUST-ignore rule.
- **Expected correction**: Add the same explicit cross-reference note to Section 1.14 that was added to Section 1.6: "Because a freshly attaching client has no prior I-frame, it MUST ignore the `frame_type=2` unchanged hint and process the frame as `frame_type=1`. See doc 04 Section 7.3 ('Client processing (seeking)') for the normative rule."
- **Consensus note**: All 4 verifiers confirmed.

### V5-02 — Scroll-response I-frame delivery path contradiction between doc 04 and doc 06

- **Severity**: minor
- **Source documents**: Protocol v0.8 `04-input-and-renderstate.md` Section 6.1 (line 739); `06-flow-control-and-auxiliary.md` Section 2.3 (line 276)
- **Description**: Doc 04 Section 6.1 states scroll-response I-frames "are delivered via the per-client direct message queue (priority 1), NOT the shared ring buffer, because scroll is a per-client viewport operation." Doc 06 Section 2.3 states: "All frames go through the ring — there are no bypass paths." These are mutually exclusive normative statements. The doc 06 "no bypass paths" statement was written in the context of the preedit overhaul (documenting preedit bypass removal), but the wording is absolute and conflicts with the pre-existing scroll-response bypass described in doc 04.
- **Expected correction**: Qualify doc 06 Section 2.3's statement to acknowledge the scroll-response direct-queue path (e.g., "All frames go through the ring — there are no bypass paths — except for per-client scroll-response I-frames, which use the direct message queue (see doc 04 Section 6.1)").
- **Consensus note**: All 4 verifiers confirmed.

### V5-03 — PreeditSync delivery order contradicts between doc 03 Section 1.6, doc 06 Section 2.2, and internally within doc 06 Section 2.3

- **Severity**: minor
- **Source documents**: Protocol v0.8 `03-session-pane-management.md` Section 1.6 (line 198–202); `06-flow-control-and-auxiliary.md` Section 2.2 (line 266) and Section 2.3 (line 445)
- **Description**: Three conflicts: (1) Doc 03 Section 1.6 post-attach sequence lists PreeditSync after I-frames, implying PreeditSync arrives last. (2) Doc 06 Section 2.2 states PreeditSync is in the direct message queue (priority 1), ensuring it arrives BEFORE the I-frame from the ring — "context before content" principle. (3) Doc 06 Section 2.3's stale recovery table lists PreeditSync last, while the prose immediately following states context messages arrive BEFORE the I-frame. The table and prose within doc 06 itself are inconsistent.
- **Expected correction**: Clarify in doc 03 Section 1.6 that the listed items describe what is sent, not the wire delivery order, and add a note that PreeditSync (direct message queue) arrives before I-frames on the wire. Correct doc 06 Section 2.3 table to match the prose ordering.
- **Consensus note**: All 4 verifiers confirmed.

## Dismissed Issues

| Issue | Reason for dismissal |
|-------|---------------------|
| S5-02 (Doc 05 Section 7.8 `"client_disconnected"` for voluntary DetachSession) | Section 7.8 explicitly documents this as an intentional design choice with inline justification. Not a contradiction. Unanimous dismissal. |
