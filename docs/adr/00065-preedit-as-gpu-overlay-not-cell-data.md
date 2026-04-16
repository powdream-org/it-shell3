# 00065. Preedit as GPU Overlay, Not Cell Data

- Date: 2026-04-16
- Status: Accepted

## Context

Design Principle A1 stated: "Preedit is cell data, not metadata." The design
assumed that the daemon calls `ghostty_surface_preedit()` on its Terminal
instance, which injects preedit characters into the terminal's Screen/Page cell
data. Under this model, preedit cells would be exported as part of FlatCell[]
in I/P-frames, and the client would render them as ordinary cells without
knowing what is preedit. This eliminated the need for a separate preedit
channel.

During Plan 9 (Frame Delivery) owner review, this assumption was investigated
and found to be **false**. ghostty's actual preedit architecture:

- `ghostty_surface_preedit()` stores UTF-8 preedit text in
  `renderer_state.preedit` under a mutex
- During `rebuildCells()`, the renderer **skips** normal cells at the
  `preedit_range` and calls `addPreeditCell()` to render preedit glyphs into
  GPU vertex buffers
- **Preedit never enters terminal cell data** (Screen/Page). It exists only in
  the GPU rendering pipeline

This means the daemon cannot embed preedit in FlatCell[] exports. The daemon's
`bulkExport()` produces cell data without preedit, and preedit must be
delivered separately.

PoC 09 (`poc/09-import-plus-preedit/`) verified the correct architecture with
actual Metal GPU rendering and programmatic screenshot capture:

- Channel 1: `importFlatCells()` populates RenderState from FlatCell[] (daemon
  cell data)
- Channel 2: `ghostty_surface_preedit()` injects Korean preedit from real
  libhangul C API
- `rebuildCells()` merges both into one Metal GPU frame

## Decision

Adopt a **two-channel delivery model** where preedit is a separate control
message, not part of frame cell data:

**Channel 1 — Control** (small messages via direct queue, Phase 1 flush):
commands, preedit updates, metadata changes, resize acks.

**Channel 2 — Frame** (FlatCell[] via ring buffer, Phase 2 delivery): terminal
cell data exported by `bulkExport()`, which never contains preedit.

On the client side, the two channels feed independent APIs:

- Frame data → `importFlatCells()` → `RenderState.row_data`
- Preedit → `ghostty_surface_preedit()` → `renderer_state.preedit`

Both merge at render time in `rebuildCells()` → Metal `drawFrame()`.

Retire Design Principle A1 ("Preedit is cell data, not metadata"). Replace
with: **Preedit is a GPU rendering overlay delivered as a control message.**

### Hangul Key Input Flow

```mermaid
sequenceDiagram
    participant U as User
    participant C as Client App
    participant S as Daemon (Socket)
    participant IME as IME Engine<br/>(libhangul)
    participant PTY as PTY
    participant VT as ghostty VT Stream

    U->>C: Press 'r' (Korean 2-set)
    C->>S: KeyInput { key: 'r' }
    S->>IME: processKey('r')
    IME-->>S: ImeResult { preedit: "ㄱ" }
    S->>C: PreeditUpdate { text: "ㄱ" }

    U->>C: Press 'k'
    C->>S: KeyInput { key: 'k' }
    S->>IME: processKey('k')
    IME-->>S: ImeResult { preedit: "가" }
    S->>C: PreeditUpdate { text: "가" }

    U->>C: Press 's'
    C->>S: KeyInput { key: 's' }
    S->>IME: processKey('s')
    IME-->>S: ImeResult { preedit: "간" }
    S->>C: PreeditUpdate { text: "간" }

    U->>C: Press 'k' (triggers commit + new preedit)
    C->>S: KeyInput { key: 'k' }
    S->>IME: processKey('k')
    IME-->>S: ImeResult { commit: "가", preedit: "나" }
    S->>PTY: write("가")
    PTY->>VT: echo "가"
    VT-->>S: pane dirty
    S->>C: PreeditUpdate { text: "나" }
```

### Client Rendering Flow

```mermaid
sequenceDiagram
    participant S as Daemon
    participant SK as Socket
    participant RS as RenderState
    participant PR as renderer_state.preedit
    participant RC as rebuildCells()
    participant GPU as Metal GPU

    S->>SK: RenderStateUpdate { FlatCell[], cursor }
    SK->>RS: importFlatCells()
    Note over RS: row_data populated<br/>(no preedit in cells)

    S->>SK: PreeditUpdate { text: "간" }
    SK->>PR: ghostty_surface_preedit(surface, "간", 3)
    Note over PR: preedit stored under mutex

    Note over RC: Next render frame
    RS->>RC: cell data (row_data)
    PR->>RC: preedit codepoints
    RC->>RC: skip cells at preedit_range<br/>add preedit via addPreeditCell()
    RC->>GPU: vertex buffers
    GPU->>GPU: drawFrame()
    Note over GPU: "hello 간" on screen<br/>한글, Bold Red visible
```

### Two-Channel Wire Architecture

```mermaid
flowchart LR
    subgraph Daemon
        DQ[Direct Queue<br/>control + preedit]
        RB[Ring Buffer<br/>FlatCell per pane]
    end

    subgraph Wire["Unix Socket (same fd)"]
        P1["Phase 1: flush control"]
        P2["Phase 2: deliver frames"]
    end

    subgraph Client
        IFC[importFlatCells]
        GSP[ghostty_surface_preedit]
        RBC[rebuildCells]
        MTL[Metal drawFrame]
    end

    DQ --> P1
    RB --> P2
    P1 --> GSP
    P2 --> IFC
    IFC --> RBC
    GSP --> RBC
    RBC --> MTL
```

## Consequences

**What gets easier:**

- Client rendering is simpler: no need to detect or strip preedit from cell
  data. `importFlatCells()` always receives clean cell data.
- Preedit updates are independent of frame delivery: a preedit change does not
  require a new frame. Lower latency for composition feedback.
- Aligns with ghostty's actual architecture: no impedance mismatch between
  what ghostty does internally and what the protocol assumes.

**What gets harder:**

- Daemon must manage two output paths for IME: committed text → PTY write,
  preedit text → PreeditUpdate broadcast. Previously assumed to be one path.
- `importFlatCells()` must set `cursor.viewport` (not just `cursor.active`)
  for preedit range calculation to work. Discovered via PoC crash.

**What must change:**

- Design Principle A1 retired, replaced with new principle.
- `preedit_overlay.zig` in libitshell3 (daemon-side overlay built on false
  premise) should be removed.
- Protocol and daemon specs need CTRs to align with two-channel model.

**Evidence:**

- PoC 09 screenshots: `poc/09-import-plus-preedit/screenshots/`
- PoC 09 diff: `poc/09-import-plus-preedit/diffs/ghostty-vendor.diff`
