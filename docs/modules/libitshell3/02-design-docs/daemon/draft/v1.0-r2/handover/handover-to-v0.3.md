# Handover: Daemon Design v0.2 to v0.3

**Date**: 2026-03-10
**Author**: owner

---

## Insights and New Perspectives

### Daemon behavior is scattered across three document sets

The protocol docs (6 docs) and IME contract docs (5 docs) contain significant daemon-side behavioral content — 20 topics from protocol, 9 from IME, with 8 overlapping. This happened because daemon design docs didn't exist when those documents were written. v0.3 is the consolidation version: absorb all daemon behavior into daemon docs, file cross-team requests for protocol and IME to slim down.

### core/ dependency invariant must be enforced by type placement

The v0.2 verification found that `Session` (core/) holds `pane_slots: [MAX_PANES]?*Pane` where `Pane` is in server/ — creating a reverse dependency. The fix is `SessionEntry` in server/ that bundles `Session` + `pane_slots`, keeping core/ pure. This pattern (pure state types in core/, resource-owning types in server/, bundled via a server-side wrapper) should be the standard for any future state that straddles the boundary.

### Pane belongs in server/ because of what it owns, not what it is

Pane's placement in server/ is driven by its fields (`*ghostty.Terminal`, `*ghostty.RenderState`, `pty_fd`, `child_pid`), not by its role in the session hierarchy. If Pane ever loses its ghostty/OS dependencies (unlikely), it could move to core/. The placement decision is about dependencies, not domain modeling.

---

## Design Philosophy

### Each document set owns its domain exclusively

After v0.3, the ownership boundaries should be:
- **Protocol docs**: wire format, message types, error codes, state machines, capability negotiation
- **IME contract docs**: ImeEngine vtable API, type definitions, composition rules, memory ownership
- **Daemon docs**: everything else — process lifecycle, key routing, ghostty integration, flow control, multi-client management, session persistence, IME engine lifecycle

No behavioral descriptions ("the server MUST do X when Y") should remain in protocol or IME docs. Those docs define "what goes on the wire" and "what the engine API is" respectively.

### SessionEntry pattern: bundle state with its resources

`SessionEntry { session: Session, pane_slots: [MAX_PANES]?Pane }` in server/ cleanly separates pure state (core/) from resource ownership (server/) while keeping them co-located for efficient access. This is the Zig equivalent of composition over inheritance for managing the core/server boundary.

---

## Owner Priorities

### 1. Content migration is the primary v0.3 goal

Absorb P1-P20 (protocol) and I1-I9 (IME) into daemon docs. See review note 04 for the full inventory and deduplication map. This is a full-team effort — likely requiring a new doc (04?) for flow control, multi-client, and IME integration topics.

### 2. SessionEntry introduction (review note 03)

Apply the pane_slots design change: remove from Session, introduce SessionEntry in server/, update all affected docs. This is architectural — requires careful propagation through docs 01-03 and the v0.1 resolution doc.

### 3. Mechanical fixes (review notes 01-02)

SplitNode remnants and pty_fd naming — straightforward text replacements.

### 4. AGENTS.md cleanup

Remove version conflict handling procedures from AGENTS.md line 54 after daemon docs cover them. Keep high-level summary only.

### 5. Coordination with protocol v0.11 and IME v0.8

Cross-team requests filed at:
- `protocol/v0.10/cross-team-requests/01-daemon-behavior-extraction.md` (23 changes)
- `ime-contract/v0.7/cross-team-requests/01-daemon-behavior-extraction.md` (9 changes)

Extraction from protocol/IME MUST happen simultaneously with daemon v0.3 absorption. The three revisions should be coordinated — possibly as a single multi-target revision cycle.

---

## New Conventions and Procedures

### Cross-team request placement

Convention updated (`docs/conventions/artifacts/documents/07-cross-team-requests.md`): cross-team requests go in target team's **latest (current) version directory** (same convention as handover). Target team's handover to v\<current+1\> MUST mention incoming cross-team requests.

---

## Pre-Discussion Research Tasks

### 1. Document structure for absorbed content

Before writing, decide how to organize 31 absorbed topics into daemon docs. Current docs:
- 01-internal-architecture (module decomposition, event loop, state tree, ghostty integration)
- 02-integration-boundaries (module boundary rules, API surfaces)
- 03-lifecycle-and-connections (daemon/session/pane/client lifecycle)

Candidates for a new doc 04: flow control & multi-client management (ring buffer, health escalation, resize policy, coalescing). Alternatively, these could extend doc 03.

### 2. Deduplication strategy for 8 overlapping topics

8 topics are described in 2-3 sources with slightly different emphasis. Before writing, read all source descriptions for each overlapping topic and produce a single authoritative version. Key overlaps: preedit flush on focus change (3 sources), per-session engine lifecycle (2 sources), session persistence IME state (2 sources).

### 3. AGENTS.md daemon lifecycle paragraph

Read current AGENTS.md line 54 and draft a replacement that keeps only: bundled binary location, LaunchAgent for local, fork+exec for remote. All procedural details (kill & restart, protocol negotiation failure) should reference daemon docs.
