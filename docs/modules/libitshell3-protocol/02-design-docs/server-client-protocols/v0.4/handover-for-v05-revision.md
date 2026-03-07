# Handover: Protocol v0.4 Review → v0.5 Revision

**From**: Protocol v0.4 review + cross-review session (2026-03-05)
**To**: Next session (v0.5 revision)

---

## 1. What was done

### v0.4 protocol revision

Six protocol design documents were written for v0.4, covering the full binary protocol, handshake, session/pane management, input/renderstate, CJK preedit, and flow control.

### Cross-review with IME Interface Contract v0.3

A cross-document consistency review was performed between Protocol v0.4 (6 docs) and IME Interface Contract v0.3. Three reviewers (protocol-architect, ime-expert, cjk-specialist) identified 11 issues + 1 gap (RestoreSession), reaching consensus on all items.

### User's own protocol review

The user independently reviewed doc 01 (protocol overview) and raised 4 additional issues covering multi-tab architecture, dead error codes, version semantics, and field naming consistency.

---

## 2. Review artifacts (all committed)

| File | Location |
|------|----------|
| Protocol v0.4 doc 01 | `docs/modules/libitshell3/02-design-docs/server-client-protocols/v0.4/01-protocol-overview.md` |
| Protocol v0.4 doc 02 | `docs/modules/libitshell3/02-design-docs/server-client-protocols/v0.4/02-handshake-capability-negotiation.md` |
| Protocol v0.4 doc 03 | `docs/modules/libitshell3/02-design-docs/server-client-protocols/v0.4/03-session-pane-management.md` |
| Protocol v0.4 doc 04 | `docs/modules/libitshell3/02-design-docs/server-client-protocols/v0.4/04-input-and-renderstate.md` |
| Protocol v0.4 doc 05 | `docs/modules/libitshell3/02-design-docs/server-client-protocols/v0.4/05-cjk-preedit-protocol.md` |
| Protocol v0.4 doc 06 | `docs/modules/libitshell3/02-design-docs/server-client-protocols/v0.4/06-flow-control-and-auxiliary.md` |
| User's protocol review notes | `docs/modules/libitshell3/02-design-docs/server-client-protocols/v0.4/review-notes-01-protocol-overview.md` |
| Protocol-side cross-review notes | `docs/modules/libitshell3/02-design-docs/server-client-protocols/v0.4/review-notes-cross-review-ime.md` |
| IME-side cross-review notes | `docs/modules/libitshell3-ime/02-design-docs/interface-contract/v0.3/review-notes-cross-review.md` |
| IME cross-review report | `docs/modules/libitshell3-ime/02-design-docs/interface-contract/v0.3/review-report.md` |
| IME handover for v0.4 revision | `docs/modules/libitshell3-ime/02-design-docs/interface-contract/v0.3/handover-for-v04-revision.md` |

---

## 3. What needs to be done: Apply review decisions to design documents

There are **TWO sources** of review notes for v0.5, requiring different handling:

