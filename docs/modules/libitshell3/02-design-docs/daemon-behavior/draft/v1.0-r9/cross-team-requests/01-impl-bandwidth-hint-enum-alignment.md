# Replace numeric bandwidth threshold with enum-based policy

- **Date**: 2026-04-04
- **Source team**: libitshell3 implementation (Plan 9)
- **Source version**: daemon-behavior draft/v1.0-r9
- **Source resolution**: Plan 9 Step 8.5 triage, issue R1-004
- **Target docs**: daemon-behavior 03-policies-and-procedures.md
- **Status**: open

---

## Context

Section 5.5 (WAN Coalescing Adjustments) uses "Below 1 Mbps: force Tier 3 for
all non-preedit output" as the policy trigger for `bandwidth_hint`. However,
`bandwidth_hint` is defined in the protocol spec (server-client-protocols
06-flow-control-and-auxiliary.md) as a categorical enum with values `local`,
`lan`, `wan`, `cellular` — not a numeric value.

The "1 Mbps" language was introduced in daemon spec v1.0-r3
(`04-runtime-policies.md` line 244) and carried forward verbatim through every
subsequent revision. The owner confirms the intent was always network-type-based
policy, not a numeric threshold. The numeric wording creates a spec-vs-spec
inconsistency: daemon-behavior assumes numeric bandwidth information that the
protocol wire format does not provide.

## Required Changes

1. **Section 5.5, WAN Coalescing Adjustments table** — Replace the
   `bandwidth_hint` row:
   - **Current**:
     `| bandwidth_hint | Below 1 Mbps: force Tier 3 for all
     non-preedit output |`
   - **Should be**:
     `| bandwidth_hint | cellular or wan: force Tier 3 for all
     non-preedit output |`
   - **Rationale**: Aligns with the protocol spec's enum definition. Both
     `cellular` (typically <1 Mbps) and `wan` (variable bandwidth, potentially
     constrained) trigger conservative throttling.

## Summary Table

| Target Doc                    | Section/Message            | Change Type | Source Resolution    |
| ----------------------------- | -------------------------- | ----------- | -------------------- |
| 03-policies-and-procedures.md | Section 5.5 bandwidth_hint | Update      | Plan 9 R1-004 triage |
