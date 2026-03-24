# Design Resolutions: Daemon v1.0-r6

**Date**: 2026-03-23 **Team**: daemon-architect, ghostty-integration-engineer,
ime-system-sw-engineer, principal-architect, protocol-architect,
system-sw-engineer (6 members) **Scope**: SEM-A preedit ownership resolution and
16 CTR scope check (15 original plus CTR-04 pulled into scope) **Source**: SEM-A
review note `draft/v1.0-r5/review-notes/01-preedit-ownership-scope.md`;
cross-team requests `draft/v1.0-r5/cross-team-requests/` (CTR-01 through CTR-20)

---

## Resolution 1: SEM-A Preedit Ownership Scope (6/6 unanimous)

**Source**: Review note `01-preedit-ownership-scope.md` (HIGH, deferred from
v1.0-r5) **Affected docs**: `01-internal-architecture.md` (doc01 §3.8),
`04-runtime-policies.md` (doc04 §6.1, §6.2, §11)

### Decision

**Option A: Clarify as complementary design.** The `PanePreeditState` ownership
tracking (doc04 §6.1-6.2) and the per-session engine exclusivity invariant
(doc04 §11) address two orthogonal concerns:

1. **Multi-PANE contention**: The per-session IME engine structurally prevents
   simultaneous compositions across different panes. There is one engine per
   session with one composition state machine. This is what §11 means by
   "physically impossible."

2. **Multi-CLIENT contention on the same pane**: Two clients attached to the
   same session can both send KeyEvents to the focused pane. The event loop
   serializes processing, but the IME engine has no concept of "client" — it
   would silently interleave keystrokes from different humans into one
   composition, producing garbage. The daemon must track which client initiated
   the active composition and, when a different client sends a composing key,
   flush the first client's preedit before processing the new key. This is what
   §6.2 specifies (last-writer-wins).

These are orthogonal invariants: §11 prevents multi-pane composition; §6.2
handles multi-client ownership on the single focused pane.

### Rationale

- The IME engine is a pure composition state machine. It receives keycodes and
  produces `ImeResult`. It has zero knowledge of which client sent the key.
  Without ownership tracking, Client B's composing key would silently extend
  Client A's in-progress composition.
- Multi-client attachment to the same session is a first-class feature (protocol
  supports `AttachSessionResponse`, multi-client resize policy, health states).
  The tmux control-mode pattern — two terminal windows attached to the same
  session, both typing — is a real scenario.
- Sequential processing (single-threaded event loop) eliminates data races but
  does NOT eliminate the semantic problem of interleaved compositions from
  different clients.

### Prior art

tmux supports multiple clients on the same session. tmux does not have
server-side IME, so it does not face the composition ownership problem. Our
architecture's server-side IME introduces a new contention axis that tmux never
needed to address.

---

## Resolution 2: Eliminate `PanePreeditState`, Move Ownership to Session (6/6 unanimous)

**Source**: Discussion consensus **Affected docs**:
`01-internal-architecture.md` (doc01 §3.2 class diagram, §3.8),
`04-runtime-policies.md` (doc04 §6.1)

### Decision

Eliminate the standalone `PanePreeditState` struct. Move ownership fields
directly onto `Session` as a nested `PreeditState` sub-struct:

```zig
// core/session.zig — Session struct (updated)
Session {
    // ... existing fields ...
    ime_engine: ImeEngine,
    current_preedit: ?[]const u8,  // rendering cache (authoritative preedit text)
    preedit_buf: [64]u8,           // backing store for current_preedit
    last_preedit_row: ?u16,        // dirty tracking for preedit row
    preedit: PreeditState,         // multi-client ownership (NEW)
}

// core/session.zig — PreeditState (replaces PanePreeditState)
PreeditState {
    owner: ?u32,       // client_id of composing client, null = no active composition
    session_id: u32,   // monotonic counter, carried in PreeditStart/Update/End/Sync wire messages
}
```

Three changes from the prior `PanePreeditState`:

1. **`preedit_text` removed.** `Session.current_preedit` (doc01 §3.8) is the
   single authoritative source for preedit text. It is updated from `ImeResult`
   on every `processKey()` call and read by `overlayPreedit()` at export time.
   Having a second copy in the ownership struct is a sync hazard — if the two
   ever diverge, the protocol layer sends one text while the render layer shows
   another. All consumers (PreeditUpdate messages, commit-to-PTY operations,
   overlayPreedit rendering) read from `session.current_preedit`.

