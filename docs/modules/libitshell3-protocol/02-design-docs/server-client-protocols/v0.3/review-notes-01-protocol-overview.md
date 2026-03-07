# Review Notes: 01-protocol-overview.md (v0.3)

**Reviewer**: heejoon.kang
**Date**: 2026-03-04

---

## Issue 1: Flags byte bit numbering convention not explicitly stated

**Severity**: Minor (clarification)

Byte order for multi-byte fields is clearly specified as "Little-endian throughout"
(Principle 4, Section 7), with solid justification comparing tmux (implicit native)
and zellij (explicit LE).

However, the **bit numbering convention** within the flags byte (offset 3) is not
explicitly stated in prose.

- Spec table: `Bit 0 = ENCODING, Bit 1 = COMPRESSED, ...`
- Zig code: `packed struct(u8) { encoding: bool, compressed: bool, ... }`

In Zig's `packed struct(u8)`, the first field is placed at the LSB (bit 0 = least
significant bit). This is defined behavior in the Zig language spec. Since the Zig
code is included in the spec document as a canonical reference, the bit ordering is
**effectively defined**.

However, implementers unfamiliar with Zig (e.g., Swift or C developers) cannot
determine from the spec table alone whether "bit 0" means LSB or MSB. In RFC
convention, "bit 0" typically refers to MSB, which is the opposite.

### Recommendation

Add one line to Section 3.2 (Frame Flags):

> Bit numbering is LSB-first: bit 0 is the least significant bit (0x01),
> bit 7 is the most significant bit (0x80).

Or add a concrete example:

> Example: ENCODING=1 only -> flags byte = `0x01`.
> ENCODING=1 + COMPRESSED=1 -> flags byte = `0x03`.

This allows implementation without reading the Zig code.

---

## Issue 2: Heartbeat timestamp specification is incomplete

**Severity**: Medium (material impact in Phase 6 TCP/TLS over the internet)

### 2a. Timezone / clock source not specified

The spec does not state whether `timestamp` and `responder_timestamp` are UTC-based
or local time. Unix epoch (ms since 1970-01-01T00:00:00Z) is implicitly UTC, but
the spec should explicitly state:
"All timestamps are milliseconds since Unix epoch (UTC)" in Section 7 or Section 5.4.

### 2b. Clock skew estimation method undefined

The spec describes `responder_timestamp` as being "for RTT and clock skew estimation"
but provides no calculation method.

The current two-way exchange yields 3 timestamps:

```
T1_S = server Heartbeat send time (server clock)
T2_C = client responder_timestamp (client clock)
T3_S = server HeartbeatAck receive time (server clock)
```

- **RTT**: `T3_S - T1_S` — uses the same clock, accurate. OK.
- **Clock skew approximation**: `offset ~ T2_C - (T1_S + T3_S) / 2` — requires
  the assumption that one-way delays are symmetric. Same approach as NTP.

Neither the formula nor the symmetric-delay assumption is documented in the spec.

### 2c. RTT and clock skew have no documented consumer

The spec collects RTT and `responder_timestamp` data but **never specifies what
uses them**. A full-text search of all v0.3 docs reveals:

- **RTT**: Calculated (`current_time - ack.timestamp`) but no protocol behavior
  depends on it. Not used by the adaptive coalescing model, flow control,
  or any other subsystem.
- **`responder_timestamp`**: Collected but no consumer. No component reads or
  acts on clock skew estimates.
- **Heartbeat's only effective purpose** is liveness detection (90-second
  timeout). The timestamp fields are dead data.

This raises a fundamental question: **why collect data that nothing uses?**

Possible intended uses (not documented):
- Adaptive coalescing could use RTT to adjust tier thresholds for WAN clients
- Debugging/logging could correlate cross-device timestamps
- Future client-side prediction (mentioned as open question in doc 05 line 865)
  could use RTT for latency compensation

