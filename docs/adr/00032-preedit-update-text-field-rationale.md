# 00032. Preedit Message Simplification

- Date: 2026-03-20
- Status: Accepted

## Context

Early drafts of the CJK preedit protocol included a richer `PreeditUpdate`
message that carried fields beyond the composition text itself:

- `composition_state` — an enum or string encoding the current IME state machine
  phase (e.g., `"composing"`, `"candidate_selection"`)
- `cursor_col` and `cursor_row` — the terminal grid coordinates of the preedit
  cursor
- `width` — the display width (in columns) of the current preedit text
- `frame_type=2` — a dedicated preedit frame type in `FrameUpdate`, separate
  from the normal I/P-frame path

These fields reflected an early design assumption: that the client would
participate in preedit rendering by receiving metadata and drawing preedit cells
using a dedicated code path, separate from the normal cell rendering pipeline.

After adopting the single-path rendering model — where all preedit rendering
goes through cell data in I/P-frames via the ring buffer, with the server
injecting preedit cells before serializing each frame — these fields became
either redundant or incorrect in their placement.

## Decision

The `PreeditUpdate` (0x0401) message is reduced to three fields: `pane_id`,
`preedit_session_id`, and `text`.

### `composition_state` removed

Preedit lifecycle is fully expressed by the `PreeditStart` / `PreeditUpdate` /
`PreeditEnd` message sequence. A separate state field adds no information the
client cannot derive from message ordering. The only state the client needs to
track is whether a composition session is active (signaled by `PreeditStart`) or
ended (signaled by `PreeditEnd`).

### `cursor_col`, `cursor_row`, `width` removed

These are server-internal values. Preedit cursor position and cell width are
computed server-side when preedit cells are injected into the frame cell data.
The client receives the correct position through the cell grid in the I-frame or
P-frame — there is no need for a separate coordinate channel. During resize,
cursor position can change due to terminal reflow; the server handles this by
recomputing coordinates before the next I-frame. Sending coordinates in
`PreeditUpdate` would require re-sending them after every resize, creating a
redundant coordinate sync problem.

### `frame_type=2` (preedit frame) removed

The single-path rendering model eliminates the need for a dedicated preedit
frame type. Preedit cells are injected into normal I-frames and P-frames. All
clients — renderers, observers, readonly clients — receive preedit through the
same cell data path as terminal content. A client that only renders does not
need to distinguish preedit frames from normal frames.

### `text` retained

The raw composition string is needed by consumers other than the renderer.
Observer clients may display a "Client A composing X" indicator using `text`
from `PreeditUpdate`. Session managers need to know what is being composed for
coordination and logging. `PreeditEnd.committed_text` uses the same text for
audit. This is not a DRY violation — cell data and `PreeditUpdate` serve
different consumers: the rendering pipeline consumes cell data; session managers
and observers consume `text`.

The final `PreeditUpdate` payload is:

```json
{
  "pane_id": 1,
  "preedit_session_id": 42,
  "text": "한"
}
```

## Consequences

- The `PreeditUpdate` message is lifecycle/metadata only. No rendering logic may
  depend on it. Preedit rendering correctness is entirely determined by cell
  data in I/P-frames.
- Clients that only render terminal content can ignore all `0x04xx` messages
  entirely. The `"preedit"` capability controls delivery of these messages and
  may be omitted by render-only clients.
- The coordinate sync problem is eliminated. There is no need to re-deliver
  cursor coordinates after resize, reflow, or any other geometry change — the
  server injects updated coordinates into the next I-frame automatically.
- Observer UIs (composition indicators, session monitors) receive the
  composition string via `text` without needing to parse cell data.
- Implementations that previously used `composition_state`, cursor coordinates,
  or a dedicated preedit frame type must be updated to use cell data for
  rendering and the `PreeditStart`/`PreeditEnd` lifecycle messages for state
  tracking.