- **Source A** (user's own review): 4 issues that need team DISCUSSION and consensus before applying.
- **Source B** (cross-review): 8 changes with consensus already reached — apply mechanically.

### Source A: User's own review (4 issues — NEEDS DISCUSSION)

Full details in `review-notes-01-protocol-overview.md`. The team must discuss these, reach consensus, and then apply.

#### Issue 1: Multi-tab requires multi-connection model (HIGH)

**Problem**: The single-session-per-connection rule (Section 5.2) is correct, but the spec never documents how a multi-tab client maintains simultaneous access to multiple sessions. The canonical pattern is one Unix socket connection per session (tab), but this is unstated.

**What is missing**:

1. Multi-connection model: Explicit statement that a client SHOULD open one connection per session for multi-tab scenarios.
2. Connection lifecycle for tabs: Open tab = open connection + handshake + create/attach session. Close tab = destroy session + close connection.
3. Max connections per client: No limit specified. Should the daemon enforce a maximum?
4. SSH tunnel interaction: Multiple connections over a single SSH tunnel work via SSH channel multiplexing. No protocol changes needed, but undocumented.
5. Handshake overhead: Each connection requires full ClientHello/ServerHello. With 10 tabs opened rapidly, that is 10 handshakes. Consider whether a lightweight "additional connection" handshake is needed or deferred.

**Recommendation**: Add a new Section 5.5 "Multi-Session Client Model" to doc 01. The review notes suggest investigating how tmux handles multi-window/multi-pane (single server connection with multiplexed window switching) to confirm our multi-connection model is the right approach.

**Affects**: doc 01

#### Issue 2: Remove ERR_DECOMPRESSION_FAILED (Minor)

**Problem**: Error code `0x00000007` (`ERR_DECOMPRESSION_FAILED`) is a dead error code for compression, which was removed in v0.3. No conforming implementation ever sets COMPRESSED=1, so this error has no legitimate sender. Non-conforming senders should receive `ERR_PROTOCOL_ERROR`.

**Changes needed**:

1. Remove `ERR_DECOMPRESSION_FAILED` from the error code table
2. Section 3.5: Change "send `ERR_DECOMPRESSION_FAILED`" to "send `ERR_PROTOCOL_ERROR`"
3. Section 11.2 pseudocode: Change `ERR_DECOMPRESSION_FAILED` to `ERR_PROTOCOL_ERROR`
4. Section 11.3 (Deferred Optimizations): Reword compression entry to "Removed from v1. No commitment to reintroduce." or remove entirely
5. Reserve error code `0x00000007` for future use

**Affects**: doc 01

#### Issue 3: Version field semantics and comparison logic undefined (MEDIUM)

**Problem**: The reader loop pseudocode (Section 11.2) performs exact version match (`header.version != PROTOCOL_VERSION`), meaning any version change breaks all implementations. The spec does not define what the version byte means, how it relates to capability negotiation, or how protocol evolution should work.

**Three options proposed** (team must choose one):

| Option | Semantics | Comparison | When to bump |
|--------|-----------|------------|--------------|
| **A: Wire format only** (recommended) | Version = binary header layout only. Capabilities handle all message-level evolution. | Exact match (acceptable because header layout rarely changes). | Only when 16-byte header structure changes (essentially never after v1). |
| **B: Major.minor split** | 4-bit major + 4-bit minor. Major = breaking, minor = compatible additions. | `major == MAJOR && minor >= MIN_MINOR` | Major: header/encoding changes. Minor: new message types, new required fields. |
| **C: Minimum version** | Monotonically increasing revision number. | `header.version >= MIN_SUPPORTED && header.version <= CURRENT` | Any normative spec change. Receiver supports a range. |

**Recommendation**: Option A is recommended because the capability mechanism already handles compatible evolution (new message types, optional/required fields). This avoids duplicating evolution logic. The version byte becomes an extension of the magic number.

**Changes needed** (after team decides):

1. Define what the version byte means
2. Define the relationship between version and capabilities
3. Update Section 11.2 pseudocode
4. Document the evolution policy (version bump vs. capability flag vs. optional field)

**Affects**: doc 01

#### Issue 4: Input method / keyboard layout field naming inconsistent (MEDIUM, 4 sub-issues)

**Problem**: Field names for input method and keyboard layout are inconsistent across the six documents. Four specific inconsistencies:

**4a: `active_` prefix convention is implicit**
- C-to-S messages use `input_method`; S-to-C messages use `active_input_method`
- This looks intentional (request vs. state) but is never stated as a convention
- Needs documentation in Section 7 (Encoding Conventions) or a new "Field Naming Conventions" subsection

**4b: Handshake uses abbreviated field names**
- Inside `preferred_input_methods` / `supported_input_methods` arrays: `method` (not `input_method`), `layout` (not `keyboard_layout`)
- Creates a third naming variant for the same concept

**4c: `layout` (singular) vs `layouts` (plural) asymmetry**
- ClientHello: `layout` (singular optional)
- ServerHello: `layouts` (plural array)
- Semantically justified but confusing

**4d: Protocol string identifiers vs IME contract naming mismatch**
- Protocol: `"korean_2set"` (single combined string)
- Owner directive: `"ko_2set"` (language-prefixed)
- IME contract: `LanguageId.korean` + `layout_id: "ko_2"` (two separate fields)
- Three different representations for the same concept — needs alignment or explicit mapping

**Affects**: docs 01, 02, 04, 05

---

### Source B: Cross-review decisions (8 changes — APPLY MECHANICALLY)

These changes have full consensus from the cross-review session. No further discussion needed. The next session applies them directly.

Full details and exact wording for each change are in `review-notes-cross-review-ime.md`.

| # | Document | Section | Change | Source Issue |
|---|----------|---------|--------|-------------|
| 1 | Doc 04 | Section 2.1 | Add IME routing validation note: server MUST validate `keycode <= 0xE7` before routing to IME engine. Keycodes above 0xE7 bypass IME. | Issue 1 |
| 2 | Doc 04 | Section 2.1 | Add "Wire-to-IME KeyEvent Mapping" subsection: Shift (bit 0) separated into `shift: bool`; Ctrl/Alt/Super (bits 1-3) into `modifiers`; CapsLock/NumLock (bits 4-5) dropped at IME boundary. | Issue 2 |
| 3 | Doc 05 | Section 2.2 | Document `display_width` computation: UAX #11, Korean preedit always 2 cells (precomposed syllables U+AC00-U+D7A3 and compatibility Jamo U+3131-U+318E are both Width=W). | Issue 6 |
| 4 | Doc 05 | Section 2.3 | Fix Escape PreeditEnd reason: change `"cancelled"` to `"committed"`. Escape causes flush (commit), not cancel. Matches ibus-hangul and fcitx5-hangul behavior. | Issue 9 |
| 5 | Doc 05 | Section 4.1 | Add SHOULD recommendation: clients SHOULD default to `commit_current=true` for InputMethodSwitch. The `commit_current=false` option is non-standard for Korean. | Issue 8 |
| 6 | Doc 05 | Section 4.1 | Add server implementation note: for `commit_current=false`, server calls `reset()` then `setActiveLanguage()` under per-pane lock. PreeditEnd reason is `"cancelled"`. | Issue 8 |
| 7 | Doc 05 | Section 4.1/4.3 | Add language identifier mapping cross-reference table: `"direct"` -> `LanguageId.direct`, `"korean_2set"` -> `LanguageId.korean` + `"2"`, etc. | Issue 10 |
| 8 | Doc 03 | RestoreSession section | Add IME engine initialization sequence: create engine with saved `layout_id`, call `setActiveLanguage(saved_language_id)`, no preedit restore (composition was flushed on detach/shutdown). | RestoreSession |

**Important**: The exact text for each change is provided in `review-notes-cross-review-ime.md` under each issue's "Protocol doc XX change" heading. Use that text verbatim or adapt minimally.

---

## 4. No-action items from cross-review (already correct)

These were reviewed and confirmed to require no changes. Listed here to prevent re-investigation.

| Issue | Reason |
|-------|--------|
| Issue 4 (INFO) | `keycode` (wire) vs `hid_keycode` (IME) naming — cosmetic difference, both correct in their context |
| Issue 7 (INFO) | `committed_text` + `forward_key` ordering — verified correct (committed text reaches PTY before forwarded key's effect) |
| Issue 11 (INFO) | macOS Cmd key modifier mapping — already correctly mapped to Super (bit 3), Option to Alt (bit 2). Confirmed via ghostty source. |

---

## 5. Key decisions to remember

These decisions were made in previous sessions. The v0.5 revision must preserve them.

1. **`composition_state` is `?[]const u8` (string), NOT enum** — Design Principle #1 ("single interface for all languages"). Korean constants use `ko_` prefix for collision avoidance (e.g., `"ko_leading_jamo"`, `"ko_syllable_with_tail"`). Language-agnostic `"empty"` has no prefix.

2. **No `commit: bool` on `setActiveLanguage()`** — YAGNI for v1. Server orchestrates cancel externally via `reset()` + `setActiveLanguage()` under per-pane lock. When Japanese/Chinese are added, the cancel-on-switch semantics may differ enough that a boolean parameter would be insufficient.

3. **Escape causes flush (commit), NOT cancel** — Deliberate correction from v0.2. Both ibus-hangul and fcitx5-hangul commit on Escape. The cmux reference uses macOS NSTextInputClient convention (cancel on Escape), but libitshell3 uses native IME, so the macOS convention does not apply.

4. **macOS modifier mapping**: Option = Alt (bit 2), Command = Super (bit 3). Confirmed via ghostty source (`key_mods.zig`, `Ghostty.Input.swift`, `InputIntent.swift`).

5. **SSH tunneling replaces TCP+TLS** — Decided in v0.3-to-v0.4. SSH handles auth, encryption, and channel multiplexing. No custom TLS layer needed.

6. **Heartbeat is `ping_id`-only** — `timestamp` and `responder_timestamp` removed. RTT measurement rejected (not deferred) because SSH tunneling makes it measure the wrong hop.

7. **Multi-client per session** — 12 gaps addressed in v0.4 (client_id assignment, pane ownership, focus races, etc.). These are separate from Issue 1's multi-connection model (which is about one client with multiple tabs, not multiple clients sharing a session).

8. **Hybrid encoding** — Binary 16-byte header + binary CellData/DirtyRows + JSON for everything else. This is settled since v0.3.

9. **Event-driven coalescing, NOT fixed 60fps** — 4-tier adaptive: Preedit (immediate) -> Interactive -> Active (16ms) -> Bulk (33ms) -> Idle. Preedit bypasses coalescing, PausePane, and power throttling. Less than 33ms latency target for preedit.

10. **Little-endian throughout** — Matches ARM64/x86_64 native. Explicit LE like zellij, not implicit native like tmux.

---

## 6. Companion work: IME Contract v0.4 revision

The IME Interface Contract v0.3 also needs a v0.4 revision applying cross-review decisions. That handover is at:

```
docs/modules/libitshell3-ime/02-design-docs/interface-contract/v0.3/handover-for-v04-revision.md
```

Both revisions should ideally happen in the **same session** to maintain cross-document consistency. The IME-side changes and protocol-side changes reference each other (e.g., Issue 10's cross-reference table appears in both documents). Revising one without the other risks introducing new inconsistencies.

**IME-side changes summary** (10 items — see the IME handover for full details):
- Add `HID_KEYCODE_MAX` constant and validation note (Issue 1)
- Add cross-reference to protocol doc 04 for wire-to-KeyEvent mapping (Issue 2)
- Add CapsLock/NumLock intentional omission note (Issue 3)
- Add `composition_state: ?[]const u8` to ImeResult with scenario matrix (Issue 5)
- Add LanguageId cross-reference to protocol string identifiers (Issue 10)
- Add `reset()` + `setActiveLanguage()` safety note (Issue 8)
- Add `CompositionStates` string constants with `ko_` prefix (Issue 5)
- Add session persistence fields note (RestoreSession)

---

## 7. Team composition

Use the same 3 core roles as v0.4 (see MEMORY.md for full team composition details):

| Role | Responsibility | Documents |
|------|---------------|-----------|
| **Protocol Architect** | Applies changes to protocol overview and handshake docs. Leads discussion on Source A issues 1-3 (architecture, version semantics). | Doc 01, Doc 02 |
| **Systems Engineer** | Applies changes to session/pane management and flow control docs. Owns RestoreSession IME initialization change. | Doc 03, Doc 06 |
| **CJK Specialist** | Applies changes to input/renderstate and CJK preedit docs. Owns all Source B cross-review changes. Leads discussion on Source A issue 4 (naming). | Doc 04, Doc 05 |

Custom agents for the protocol team are registered at `.claude/agents/protocol-team/` (directory exists, agent definitions to be created if not already present).

**Optional researchers** (spawn on demand):
- **tmux Researcher**: For Issue 1 — investigate how tmux handles multi-window (single connection with multiplexed switching? or multiple connections?). Source: `~/dev/git/references/tmux/`
- **ghostty Researcher**: For Issue 4d — verify ghostty's internal key/modifier naming for alignment. Source: `~/dev/git/references/ghostty/`

---

## 8. Recommended workflow

### Phase 1: Source B — Mechanical application (no discussion needed)

1. Create v0.5 directory: `docs/modules/libitshell3/02-design-docs/server-client-protocols/v0.5/`
2. Copy all 6 docs from v0.4 into v0.5
3. Apply all 8 Source B changes mechanically (exact text is in `review-notes-cross-review-ime.md`)
4. Each role applies changes to their assigned documents in parallel
5. Quick cross-check for consistency after application

### Phase 2: Source A — Discussion and consensus

1. Present all 4 issues to the team
2. For Issue 1 (multi-tab): Consider spawning a tmux researcher to investigate multi-window handling
3. For Issue 3 (version semantics): Team should evaluate Options A/B/C and reach consensus
4. For Issue 4 (naming): Coordinate with whoever is doing the IME v0.4 revision to align identifier formats
5. Once consensus is reached on each issue, apply the agreed changes

### Phase 3: Cross-document verification

1. Verify all cross-references between protocol and IME contract are consistent
2. Verify field naming consistency across all 6 protocol docs
3. Verify no stale references to removed concepts (e.g., ERR_DECOMPRESSION_FAILED)

---

## 9. Workflow lessons from previous sessions

These lessons were learned through experience. The v0.5 session lead must follow them.

1. **Review phase and revision phase MUST be strictly separated.** Do NOT modify design documents during review/discussion. First reach consensus on all issues, then apply changes.

2. **Do NOT pre-assign issues to reviewers during discussion.** Let all reviewers see all issues and discuss freely. Assign work only after consensus is reached.

3. **Do NOT intervene in team discussions.** Let agents DM each other directly and reach consensus autonomously. The team lead coordinates but does not dictate outcomes.

4. **Source A (new, need discussion) and Source B (decided, need application) should be handled as separate phases.** Source B can start immediately while Source A is being discussed — but only if different agents handle each phase to avoid confusion.

5. **Always verify cross-document consistency after revision.** Both protocol and IME documents reference each other. A change in one may require a corresponding update in the other.

6. **Always verify both review notes files for consistency before applying.** The protocol-side and IME-side cross-review notes should describe the same decisions. If they contradict, investigate before applying.
