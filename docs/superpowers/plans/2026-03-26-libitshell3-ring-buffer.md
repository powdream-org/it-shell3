# libitshell3 Ring Buffer + Frame Delivery Implementation Plan (v2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use the `/implementation` skill
> to execute this plan. The implementation team is defined in
> `.claude/agents/impl-team/`.
>
> **CRITICAL**: The design spec is the architectural authority. This plan is a
> task breakdown only. When this plan's descriptions conflict with the design
> spec, **the spec wins**. Verify every public API against the spec section
> cited. Do NOT treat any description in this plan as a substitute for reading
> the spec.

**Goal:** Redesign and reimplement the ring buffer delivery path to match the
design spec's zero-copy, byte-granular cursor model.

**Architecture (per spec §4.1-4.11):**

The ring buffer is a **byte ring** — a contiguous circular byte buffer. Frames
are written as length-prefixed entries, but delivery and cursor advancement are
**byte-granular**, not frame-granular. The delivery path constructs iovecs from
cursor position to write position (spanning all pending bytes, potentially
multiple frames), calls `writev()` once, and advances the cursor by the number
of bytes the kernel accepted. No intermediate buffer copies.

Key spec requirements the previous implementation got wrong:

1. `peekFrame` copied into a caller buffer — spec §4.6 says `sendv(iovecs)` for
   zero-copy delivery from ring memory
2. Delivery was frame-by-frame in a loop — spec §5.4 pseudocode shows one
   `sendv()` call spanning all pending data, cursor advances by `n` bytes
3. `ring_frame_sent` tracked partial frame state — spec §5.4 just advances
   cursor by bytes sent, next call resumes from new cursor position

**Tech Stack:** Zig 0.15+, libitshell3 (core/, ghostty/), libitshell3-protocol

**Spec (authoritative — READ THESE for API design, not this plan):**

- `daemon-architecture/draft/v1.0-r8/02-state-and-types.md` §4
- `daemon-behavior/draft/v1.0-r8/03-policies-and-procedures.md` §4-5
- `daemon-behavior/draft/v1.0-r8/impl-constraints/policies.md` §5.3-5.5

---

## Team Composition

| Role        | Agent Definition                          | Model  |
| ----------- | ----------------------------------------- | ------ |
| Implementer | `.claude/agents/impl-team/implementer.md` | sonnet |
| QA Reviewer | `.claude/agents/impl-team/qa-reviewer.md` | opus   |

---

## Scope

Redesign of existing Plan 4 files. Only 3 files change; the rest are correct:

| File                               | Action               | Reason                                                                    |
| ---------------------------------- | -------------------- | ------------------------------------------------------------------------- |
| `ring_buffer.zig`                  | **Rewrite read API** | Replace `peekFrame(buf)` → iovec API returning slices into ring memory    |
| `client_writer.zig`                | **Rewrite delivery** | Replace `write(fd, buf)` → `writev(fd, iovecs)` with byte-granular cursor |
| `ring_buffer_integration_test.zig` | **Rewrite tests**    | Spec-driven tests, each citing spec section                               |
| `frame_serializer.zig`             | Unchanged            | Writes to ring correctly                                                  |
| `direct_queue.zig`                 | Unchanged            | Priority 1 channel correct                                                |
| `pane_delivery.zig`                | Unchanged            | Ring lifecycle correct                                                    |
| `event_loop.zig`                   | Unchanged            | Stubs correct                                                             |
| `pty_read.zig`                     | Unchanged            | Dirty marking correct                                                     |

---

## Task Dependency Graph

```
Task 1 (ring_buffer.zig — byte-granular iovec API)
  └──► Task 2 (client_writer.zig — writev + byte-granular cursor)
         └──► Task 3 (spec-driven integration tests)
```

---

### Task 1: Ring Buffer — Byte-Granular Iovec API

**Files:** Modify `modules/libitshell3/src/server/ring_buffer.zig`

**Spec reference:** Read §4.5 (cursor model), §4.6 (sendv delivery), §5.4
(byte-granular advancement pseudocode) BEFORE writing any code.

**What to change:**

The ring buffer's read API must support the delivery model in spec §5.4:

