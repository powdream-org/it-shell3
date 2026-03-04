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