The designer should either:
1. Define concrete consumers for RTT/clock skew and document the behavior, or
2. Simplify Heartbeat to liveness-only (drop `responder_timestamp`, keep only
   `ping_id` for correlation) and add RTT measurement later when a real
   consumer exists

Reference investigation needed: check how tmux, zellij, and iTerm2 handle (or
don't handle) RTT measurement, clock synchronization, and latency-based
adaptation in their protocols.

**Relationship to adaptive coalescing (Section 10)**: One might expect heartbeat
RTT to feed into the 4-tier adaptive coalescing model — e.g., adjusting tier
thresholds for high-latency clients. However, the coalescing model uses PTY
output rate (KB/s) and keystroke timing to select tiers. It never references
heartbeat RTT. These two systems are completely disconnected in the current spec.

**Compounded by SSH tunneling (see Issue 4)**: If the transport moves to SSH
tunneling, heartbeat RTT becomes doubly useless:

```
What heartbeat RTT measures:    daemon <-> sshd  (local Unix socket, ~0ms)
What we actually need to know:  daemon <-> iOS app  (internet, 50-100ms)
```

The heartbeat only sees the local hop to sshd, not the true end-to-end latency
to the remote client. Even if a consumer for RTT existed, the measured value
would be wrong.

The correct approach (proposed in Issue 4) is client self-reporting of transport
characteristics via `ClientDisplayInfo`, which the coalescing model can then
use for per-client tier adjustment.

### 2d. Two-way exchange cannot accurately measure clock skew over the internet

Phase 6 TCP/TLS connects iOS and macOS over the **public internet**, not just LAN.
Over the internet, one-way delays are asymmetric due to:

- Uplink/downlink speed differences
- Asymmetric routing paths
- Intermediate node queuing delays

The symmetric-delay assumption (`offset ~ T2_C - (T1_S + T3_S) / 2`) breaks down.
The resulting clock skew estimate can have errors of tens to hundreds of milliseconds.
Even NTP mitigates this limitation by using multiple servers, repeated measurements,
and statistical filtering.

Consequences of inaccurate clock skew:
- Cross-device timestamp comparison for debugging becomes meaningless
- If timestamp-based logic is added in the future (e.g., message ordering,
  expiration), inaccurate skew becomes a real bug

### Recommendations

1. Explicitly state "timestamps are UTC (Unix epoch)" in Section 5.4 or Section 7
2. Document the RTT formula: `RTT = T3_S - T1_S`
3. Document the limitation of clock skew estimation: "Two-way exchange only;
   accurate under symmetric-delay assumption. Not reliable over the internet."
4. Constrain `responder_timestamp` usage to RTT supplementary data and debugging
   only. Explicitly prohibit using clock skew estimates in protocol logic.
5. Record in Design Decisions that if accurate clock sync is needed in the future,
   the protocol should be extended to NTP-style 4-timestamp exchange or a
   three-way handshake.

---

## Issue 3: JSON optional field convention is ambiguous

**Severity**: Medium (affects all JSON-encoded messages)

Section 7 (Endianness and Encoding Conventions) states:

> Optional fields: JSON: field absent or `null`.

This allows **two different representations** for the same semantic meaning
("this field has no value"):

```json
// Option A: field absent
{ "pane_id": 1 }

// Option B: field present with null
{ "pane_id": 1, "shell_command": null }
```

The spec must pick **one** and make it normative. Allowing both means:

- Receivers must handle both forms (extra code in every parser)
- Serializers may produce inconsistent output
- Equality comparison of messages becomes ambiguous (is `{}` the same as
  `{"foo": null}`?)
- Swift's `JSONDecoder` and Zig's `std.json` handle these differently:
  - Swift `Codable` with `Optional<T>`: decodes both `null` and missing as
    `nil`, but **encodes** `nil` as key-absent (by default) unless
    `encodeIfPresent` is explicitly used
  - Zig `std.json`: `null` and missing are distinct; `.optional` fields
    parse `null` but missing keys require `@"field" = null` default

### Recommendation

Choose one convention and state it explicitly in Section 7:

| Option | Convention | Pros | Cons |
|--------|-----------|------|------|
| **A: Omit field** | Optional fields MUST be omitted when absent. `null` values MUST NOT appear. | Smaller payloads; unambiguous | Receivers must tolerate missing keys |
| **B: Send null** | Optional fields MUST always be present. Use `null` for absent values. | Fixed schema; simpler parsing in some languages | Larger payloads; verbose |

Either is fine, but the spec must pick one. Option A (omit) is more common in
modern JSON APIs and produces smaller payloads.

---

## Issue 4: Replace custom TCP+TLS transport with SSH tunneling (libssh2)

**Severity**: High (architectural change — eliminates entire transport layer)

Section 2.2 specifies a custom TCP/TLS 1.3 transport for Phase 6 (iOS-to-macOS
over the internet) with:
- Custom port 7822
- Mutual TLS with pre-shared client certificates, or SRP-based password auth
- TLS 1.3 mandatory via `std.crypto.tls`

**This should be replaced with SSH tunneling using libssh2.**

### Rationale

| Aspect | Custom TCP+TLS | SSH tunnel (libssh2) |
|--------|---------------|----------------------|
| Authentication | Must implement mTLS cert management or SRP from scratch | Delegates to SSH: public key, password, certificates — already battle-tested |
| Security audit | Custom TLS implementation is a vulnerability risk | SSH protocol has decades of security auditing |
| Firewall/NAT | Custom port 7822 likely blocked on corporate/school networks | Port 22 is almost universally allowed |
| Key management | Certificate generation, distribution, renewal, storage — all custom | Uses existing `~/.ssh/authorized_keys` and ssh-agent |
| Implementation cost | Large: Zig `std.crypto.tls` + mTLS + SRP | Small: link libssh2, set up port forwarding |
| Transport implementation count | **Two** (Unix socket + TCP/TLS) | **One** (Unix socket only) |

### Architecture with SSH

```
Local client:   App -----> Unix socket -----> daemon
Remote client:  App -> SSH tunnel -> sshd -> Unix socket -> daemon
```

All clients connect via Unix socket from the daemon's perspective. The protocol
remains truly transport-agnostic with a single transport implementation.

- SSH tunnel forwards a local port on the iOS device to the daemon's Unix
  socket on the macOS host
- `SO_PEERCRED` sees sshd's UID (SSH has already authenticated the user)
- FD passing is not available through the tunnel (same limitation as TCP/TLS)
- iOS implementation: bundle libssh2 (or NMSSH, an Objective-C wrapper)

### Coalescing implication: daemon cannot distinguish local from remote clients

With SSH tunneling, the daemon sees **all connections as local Unix sockets**.
It has no way to know that a client is actually connected over the internet
with 50-100ms RTT.

This matters for the adaptive coalescing model (Section 10): a remote client
on a high-latency link should probably use different coalescing parameters
(longer intervals, more aggressive batching) than a local client.

**Recommendation**: Add a field to `ClientDisplayInfo` (or a new message) where
the client declares its transport characteristics:

```json
{
  "transport_type": "local" | "ssh_tunnel",
  "estimated_rtt_ms": 85,
  "bandwidth_hint": "wan"
}
```

The server can use these hints to:
- Adjust coalescing tier thresholds for the remote client
- Set appropriate heartbeat intervals
- Decide whether zstd compression is worthwhile (yes for WAN, no for local)

Without this, the server would apply local-socket coalescing parameters to a
client on a 100ms internet link, which may cause unnecessary backpressure or
suboptimal batching.

### What to change in the spec

1. **Section 2.2**: Replace custom TCP/TLS spec with SSH tunneling via libssh2.
   Remove mTLS, SRP, custom port 7822. Document SSH port forwarding setup.
2. **Section 2.3 (FD passing)**: Note that FD passing is unavailable for
   SSH-tunneled connections (same as before with TCP/TLS).
3. **Heartbeat (Section 5.4)**: `responder_timestamp` becomes less relevant
   since the daemon cannot measure true RTT to the remote device (it only
   sees the local Unix socket hop to sshd). RTT measurement should move to
   the SSH layer or the client should self-report.
4. **ClientDisplayInfo** (doc 02): Add transport type and RTT hint fields.
5. **Adaptive coalescing (Section 10)**: Document that tier selection should
   account for client-reported transport characteristics.

---

## Issue 5: zstd compression tradeoff needs validation

**Severity**: Medium (latency and throughput impact)

Section 3.5 specifies optional zstd compression for payloads >= 256 bytes,
negotiated at handshake. The spec itself acknowledges:

> "Over Unix sockets, the bandwidth savings are negligible compared to the
> CPU cost."

However, the compression decision lacks empirical justification:

### Concerns

1. **Latency cost**: zstd compression/decompression adds CPU time to every
   compressed message. For the Preedit tier (0ms target) and Interactive tier
   (0ms target), any added latency is harmful. The spec says compression is
   "primarily beneficial for FrameUpdate over network transport," but does not
   quantify the CPU cost vs. bandwidth saving tradeoff.

2. **Unix socket**: >1 GB/s throughput (doc 04, Section 8.2). Even worst-case
   FrameUpdate (~38 KB) is trivial at this bandwidth. Compression saves
   bandwidth that is not scarce, while adding latency that is.

3. **SSH tunnel**: If transport moves to SSH (Issue 4), SSH already provides
   built-in compression (`Compression yes` in ssh_config, typically zlib).
   Adding zstd on top of SSH compression is double-compression — worse ratio,
   more CPU, no benefit.

4. **When is compression actually useful?** The only scenario where bandwidth
   is constrained is WAN with limited upload (e.g., mobile data). But SSH
   compression already covers this case.

### Recommendation

Reference investigation needed: check whether tmux and zellij implement
payload compression in their protocols, and if so, what compression algorithm,
at what layer, and what latency/throughput tradeoffs they encountered.

If neither tmux nor zellij compresses at the application protocol layer
(relying instead on transport-level compression like SSH), that would be
strong evidence to simplify: remove application-layer compression from the
spec and rely on SSH compression for WAN scenarios.

If compression is retained, the spec should:
1. Explicitly exclude Preedit and Interactive tier messages from compression
2. Document measured CPU cost vs. bandwidth saving for typical FrameUpdate
3. Address interaction with SSH tunnel compression (no double-compression)

---

## Issue 6: Input language negotiation is missing (conflated with keyboard layout)

**Severity**: High (fundamental gap for server-authoritative IME architecture)

The server-authoritative IME model (libitshell3-ime handles all composition) requires
the server and client to agree on which **input languages** are available and active.
The current spec conflates two distinct concepts under a single `layout_id` and has
**partial runtime switching** but **no handshake-time negotiation**.

### 6a. Input language vs. keyboard layout — two distinct concepts

The spec's "Layout ID" table (doc 04) mixes these together:

| Current layout_id | What it actually represents |
|---|---|
| `0x0000` US QWERTY | **Keyboard layout** (physical key mapping) |
| `0x0001` Korean 2-set | **Input language** (Korean) + **keyboard layout** (2-set) |
| `0x0002` Korean 3-set (390) | **Input language** (Korean) + **keyboard layout** (3-set) |
| `0x0100`-`0x01FF` Reserved Japanese | **Input language** (Japanese) + layout TBD |

These are orthogonal axes:

- **Keyboard layout**: Physical key → character mapping (QWERTY, Dvorak, Colemak,
  JIS kana). Determines what character a keycode produces.
- **Input language / IME mode**: Which composition engine is active (direct input,
  Korean Hangul composition, Japanese romaji→kana→kanji, Chinese pinyin→hanzi).

Example: Japanese can use the same QWERTY layout with romaji input **or** a JIS
kana layout with direct kana input. Same language, different layouts. Conversely,
QWERTY is used for both English and Korean 2-set — same layout, different IME modes.

The spec should separate these two axes. A single `layout_id` cannot cleanly
represent the full matrix of (language × layout) combinations.

### 6b. What exists in the spec (runtime switching only)

- **`active_layout_id` in KeyEvent**: Each key event carries the active layout.
- **InputMethodSwitch (0x0404, C->S)**: Client requests layout change for a pane.
- **InputMethodAck (0x0405, S->C)**: Server confirms and **broadcasts to all attached
  clients** — multi-client notification is covered.
- **PreeditSync**: Carries `active_layout_id` for late-joining clients.
- **Error on unknown layout** (doc 05): Server rejects unknown `layout_id` with error.

### 6c. What is missing

**Handshake layout negotiation is claimed but not defined.** Doc 04 line 131 states:

> "Layout IDs are negotiated during handshake (the server advertises supported
> layouts, the client selects from them)."

