# 00008. Session-as-Tab with No Tab Protocol Entity

- Date: 2026-03-16
- Status: Accepted

## Context

The original design had a three-level hierarchy: Daemon > Session > Tab > Pane
tree. Tabs added an intermediate entity between Session and Pane with unclear
protocol-level semantics.

## Decision

Remove Tab from the protocol. Hierarchy is Daemon > Session > Pane tree. The
client UI presents Sessions as tabs (new tab = CreateSession, close tab =
DestroySession, switch tab = client-local display switch, rename tab =
RenameSession). Tab functionality is fully preserved in the UI; only the
intermediate Tab object is removed from the protocol.

## Consequences

- Simpler protocol: no Tab CRUD messages, no tab-level state.
- Client UI maps Sessions directly to tabs — no translation layer.
- If multi-tab-per-session is ever needed, it would require a protocol
  extension.
