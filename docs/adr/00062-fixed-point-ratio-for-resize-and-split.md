# 00062. Fixed-Point Signed Ratio Delta for ResizePaneRequest

- Date: 2026-03-30
- Status: Accepted

## Context

The current protocol defines `ResizePaneRequest` with `delta: i32` (cell count)
and `direction: u8` (4-direction enum: right=0, down=1, left=2, up=3). The
daemon must convert this cell delta to a ratio adjustment on the split tree
node, which requires knowing the total cell dimension of the split's coverage
area. This depends on the session-level window size — a value that arrives via a
separate `WindowResize` message.

This creates a circular dependency: resize cannot work correctly until window
dimensions are established. The current implementation hardcodes a divisor of
80.0, producing incorrect ratios for any non-80-column terminal or any vertical
split.

The client already knows the exact ratio when the user drags a divider handle.
Converting from pixel position to cell delta on the client, only for the daemon
to convert cell delta back to a ratio, is a lossy round-trip with rounding
errors at both ends.

The 4-direction enum is also redundant for resize — a split divider moves along
one axis only. The axis (horizontal/vertical) plus the sign of the delta fully
determines the direction.

## Decision

Replace the `ResizePaneRequest` wire format:

**Current:** `direction: u8` (4-direction) + `delta: i32` (cells)

**New:** `orientation: u8` (0=horizontal, 1=vertical) + `delta_ratio: i32`
(signed fixed-point percentage, 2 decimal places, ×10^4)

- `delta_ratio = 625` means +6.25% ratio increase to the first child.
- `delta_ratio = -125` means −1.25% ratio decrease to the first child.
- Scale: value / 10^4 = percentage as decimal. `5000` = 50.00% = 0.5.
- Max intermediate: 1000 cells × 10,000 = 10,000,000 — safe within u32.
- Positive grows the first child; negative shrinks it.

Converting the user's handle drag or keyboard shortcut into a delta percentage
is **client-side responsibility**. The daemon receives the ratio delta directly
and applies it to the split node with integer arithmetic.

The internal split ratio representation may change from `f32` to `u32`
fixed-point as a consequence, but that is an implementation decision — not part
of this protocol ADR.

## Consequences

- **Eliminates the cells-to-ratio conversion problem.** The daemon no longer
  needs window dimensions to process resize requests.
- **Simplifies the protocol.** 4-direction (4 values) becomes orientation (2
  values) + sign. The client does the geometric reasoning; the daemon adjusts a
  number.
- **Client takes on conversion responsibility.** The client must convert pixel
  handle positions to percentage deltas. This is straightforward and the client
  already has the pixel information.
- **Wire format is a breaking change.** `ResizePaneRequest` field names and
  semantics change. Since no client exists yet, this is cost-free.
- **JSON representation is unambiguous.** Fixed-point integers have no
  floating-point representation ambiguity.
- **Requires CTRs** to update protocol spec (ResizePaneRequest/Response) and
  daemon-behavior (resize handling procedure).