However, doc 02 (Handshake) defines **no such mechanism**:
- `ServerHello` has no `supported_input_languages` or `supported_layouts` field.
- `ClientHello` has no `preferred_languages` or `requested_layouts` field.

The claim is an empty promise — the negotiation does not exist in the spec.

**Specific gaps:**

1. **Server does not advertise supported input languages**: The client cannot know
   which languages/layouts the server's IME engine supports. The only way to find
   out is trial-and-error (`InputMethodSwitch` → error response).

2. **Client cannot declare desired input languages at handshake**: No way for the
   client to say "I want Korean and English" when connecting.

3. **Default input language for new panes is undefined**: When a pane is created,
   which language/layout is active? Not specified. Options:
   - Always start with English/QWERTY?
   - Inherit from session's last active language?
   - Use the creating client's preferred language?

4. **Multi-client language change event**: `InputMethodAck` being broadcast to all
   clients covers the notification case. However, there is no mechanism for a
   newly-attached client to receive the **full list of per-pane active languages**
   for all panes in a session (only `PreeditSync` carries it, and only for panes
   with active preedit).

### Recommendation

1. **Separate input language from keyboard layout** in the protocol model. Consider
   a two-level scheme:
   - `input_language`: `"en"`, `"ko"`, `"ja"`, `"zh"` (what IME/composition engine)
   - `keyboard_layout`: `"qwerty"`, `"2set"`, `"3set_390"`, `"jis_kana"` (key mapping)
   - The server advertises supported `(language, layout)` pairs.