2. **Struct renamed from `PanePreeditState` to `PreeditState`.** The old name
   implied per-pane granularity that does not exist. The preedit exclusivity
   invariant is per-session (one engine, one composition at a time), so
   ownership tracking is inherently session-scoped.

3. **Struct lives on `Session`, not on `Pane`.** The preedit exclusivity
   invariant guarantees at most one pane per session has active preedit. A
   per-pane struct would mean either (a) every pane carries an instance with all
   but one always null, or (b) a single instance with a misleading per-pane
   name. Session-level placement makes the invariant self-evident in the data
   structure.

### `preedit_session_id` retention

`preedit_session_id` (renamed to `session_id` within the nested struct) is
retained. It has four concrete wire protocol consumers:

| Wire message    | Type code | Field                | Purpose                     |
| --------------- | --------- | -------------------- | --------------------------- |
| `PreeditStart`  | 0x0400    | `preedit_session_id` | Unique ID for this session  |
| `PreeditUpdate` | 0x0401    | `preedit_session_id` | Correlates with Start       |
| `PreeditEnd`    | 0x0402    | `preedit_session_id` | Correlates with Start       |
| `PreeditSync`   | 0x0403    | `preedit_session_id` | Late-joining client context |

It disambiguates overlapping composition sessions and enables stale message
detection (protocol Doc 05 §10 error table).

### Rendering cache vs ownership metadata

`Session.current_preedit` / `preedit_buf` remain on Session as top-level fields
(not inside `PreeditState`). They serve the render pipeline (`overlayPreedit()`
reads `session.current_preedit` directly); the ownership struct serves
multi-client coordination. Different consumers, different access patterns —
grouping them separately is intentional.

---

## Resolution 3: Focus-Preedit Invariant (6/6 unanimous)

**Source**: Discussion consensus (daemon-architect + ime-system-sw-engineer)
**Affected docs**: `04-runtime-policies.md` (doc04 §6.1, §7.1)

### Decision

Document the following normative invariant: **The pane with active preedit is
always `Session.focused_pane`.** No explicit `preedit_pane` field is needed.

Proof:

1. Focus change always commits preedit (doc04 §7.1).
2. New composition can only start on the focused pane (keys are routed to the
   focused pane).
3. Therefore, there is no state where preedit is active on a non-focused pane.

An explicit `preedit_pane` field would create a sync hazard — any bug where
`preedit_pane` and `focused_pane` diverge would cause preedit to be overlaid on
the wrong pane or committed to the wrong PTY. The implicit invariant is stronger
because it is structurally impossible to violate.

The focus-change sequence relies on this invariant: the daemon commits preedit
to the OLD `focused_pane`'s PTY (step 3) before updating `focused_pane` to the
new pane (step 6), guaranteeing the correct PTY receives the committed text
without a separate `preedit_pane` field.

---

## Resolution 4: Reword "Concurrent Attempt" in §6.2 (6/6 unanimous)

**Source**: Discussion consensus **Affected docs**: `04-runtime-policies.md`
(doc04 §6.2 Rule 2)

### Decision

Reword §6.2 Rule 2 from "concurrent attempt" to "ownership transition on client
switch." The current wording implies true concurrency; the actual scenario is
sequential processing of interleaved keys from different clients in the
single-threaded event loop.

Replace: "Concurrent attempt: When Client B sends a composing KeyEvent on the
same pane while Client A owns the preedit..."

With: "Ownership transition: When Client B sends a composing KeyEvent on the
same pane while Client A owns the preedit (interleaved client keys processed
sequentially by the event loop)..."

The behavioral specification remains unchanged — flush Client A's preedit,
transfer ownership to Client B, send PreeditEnd/PreeditStart. Only the framing
changes to accurately describe sequential ownership transition rather than
implying concurrent access.

---

## Resolution 5: Normative Notes for §6.1 and §11 (6/6 unanimous)

**Source**: SEM-A review note, discussion consensus **Affected docs**:
`04-runtime-policies.md` (doc04 §6.1, §11)

### Decision

Add two normative notes:

**§6.1 normative note** (after the `PreeditState` struct definition):

> `PreeditState` tracks multi-CLIENT ownership on the focused pane. When
> multiple clients are attached to the same session, the `owner` field
> determines which client initiated the active composition. The per-session IME
> engine prevents multi-PANE simultaneous composition (§11); `PreeditState`
> handles the orthogonal concern of multi-client contention on a single pane.
> For the authoritative preedit text, see `Session.current_preedit` (doc01
> §3.8).