1. Construct iovecs covering **all pending bytes** from cursor to write_pos
2. Caller does `writev(fd, iovecs)` — kernel reads directly from ring memory
3. Cursor advances by `n` bytes (return value of `writev`)

The API should return iovecs pointing into `self.buf`. When the pending range
doesn't wrap: 1 iovec. When it wraps: 2 iovecs (tail segment + head segment).

Remove `peekFrame` and `advancePastFrame`. Replace with:

- A function that returns iovecs for all pending bytes (per spec §5.4)
- A function that advances cursor by N bytes (per spec §5.4: "advance client
  cursor by n bytes")

`RingCursor` must include the `last_i_frame` field per spec §4.5. The update
semantics are a spec gap (logged below), but the field must exist.

Keep frame-level operations that are still needed:

- `writeFrame` — write a frame to the ring (unchanged)
- `seekToLatestIFrame` — for slow client recovery (spec §4.8)
- `hasValidIFrame` — ring invariant check
- Frame index tracking (`FrameMeta`, `frame_count`, `latest_i_frame_idx`) —
  needed for I-frame seeking, not for delivery

**Spec ambiguity to flag (log in TODO.md Spec Gap Log):**

- `last_i_frame` field defined in §4.5 but update semantics never specified —
  when exactly is it updated? After full I-frame delivery? On seek?
- Ring cursor lag formula for §4.4 smooth degradation never defined

**Inline unit tests must verify:**

- Iovecs point into `self.buf` address range (zero-copy proof)
- Non-wrapping range → 1 iovec; wrapping range → 2 iovecs
- Iovec byte lengths sum to `available()` bytes
- `advanceCursor(n)` advances by exactly n bytes
- Partial advancement (n < available) leaves correct remaining bytes
- `advanceCursor(0)` is a no-op; `advanceCursor(n > available)` is defined
  behavior (assert or clamp)
- All existing behavioral tests adapted (overwrite detection, I-frame seeking)

- [ ] Step 1: Read spec §4.5, §4.6, §5.4 — understand byte-granular model
- [ ] Step 2: Remove `peekFrame` and frame-granular `advancePastFrame`
- [ ] Step 3: Implement iovec API per spec §5.4
- [ ] Step 4: Implement byte-granular `advanceCursor`
- [ ] Step 5: Update all inline unit tests
- [ ] Step 6: `mise run test:macos` passes
- [ ] Step 7: `mise run test:macos:release-safe` passes

---

### Task 2: Client Writer — writev with Byte-Granular Cursor

**Files:** Modify `modules/libitshell3/src/server/client_writer.zig`

**Spec reference:** Read §4.4 (two-channel priority), §5.4 (delivery pseudocode)
BEFORE writing any code.

**What to change:**

The `writePending` delivery path must match the spec §5.4 pseudocode exactly:

1. Phase 1: Drain direct queue completely (unchanged — already correct)
2. Phase 2: Get iovecs for all pending ring bytes, call `writev(fd, iovecs)`,
   advance cursor by return value

This eliminates:

- The 128KB `frame_buf` stack allocation
- The `ring_frame_sent` partial frame tracker
- The frame-by-frame `while` loop

The entire ring delivery becomes: get iovecs → `writev()` → handle result. The
result handling must match the spec §5.4 pseudocode exactly — three branches:

1. `.bytes_written(n)` → advance cursor by n bytes. If cursor == write_pos:
   return `fully_caught_up`. Else: return `more_pending`.
2. `.would_block` → cursor stays at current position. Return `would_block`.
3. `.peer_closed` → return `peer_closed` (caller handles disconnect).

Partial writes are handled by the cursor position — next call gets iovecs from
the new position. No `ring_frame_sent` tracking needed.

**Inline unit tests must verify:**

- `hasPending` reflects both channels correctly (unchanged tests)
- No large stack buffers in struct or `writePending`
- Partial cursor advancement state is just the cursor position (no extra state)
- `WriteResult` enum has variants matching spec §5.4 three-branch model

- [ ] Step 1: Read spec §4.4 and §5.4
- [ ] Step 2: Replace frame-by-frame loop with single writev path
- [ ] Step 3: Remove `ring_frame_sent`, `frame_buf`
- [ ] Step 4: Update inline tests
- [ ] Step 5: `mise run test:macos` passes

---

### Task 3: Spec-Driven Integration Tests

**Files:** Rewrite
`modules/libitshell3/src/server/ring_buffer_integration_test.zig`

**Spec reference:** All of §4.1-4.11, §5.3-5.5

**Test design principle:** Each test cites the spec section it verifies. Tests
are derived from spec requirements. A test that proves "the code does what the
code does" is not a spec compliance test.

**Required tests (each citing spec section):**

1. **§4.1 — O(1) memory + write-once**: Write one frame, create multiple
   cursors. All cursors' iovecs point into the same ring backing memory (pointer
   address range proof). Frame data exists once in ring, not copied per cursor.