2. **Add to `ServerHello`**: `supported_input_methods` listing all available
   (language, layout) combinations the server's IME engine can handle.

3. **Add to `ClientHello`**: `preferred_input_methods` declaring the client's
   desired languages/layouts in preference order.

4. **Define default language for new panes** and document the behavior.

5. **Add per-pane language state to `AttachSessionResponse`**: So newly-attached
   clients receive the active input language for every pane, not just panes with
   active preedit.

### Scope note: supported languages and future roadmap

For the initial implementation, the server's IME engine (libitshell3-ime) supports
**English QWERTY + Korean 2-set only**. The negotiation and IME engine need only
handle these two in v1.

Future input language priority:
1. Japanese romaji (QWERTY + romaji→kana→kanji)
2. Chinese pinyin (QWERTY + pinyin→hanzi)
3. Korean 3-set (390 and Final)

The layout ID table already reserves ranges for Japanese (`0x0100`-`0x01FF`) and
Chinese (`0x0200`-`0x02FF`). The protocol negotiation mechanism should be designed
to accommodate these future additions without breaking changes.

---

## Issue 7: Daemon lifecycle and empty session handling undefined

**Severity**: Medium (affects first-launch and daemon-restart UX)

The protocol defines what happens **after** a connection is established (ClientHello →
ServerHello → Attach/Create), but does not specify behavior for two common scenarios:

