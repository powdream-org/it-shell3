# Handover: IME Interface Contract v0.7 to v0.8

**Date**: 2026-03-10
**Author**: owner

---

## Insights and New Perspectives

### The IME contract contains daemon architecture

During the daemon v0.2 review cycle, we discovered that ~40% of the IME contract content (by line count) describes daemon-side behavior rather than IME engine API/contract. This happened because the daemon design docs didn't exist when the IME contract was written. Now that daemon docs exist, this content should migrate.

The clearest example is `04-ghostty-integration.md` — all 300+ lines describe how the daemon uses ghostty APIs to consume ImeResult. The IME engine has no interaction with ghostty whatsoever. This entire section belongs in daemon docs.

### The contract should define "what", not "when"

The vtable methods (activate, deactivate, flush, processKey) have clear behavioral contracts — what the engine does when called. But the current docs also describe when the daemon calls them (session focus, pane focus change, etc.). The "when" is daemon lifecycle logic, not engine API contract. Separating these concerns makes both docs cleaner and avoids the current situation where a daemon design change requires updating the IME contract.

---

## Design Philosophy

### IME contract = engine API boundary only

The contract's scope should be: type definitions (KeyEvent, ImeResult), vtable method signatures and behavioral contracts, composition rules, memory ownership, and extensibility. Everything else — key routing, ghostty integration, session lifecycle, persistence procedures — belongs in daemon docs.

---

## Owner Priorities

### Cross-team request: daemon behavior extraction

The daemon team (v0.2) filed a cross-team request at `v0.7/cross-team-requests/01-daemon-behavior-extraction.md` requesting removal of daemon-side behavioral descriptions from IME contract docs. 9 specific changes across 01-overview, 02-types, 03-engine-interface, 04-ghostty-integration, 05-extensibility, and design-resolutions. These changes MUST be applied simultaneously with daemon v0.3 absorbing the same content. See the cross-team request for the full change list.

This is the highest priority for v0.8. The contract should become leaner and more focused.

---

## New Conventions and Procedures

None introduced in this session.

---

## Pre-Discussion Research Tasks

### Scope audit before extraction

Before removing daemon content, the team should read daemon v0.3's corresponding sections to verify every migrated topic is properly received. Do not remove content from the IME contract until the daemon doc covers it.