**§11 normative note** (appended to the "Single preedit owner per session"
entry):

> "Physically impossible" refers to multi-PANE simultaneous composition: one IME
> engine per session means one composition state machine, one focused pane.
> Multi-CLIENT contention on the same focused pane is handled by §6.2's
> ownership transition protocol — this is a complementary mechanism, not a
> contradiction.

---

## Resolution 6: CTR Scope and Disposition (6/6 unanimous)

**Source**: 15 cross-team requests from protocol v1.0-r12 cleanup + CTR-04
pulled into scope by owner decision **Affected docs**: all four daemon spec docs

### 6.1 Per-CTR Disposition

#### Mechanical / clean integration

| CTR    | Topic                      | Target doc(s)  | Notes                                          |
| ------ | -------------------------- | -------------- | ---------------------------------------------- |
| CTR-01 | Resize internals           | doc04 §2       | Verify completeness vs existing content        |
| CTR-02 | Pane ID routing            | doc04          | Straightforward add                            |
| CTR-03 | Korean composition example | doc01          | Pure documentation move                        |
| CTR-05 | Input processing priority  | doc01          | Flow diagram + priority order                  |
| CTR-15 | Ambiguous width            | doc04          | Single-sentence add                            |
| CTR-16 | Compression flag removed   | doc03          | Trivial string replacement                     |
| CTR-17 | Server negotiation         | doc03          | Handshake negotiation algorithms               |
| CTR-20 | Section renumbering        | doc03 line 583 | Mechanical cross-reference fix (§9 becomes §8) |

#### Removals

| CTR    | Topic                    | Target doc(s)        | Notes                                                                                                                                                               |
| ------ | ------------------------ | -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| CTR-10 | Snapshot/restore removed | doc04 §8, doc01 §3.7 | ADR 00036 removes entire persistence feature from v1. Remove doc04 §8 entirely. Clean up doc01 §3.7 snapshot JSON format references. Frees §8 slot for repurposing. |

#### Large integrations (dedup against existing v1.0-r6 content)

| CTR    | Topic                | Target doc(s) | Notes                                                                                                                                                                                                                                                                                                                |
| ------ | -------------------- | ------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| CTR-06 | Ring buffer          | doc01 + doc04 | Largest CTR (10 items). Pair with CTR-08. Dedup: doc04 §4.5 already defines socket write priority.                                                                                                                                                                                                                   |
| CTR-07 | Health escalation    | doc04 §3      | Verify what's already absorbed. Check heartbeat RTT heuristic completeness.                                                                                                                                                                                                                                          |
| CTR-08 | Coalescing tiers     | doc04 §5      | Pair with CTR-06. Dedup against existing content.                                                                                                                                                                                                                                                                    |
| CTR-09 | Authentication       | doc03         | Single authoritative timeout table (not two copies). Add explicit socket permissions: `chmod 0700` (directory), `chmod 0600` (socket). Socket directory: `$TMPDIR/it-shell3/` on macOS, `$XDG_RUNTIME_DIR/it-shell3/` on Linux, `/tmp/it-shell3-$UID/` as fallback. Fail-safe: refuse to start on wrong permissions. |
| CTR-12 | IME engine lifecycle | doc02         | Drop item 8 (engine init on restore) — conflict with CTR-10 / ADR 00036. Items 1-7 valid.                                                                                                                                                                                                                            |

#### SEM-A dependent (integrate last)

| CTR    | Topic                   | Target doc(s) | Notes                                                                              |
| ------ | ----------------------- | ------------- | ---------------------------------------------------------------------------------- |
| CTR-11 | Preedit race conditions | doc04 NEW §8  | 12 server behavior procedures. Repurpose freed §8 slot. See §6.3 for organization. |

#### Pulled from deferred (design gap)

| CTR    | Topic                     | Target doc(s)      | Notes                                                                                                                                                                                                                                    |
| ------ | ------------------------- | ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| CTR-04 | Mouse-preedit interaction | doc01 + doc02 §4.8 | Owner pulled into r6 scope. MouseButton commits preedit before forwarding. MouseScroll/MouseMove exempt. Resolves normative contradiction "mouse events bypass IME entirely." Preedit check in `server/` before `terminal.mousePress()`. |

### 6.2 CTR-10 / CTR-12 Conflict Resolution

