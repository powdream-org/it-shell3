# Protocol Doc Changes Required (from IME v0.6 Revision)

> **Date**: 2026-03-05
> **Source**: IME interface contract v0.6 revision (per-session engine architecture, Resolutions 9–13)
> **Target**: Protocol doc team for v0.7 revision
> **Affected docs**: Protocol doc 03 (session/pane mgmt), Protocol doc 05 (CJK preedit protocol)
> **Participants who resolved these**: protocol-architect, ime-expert, cjk-specialist (3/3 unanimous)

---

These changes were agreed during the IME v0.6 design (design-resolutions-per-tab-engine.md, Resolutions 9–13) but belong in the protocol docs, not the IME contract. The protocol team should apply them to the next revision of docs 03 and 05.

---

## Doc 03 Changes (Session/Pane Management)

### Change 1: LayoutChanged — Add Normative Note on Leaf Node Consistency (Resolution 9)

In the LayoutChanged message description, add a normative note:

> All leaf nodes in a session MUST have identical `active_input_method` and `active_keyboard_layout` values. The server populates these from the session's shared engine state. Clients MUST NOT interpret per-leaf differences as intentional per-pane overrides — they represent a server bug if they occur.

**Rationale**: With the per-session engine, all panes share the same `active_input_method`. Leaf nodes still carry the field for self-containedness (a client rendering a single pane can read its leaf without walking to session-level fields), but all values must be identical.

### Change 2: AttachSessionResponse — Replace Per-Pane Array with Session-Level Fields (Resolution 10)

Replace the `pane_input_methods` array in `AttachSessionResponse` with session-level fields:

**Before:**
```json
{
  "status": 0,
  "session_id": 1,
  "name": "my-session",
  "active_pane_id": 1,
  "pane_input_methods": [
    { "pane_id": 1, "input_method": "korean_2set" },
    { "pane_id": 2, "input_method": "korean_2set" }
  ]
}
```

**After:**
```json
{
  "status": 0,
  "session_id": 1,
  "name": "my-session",
  "active_pane_id": 1,
  "active_input_method": "korean_2set",
  "active_keyboard_layout": "qwerty"
}
```

The `pane_input_methods` array is obsolete — all panes share the session's engine, so a single session-level field is sufficient. Leaf nodes in LayoutChanged (Change 1 above) provide the same data per-pane for clients that need it.

Apply the same change to `AttachOrCreateResponse`.

### Change 3: CreatePaneRequest / SplitPaneRequest — Remove Per-Pane input_method Field (Resolution 7)