### 7a. Daemon not running when client starts

When the client attempts to connect and the daemon is not running (Unix socket does
not exist or connection refused), the spec does not define:

1. **Should the client auto-start the daemon?** tmux does this: `tmux new-session`
   forks the server if none exists. Is this expected behavior for it-shell3?
2. **If auto-start, how?** Fork/exec the daemon binary? Use launchd on macOS?
3. **If not auto-start, what error does the client get?** The transport layer
   returns a connection error (ECONNREFUSED, ENOENT), but the protocol has no
   corresponding error code for "daemon not available." The Error message's error
   codes (Section 6) only cover protocol-level errors after a connection is
   established.
4. **Daemon crash while clients are connected**: Clients detect this via
   socket closure / heartbeat timeout. But is there a recommended reconnection
   strategy? Exponential backoff? Immediate retry?

### 7b. Daemon running but no sessions exist

When `ServerHello.sessions` is an empty array `[]`:

1. **Should the client auto-create a session?** This is the expected first-launch
   behavior (user opens the app, sees a terminal — not an empty session picker).
   tmux and zellij both auto-create on first connect.
2. **Is there an "attach-or-create" shortcut?** tmux has `new-session -A` (attach
   if exists, create if not). The current protocol requires the client to inspect
   `ServerHello.sessions`, then decide between `AttachSessionRequest` and
   `CreateSessionRequest` — a 2-step process.