CTR-12 item 8 requests documentation of "engine initialization on session
restore." CTR-10 removes the entire Snapshot/Restore feature from v1 per ADR
00036. Resolution: **drop CTR-12 item 8**. The remaining 7 items of CTR-12 are
unaffected.

ADR 00036 removes both the save and restore sides of persistence (wire messages
0x0700-0x0707 are all deleted). Doc04 §8 (Session Persistence) should be removed
entirely for v1.

### 6.3 Repurpose §8 for Server Behavior Procedures

With CTR-10 removing doc04 §8 (Session Persistence), the freed section is
repurposed for "Server Behavior Procedures" to house CTR-11's 12 server behavior
procedures. This separates policy (§6 ownership rules, §7 lifecycle policies)
from procedure (§8 step-by-step engine call sequences with lock scope, buffer
lifetime, and message ordering constraints).

Proposed subsection structure:

| Section | Topic              | Content                                                                                                                                                                       |
| ------- | ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| §8.1    | Ownership transfer | Reference procedure: the flush-and-transfer sequence. Other procedures reference this. Engine buffer lifetime constraint: extract from `ImeResult` before next mutating call. |
| §8.2    | Client-triggered   | Disconnect, detach, eviction procedures.                                                                                                                                      |
| §8.3    | State-triggered    | Focus change, pane close, alt screen, resize procedures.                                                                                                                      |
| §8.4    | Input-triggered    | Rapid keystrokes, mouse click, InputMethodSwitch procedures.                                                                                                                  |
| §8.5    | Error recovery     | Invalid composition state procedure.                                                                                                                                          |

§8.1 (ownership transfer) is the foundational procedure. It defines the 10-step
flush-and-transfer sequence with the critical buffer lifetime constraint: the
daemon must extract `committed_text` from the `ImeResult` returned by
`engine.flush()` before making any further engine calls, because the engine's
internal buffers are invalidated on the next mutating call (per IME contract
Section 6). Other procedures (§8.2-§8.4) reference §8.1's flush steps rather
than duplicating them.

### 6.4 Integration Order

The design team should integrate CTRs in the following dependency order:

| Order | CTR(s)                 | Rationale                                              |
| ----- | ---------------------- | ------------------------------------------------------ |
| 1     | SEM-A (R1-R5)          | Affects CTR-11, CTR-12 framing                         |
| 2     | CTR-20                 | Mechanical renumbering; avoids stale cross-references  |
| 3     | CTR-10, CTR-16         | Removals and small edits; quick wins                   |
| 4     | CTR-06 + CTR-08        | Ring buffer + coalescing; tightly coupled              |
| 5     | CTR-07                 | Health escalation; references ring buffer              |
| 6     | CTR-01                 | Resize; references health model                        |
| 7     | CTR-09, CTR-17         | Auth + negotiation; both land in doc03                 |
| 8     | CTR-02, CTR-05, CTR-15 | Input routing; independent                             |
| 9     | CTR-03                 | Korean example; independent                            |
| 10    | CTR-12                 | IME lifecycle; integrate before CTR-11                 |
| 11    | CTR-11                 | Preedit race conditions; depends on SEM-A + CTR-12     |
| 12    | CTR-04                 | Mouse-preedit; last (depends on CTR-11 §8.4 structure) |

### 6.5 Dedup Guidance

CTRs were written against the protocol spec's v1.0-r12 removal, not against the
daemon's v1.0-r6 baseline. Some CTRs (especially CTR-01, CTR-06, CTR-07, CTR-08)
may be partially or fully absorbed in existing v1.0-r6 content, since the daemon
docs were developed in parallel with the protocol cleanup.

The design team MUST diff each CTR's "Required Changes" list against existing
v1.0-r6 content before adding anything. For each item: if already present, mark
satisfied; if partially present, identify the gap; if absent, add it. This
avoids both duplication and missed content.

---

## Wire Protocol Changes

**None.** All resolutions are daemon-internal documentation changes. The wire
protocol (message types, field definitions, encoding) is unaffected.

---

## Items Deferred

| Item                                               | Deferred to | Rationale                                                |
| -------------------------------------------------- | ----------- | -------------------------------------------------------- |
| Snapshot/Restore feature                           | Post-v1     | ADR 00036. Must define restore scope before redesigning. |
| `echo_nonce` (app-level heartbeat verification)    | v2          | `HEARTBEAT_NONCE` capability; doc04 §10.4                |
| Per-client viewports (scroll to see clipped areas) | v2          | doc04 §2.3                                               |