If either message currently carries a per-pane `input_method` field (for specifying the new pane's initial input method), remove it. New panes inherit the session's shared engine state automatically. No per-pane input method specification is needed or meaningful.

Add a note in the message description:

> The new pane inherits the session's current `active_input_method`. No per-pane override is supported. To change the input method, send an InputMethodSwitch message (0x0404) after the pane is created.

---

## Doc 05 Changes (CJK Preedit Protocol)

### Change 4: InputMethodSwitch (0x0404) — Remove `per_pane` Field (Resolution 11)

Remove the `per_pane` boolean field from InputMethodSwitch.

**Revised wire format:**
```json
{
  "pane_id": 1,
  "input_method": "korean_2set",
  "keyboard_layout": "qwerty",
  "commit_current": true
}
```

`pane_id` is retained for consistency with all other C→S messages (all use `pane_id` for addressing). The server derives the session from the pane and applies the input method switch to the entire session.

Update the server behavior description:

> The server identifies the session from `pane_id`, then applies the input method switch to the entire session (all panes). The switch is not limited to the identified pane.

### Change 5: InputMethodAck (0x0405) — Add Normative Note on Session-Wide Scope (Resolution 12)

Add a normative note to the InputMethodAck message description:

> `pane_id` identifies the pane that was focused when the input method switch occurred. Clients MUST update the input method state for ALL panes in the session, not just the identified pane. Displaying a stale input method for any pane in the session is incorrect.

### Change 6: New Section — Preedit Exclusivity Rule (Resolution 13)

Add a normative section (suggested location: Section 1 overview or a new dedicated normative section before the message descriptions):

> **Preedit exclusivity invariant**: At most one pane in a session can have active preedit at any time. This is naturally enforced by the single engine instance per session — the engine has one `HangulInputContext` with one jamo stack. A server that correctly implements the per-session engine model MUST NOT produce simultaneous PreeditUpdate messages for two different panes within the same session.
>
> Clients MAY rely on this invariant for rendering optimization: when a PreeditStart arrives for pane B, any active preedit on pane A within the same session has already been cleared via PreeditEnd.

### Change 7: Section 4.3 — Update Per-Pane Input Method State to Per-Session (Resolution 11)

Section 4.3 (or wherever "Per-Pane Input Method State" is described) must be updated to reflect the per-session model:

- Rename section to "Per-Session Input Method State" (or equivalent).
- Update all references from per-pane ownership to per-session ownership.
- Note that the client tracks one `active_input_method` per session, updated by InputMethodAck and initialized by AttachSessionResponse.

### Change 8: Section 4.1 — "per-pane lock" → "per-session lock" in Discard-and-Switch Description

In the InputMethodSwitch server behavior description (Section 4.1, discard-and-switch pattern using `commit_current=false`), update the lock scope:

**Before:**
> The server orchestrates cancel via `reset()` + `setActiveInputMethod()` under per-pane lock.

**After:**
> The server orchestrates cancel via `reset()` + `setActiveInputMethod()` under per-session lock.

**Rationale**: With the per-session engine, there is one engine per session. The lock that guards `reset()` + `setActiveInputMethod()` atomicity must cover the session, not just a single pane.

### Change 9: Section 9.2 — Update Session Restore IME Description to Per-Session (Resolution 8)

In the session restore section (Section 9.2 or equivalent), update the description of IME state restoration:

**Before (per-pane model):**
> Per-pane input method identifiers are restored. For each pane, the server creates a `HangulImeEngine` with the saved `input_method` and calls `setActiveInputMethod()`.

**After (per-session model):**
> The session's `input_method` and `keyboard_layout` are restored at session level. The server creates one `HangulImeEngine` per session with the saved `input_method`. All panes in the session share this engine. No per-pane IME state is restored — panes carry no IME fields in the session snapshot.

Also update the session snapshot JSON example (if present) from a per-pane `ime` field inside each pane to a single `ime` object at session level, matching the format in IME contract Section 9.

### Change 10: Section 15 Open Questions — Resolve Q5 (Simultaneous Compositions Contradicts Preedit Exclusivity)

Section 15, Open Question #5 (or equivalent) asks about "simultaneous compositions per pane" or similar. This directly contradicts the preedit exclusivity invariant established by Resolution 13.

**Resolution**: Close this question as resolved. The per-session engine architecture (Resolution 1) makes simultaneous compositions per session physically impossible — a single `HangulInputContext` has one jamo stack. The preedit exclusivity invariant (Change 6 above) is the normative statement of this constraint.

Remove the open question and add a note in the relevant section:

> **Resolved (v0.7)**: Simultaneous compositions within a session are not possible. The per-session engine (one `HangulInputContext` per session) enforces the preedit exclusivity invariant. See Section 1 for the normative statement.

### Change 11: Section 4.3 — Note keyboard_layout Per-Session Scope

In Section 4.3 (wherever `keyboard_layout` is described as a property), update the ownership description:

**Before:**
> `keyboard_layout` is a per-pane property, persisted per pane in session snapshots.

**After:**
> `keyboard_layout` is a per-session property, shared by all panes in a session. Both `input_method` and `keyboard_layout` are stored at session level in session snapshots (not per pane). See IME contract Section 9 for the session snapshot schema.

---

## Summary Table

| Doc | Section/Message | Change type | Resolution |
|-----|----------------|-------------|------------|
| Doc 03 | LayoutChanged | Add normative note (leaf node consistency) | R9 |
| Doc 03 | AttachSessionResponse | Replace `pane_input_methods` array with session-level fields | R10 |
| Doc 03 | AttachOrCreateResponse | Same as AttachSessionResponse | R10 |
| Doc 03 | CreatePaneRequest, SplitPaneRequest | Remove per-pane `input_method` field | R7 |
| Doc 05 | InputMethodSwitch (0x0404) | Remove `per_pane` field | R11 |
| Doc 05 | InputMethodAck (0x0405) | Add normative note: clients update ALL panes | R12 |
| Doc 05 | Section 1 / new section | Add preedit exclusivity invariant | R13 |
| Doc 05 | Section 4.1 | "per-pane lock" → "per-session lock" in discard-and-switch | R1/R8 |
| Doc 05 | Section 4.3 | Rename and update per-pane → per-session; note keyboard_layout per-session scope | R11 |
| Doc 05 | Section 9.2 | Update session restore description to per-session model | R8 |
| Doc 05 | Section 15 (Open Questions) | Resolve Q5 (simultaneous compositions) — contradicts R13 | R13 |

No new message types are introduced. The architectural change is handled entirely through semantic updates to existing messages.
