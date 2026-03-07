# Handover: Input Method Identifier Consensus (Protocol v0.5)

> **Date**: 2026-03-05
> **Participants**: protocol-architect, ime-expert, cjk-specialist
> **Scope**: Protocol docs v0.5 (docs 01-06)

## 1. Summary

This session unified input method identification across the protocol and IME contract.
The previous representation used a split `LanguageId` enum + `layout_id` pair. This has
been replaced with a single canonical `input_method` string that flows unchanged from
client to server to IME engine constructor.

## 2. The 10-Point Identifier Consensus

### Decision 1: Single canonical string identifier

The protocol uses a single `input_method` string (e.g., `"direct"`, `"korean_2set"`)
as the ONLY representation crossing component boundaries. No enums, no numeric IDs.

### Decision 2: Two-axis design (input_method + keyboard_layout)

`input_method` (composition engine variant) and `keyboard_layout` (physical key
arrangement, e.g., `"qwerty"`, `"azerty"`) are orthogonal per-pane fields. They are
never merged into a single string (e.g., no `"direct_azerty"`).

### Decision 3: Naming convention

Format: `{language}_{human_readable_variant}`. Engine-agnostic -- does not leak
libhangul internal IDs into protocol strings.

- `"direct"` -- no composition
- `"korean_2set"` -- not `"ko_2"`
- `"korean_3set_final"` -- not `"ko_3f"`
- `"korean_ahnmatae"` -- not `"ko_ahn"`

### Decision 4: LanguageId removed from public API

The `LanguageId` enum is removed from the IME contract's public interface. Replaced by
`[]const u8` string. A private `EngineMode` enum (`direct`, `composing`) is kept
internally for hot-path dispatch.

### Decision 5: Canonical registry lives in IME contract

The single source of truth for valid `input_method` strings is IME Interface Contract,
Section 3.7 (HangulImeEngine). Protocol docs cross-reference it; they never duplicate it.

### Decision 6: Engine owns the mapping

The `HangulImeEngine.libhangulKeyboardId()` function is the sole translation point
between canonical protocol strings and libhangul keyboard IDs. No cross-component
mapping table exists.

### Decision 7: vtable uses string-based methods

- `getActiveInputMethod() -> []const u8`
- `setActiveInputMethod(method: []const u8) -> error{UnsupportedInputMethod}!ImeResult`

### Decision 8: Error union for unsupported input methods

`setActiveInputMethod()` returns `error.UnsupportedInputMethod` for unrecognized
strings. The server MUST only send strings from the canonical registry.

### Decision 9: Session persistence uses single field

One field per pane: `input_method` (string). Replaces old `active_language` +
`layout_id` pair.

### Decision 10: Composition state prefix is separate from identifier prefix

Composition states use `ko_` prefix (e.g., `"ko_leading_jamo"`) -- engine-internal
runtime state. Input method identifiers use `korean_` prefix (e.g., `"korean_2set"`)
-- protocol-visible names. These are intentionally different.

## 3. Canonical Input Method Registry

Authoritative source: IME Interface Contract v0.4, Section 3.7.

| Canonical string | libhangul keyboard ID | Description |
|---|---|---|
| `"direct"` | N/A | No composition -- direct passthrough |
| `"korean_2set"` | `"2"` | Dubeolsik (standard, most common) |
| `"korean_2set_old"` | `"2y"` | Dubeolsik with historical jamo |
| `"korean_3set_dubeol"` | `"32"` | Sebeolsik mapped to 2-set positions |
| `"korean_3set_390"` | `"39"` | Sebeolsik 390 |
| `"korean_3set_final"` | `"3f"` | Sebeolsik Final |
| `"korean_3set_noshift"` | `"3s"` | Sebeolsik Noshift |
| `"korean_3set_old"` | `"3y"` | Sebeolsik with historical jamo |
| `"korean_romaja"` | `"ro"` | Latin-to-Hangul transliteration |
| `"korean_ahnmatae"` | `"ahn"` | Ahnmatae ergonomic layout |