2. **§4.3 — Wire format in ring**: Data read via iovecs is a valid protocol
   message (decode Header + FrameHeader from iovec bytes)
3. **§4.4 — Two-channel priority**: Direct queue fully drained before any ring
   data is delivered. Verify ordering invariant.
4. **§4.5 — Independent cursors**: Two cursors at different positions have
   different `available()` counts and different iovec ranges. Advancing cursor A
   does NOT affect cursor B's position or available count.
5. **§4.6 — Zero-copy delivery**: Iovecs returned by ring buffer point into
   `ring.buf` address range (verify via `@intFromPtr`), not into any
   intermediate buffer
6. **§4.6 — Wrap-around iovecs + zero-copy**: Pending bytes spanning ring
   boundary produce 2 iovecs. BOTH iovecs point into `ring.buf` address range
   (zero-copy proof for wrapped case). Concatenation equals original data.
7. **§5.4 — Byte-granular cursor**: Advance cursor by partial byte count (less
   than total available), verify remaining iovecs start at correct byte position
   in ring memory
8. **§5.4 — Full delivery**: Advance cursor by total available bytes, verify
   `available() == 0` and iovec function returns no data
9. **§5.4 — would_block semantics**: After a `would_block` result, cursor
   position is unchanged; next iovec call returns same data
10. **§4.8 — Slow client recovery**: Overwritten cursor seeks to latest I-frame
    position, can read from there via iovecs
11. **§4.9 — I-frame no-op when unchanged**: When I-frame timer fires with no
    changes since last I-frame, no frame is written to ring (spec: "no frame is
    written to the ring"). Empty P-frame (no dirty rows) also returns null.
12. **§4.11 — Multi-client ring read**: Independent cursor positions produce
    independent iovec ranges from same ring backing
13. **Pane delivery lifecycle**: Ring buffer allocated/freed correctly via
    `SessionDeliveryState`
14. **Edge cases**: `advanceCursor(0)` is no-op; behavior defined for edge
    conditions

- [ ] Step 1: Read spec §4.1-4.11 and §5.3-5.5 thoroughly
- [ ] Step 2: Delete existing integration tests
- [ ] Step 3: Write spec-driven tests (each citing section in test name)
- [ ] Step 4: `mise run test:macos` passes
- [ ] Step 5: `mise run test:macos:release-safe` passes

---

## Spec Ambiguities to Log

These should be added to `TODO.md` Spec Gap Log during implementation:

1. `last_i_frame` field (§4.5) — defined but update semantics unspecified
2. Ring cursor lag formula (§4.4) — 50%/75%/90% thresholds reference "ring
   capacity" but lag calculation not defined
3. FrameEntry type (§4.3) — referenced as "header + payload bytes" but no struct
   definition
4. I-frame timer vs coalescing timer interaction (§4.9) — independence stated
   but reset behavior ambiguous
5. §4.3 says "memcpy from ring slot to send buffer" while §4.6 says "zero-copy
   delivery" — §4.6/§5.4 pseudocode is normative

---

## Post-Implementation Notes

**Deferred to later plans (unchanged):**

- Coalescing timer logic (Plan 9)
- IME preedit overlay (Plan 5)
- Session attachment tracking (Plan 7)
- EVFILT_WRITE management (Plan 9)
- Ring I-frame invariant enforcement — write-time check (Plan 9, requires
  knowing when the next frame would overwrite the only I-frame)
- Smooth degradation thresholds (Plan 9)