3. **Default session behavior is not documented**: What should the client do if
   sessions exist but all are fully occupied (e.g., `detach_others=false` and
   multi-client is not desired)?

### Recommendation

1. Define daemon auto-start behavior: specify whether the client binary should
   fork the daemon, or require the daemon to be running (e.g., via launchd).
2. Define the expected client behavior when `sessions` is empty: auto-create
   a default session with standard parameters.
3. Consider adding an `AttachOrCreateRequest` message that combines the
   attach-if-exists / create-if-not pattern into a single message.
4. Document reconnection strategy after daemon crash.

---

## Issue 8: Error message type should be 0x00FF (not 0x0006)

**Severity**: Minor (message type allocation)

The Handshake & Lifecycle range (`0x0001`-`0x00FF`) currently allocates:

| Type | Message |
|------|---------|
| `0x0001` | ClientHello |
| `0x0002` | ServerHello |
| `0x0003` | Heartbeat |
| `0x0004` | HeartbeatAck |
| `0x0005` | Disconnect |
| `0x0006` | Error |
| `0x0007`-`0x00FF` | (unused) |

`Error` is a catch-all message used across all lifecycle states. Placing it at
`0x0006` wastes the `0x0007`-`0x00FE` range — future lifecycle messages (e.g.,
`AttachOrCreateRequest`, daemon status, reconnection) would need to skip over
`Error` or be placed non-contiguously.

### Recommendation

Move `Error` to **`0x00FF`** — the last slot in the Handshake & Lifecycle range.
Reserve `0x0006`-`0x00FE` for future lifecycle messages with semantically
meaningful assignments.

| Type | Message |
|------|---------|
| `0x0001` | ClientHello |
| `0x0002` | ServerHello |
| `0x0003` | Heartbeat |
| `0x0004` | HeartbeatAck |
| `0x0005` | Disconnect |
| `0x0006`-`0x00FE` | Reserved (future lifecycle messages) |
| `0x00FF` | Error |

---

## Carried from v0.1/v0.2 reviews — still not addressed in v0.3

### Issue 5 (v0.1): Cursor style change during CJK composition

No specification exists for whether cursor style should change when CJK preedit is
active. Common UX convention: normal -> bar, composing -> block, committed -> bar.
Needs a decision on whether the server automatically changes `cursor_style` based on
`preedit_active` state, or whether the client decides independently.

### Issue 6 (v0.1): Multi-client window size negotiation contradiction

Potential contradiction between `02-handshake` and `03-session-pane` documents:
- One specifies "minimum (cols, rows)" across all clients (tmux aggressive-resize)
- The other specifies "most recently attached client's dimensions"
Needs verification whether v0.3 docs 02 and 03 have resolved this.