v1 ships `"direct"` + `"korean_2set"` only. The full table establishes the naming
convention.

### Normative rule

The canonical `input_method` string flows unchanged to the IME engine constructor.
The engine owns the sole translation to engine-internal types. Protocol docs do not
maintain a separate mapping table.

## 4. Changes Applied to Protocol v0.5

### Doc 03 (Session and Pane Management)

- **Section 8 (Input Method State)**: Updated session restore reference to use single
  canonical `input_method` string instead of `layout_id` + `active_language` pair.
- **Changelog**: Added v0.5 entry documenting the change.

### Doc 04 (Input Forwarding and RenderState)

- Applied by cjk-specialist. Already used string-based identifiers since v0.3.
  Cross-verified clean.

### Doc 05 (CJK Preedit Protocol)

- **Section 4.3**: Removed cross-component mapping table (which had the
  `"korean_3set_390" -> "3f"` bug; correct ID is `"39"`). Replaced with normative
  rule and cross-reference to IME Interface Contract, Section 3.7.
- **Changelog**: Added v0.5 entry documenting mapping table removal and bug fix.
- Additional edits by cjk-specialist for `ko_` prefix consistency and
  `composition_state` updates.

### Doc 06 (Flow Control and Auxiliary)

- **Section 4.4 (RestoreSessionResponse)**: Replaced 3-step IME initialization using
  `layout_id` + `setActiveLanguage()` with single-step initialization using saved
  `input_method` string. The engine constructor decomposes the string internally.
- **Changelog**: Added two v0.5 entries (RestoreSession update and identifier
  unification).

### Docs 01 and 02

- No changes needed. Already used `input_method` / `active_input_method` convention.

## 5. Verification Status

Cross-document verification completed by protocol-architect and cjk-specialist.
All checks pass:

1. No functional references to stale `LanguageId`, `layout_id`, `active_language`,
   `setActiveLanguage`, or `getActiveLanguage` remain. Surviving occurrences are in
   changelog entries (historical records -- correct).
2. All JSON examples use `"korean_2set"` naming convention consistently.
3. Mapping table exists only in IME contract Section 3.7; protocol docs cross-reference it.
4. Cross-references between protocol docs and IME contract are correct.
5. Session persistence uses single `input_method` field everywhere.
6. `composition_state` uses `ko_` prefix consistently.

## 6. Open Items for Next Session

No blocking open items from the identifier consensus work.

**Previously identified open items** (from v0.4 cross-review, unrelated to this session):

1. **SSH vs TLS for network transport**: Doc 01 mentions "TCP + TLS 1.3 port 7822" but
   the team settled on SSH tunneling. Rationale section could be made more explicit.
2. **v0.6 production**: If the team decides to cut a new version incorporating all v0.5
   changes, the changelog entries and version headers will need updating.

## 7. File Locations

| Document | Path |
|----------|------|
| Protocol doc 01 | `docs/libitshell3/02-design-docs/server-client-protocols/v0.5/01-protocol-overview.md` |
| Protocol doc 02 | `docs/libitshell3/02-design-docs/server-client-protocols/v0.5/02-handshake-capability-negotiation.md` |
| Protocol doc 03 | `docs/libitshell3/02-design-docs/server-client-protocols/v0.5/03-session-pane-management.md` |
| Protocol doc 04 | `docs/libitshell3/02-design-docs/server-client-protocols/v0.5/04-input-and-renderstate.md` |
| Protocol doc 05 | `docs/libitshell3/02-design-docs/server-client-protocols/v0.5/05-cjk-preedit-protocol.md` |
| Protocol doc 06 | `docs/libitshell3/02-design-docs/server-client-protocols/v0.5/06-flow-control-and-auxiliary.md` |
| IME contract v0.4 | `docs/libitshell3-ime/02-design-docs/interface-contract/v0.4/01-interface-contract.md` |
