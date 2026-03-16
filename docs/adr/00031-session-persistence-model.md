# 00031. Session Persistence Model (Hybrid Memory + JSON Snapshots)

- Date: 2026-03-16
- Status: Superseded by ADR 00036

## Context

The daemon must persist session state so that sessions survive daemon restarts
(planned upgrades, crashes, system reboots). Two broad approaches exist: (1)
write-ahead log (WAL) that journals every state change to disk, or (2) periodic
snapshots of in-memory state. A WAL provides durability down to individual
operations but adds write amplification and recovery complexity. Periodic
snapshots are simpler but accept bounded data loss (up to one snapshot
interval).

## Decision

**Hybrid persistence: live state in memory, periodic JSON snapshots to disk.**
The daemon holds all live session state in memory and periodically writes a
complete snapshot to disk in JSON format. The auto-save interval is 8 seconds,
following cmux's proven model. Clients can also trigger explicit snapshots via
`SnapshotRequest` / `SnapshotResponse` messages.

JSON was chosen over a binary snapshot format for debuggability -- operators can
inspect and manually edit snapshots when diagnosing issues. The 8-second
interval balances durability (worst-case loss of 8 seconds of state) against
disk I/O overhead.

## Consequences

- Simple implementation: no WAL infrastructure, no replay logic. Snapshot is a
  single atomic file write (write-to-temp + rename).
- Worst-case data loss on unclean shutdown is bounded by the snapshot interval
  (8 seconds of session state changes).
- JSON format enables manual inspection and recovery tooling without custom
  parsers.
- Explicit snapshot support (`SnapshotRequest`) lets clients force a sync before
  known risky operations (e.g., before triggering a daemon upgrade).
