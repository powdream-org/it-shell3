# Handover: Identifier Consensus Changes Applied to IME Contract v0.4

> **Date**: 2026-03-05
> **Session participants**: protocol-architect, ime-expert, cjk-specialist (team-lead facilitated)
> **Status**: All changes applied and verified

## 1. Summary

This session resolved the inconsistency between the protocol's single-string input method identifiers (e.g., `"korean_2set"`) and the IME contract's two-field model (`LanguageId` enum + `layout_id` string). The team reached unanimous consensus on 10 decisions, which were then applied to the IME contract v0.4.

## 2. Consensus Decisions (10 points, unanimous)

1. **Single canonical string**: `input_method: []const u8` used everywhere — protocol wire, IME contract API, session persistence. No pair model.

2. **Naming convention**: `{language}_{human_readable_variant}` (e.g., `"korean_2set"`, `"korean_3set_390"`). NOT engine-native IDs like `"ko_2"`. `"direct"` is the special case with no prefix.

3. **LanguageId enum removed from public API**: The engine uses a private `EngineMode` enum internally for hot-path dispatch. No public enum.

4. **layout_id removed from public API**: The engine owns the mapping from protocol string to libhangul keyboard ID via `libhangulKeyboardId()`.

5. **Vtable methods renamed**: `getActiveLanguage()` -> `getActiveInputMethod()`, `setActiveLanguage()` -> `setActiveInputMethod()`.

6. **Error union for unsupported input methods**: `setActiveInputMethod()` returns `error{UnsupportedInputMethod}!ImeResult`.

7. **Canonical registry table**: Authoritative mapping from protocol strings to libhangul keyboard IDs, owned by IME contract Section 3.7. Protocol docs cross-reference this table, never duplicate it.

8. **keyboard_layout is orthogonal**: Physical keyboard layout (QWERTY/AZERTY/QWERTZ) is a separate per-pane field. Korean always uses QWERTY-normalized input. `keyboard_layout` persists across input method switches.

9. **Session persistence**: Single `input_method` field per pane (e.g., `"korean_2set"`). No separate language/layout fields.

10. **Engine stores protocol string**: `active_input_method: []const u8` stores the full protocol string (e.g., `"korean_2set"`), not the libhangul ID.

## 3. Changes Applied to IME Contract v0.4

25 edits applied across the entire document. Key changes:

### Structural Changes
- **Section 3.4**: Complete rewrite from "LanguageId" to "Input Method Identifiers"
- **Section 3.5**: VTable methods renamed (`getActiveInputMethod`/`setActiveInputMethod`)
- **Section 3.6**: Complete rewrite from "setActiveLanguage Behavior" to "setActiveInputMethod Behavior"
- **Section 3.7**: Complete rewrite of `HangulImeEngine` struct — removed `layout_id`, added `active_input_method`, private `EngineMode`, `libhangulKeyboardId()`, `deriveMode()`, canonical registry table

### Code Example Updates
- Section 3.8 (MockImeEngine), Section 4 (Responsibility Matrix), Section 5 (Integration code), Section 8 (C API), Section 9 (Session Persistence)

### Appendices
- Appendix C.1: Added forward reference to Appendix F
- Appendix E.6, E.7, E.9: Added "Superseded by Appendix F" notes
- **Appendix F (new)**: 7 subsections (F.1-F.7) documenting all identifier consensus changes with rationale

### Bug Fixed
The `"korean_3set_390" -> "3f"` mapping bug (should be `"39"`) is eliminated by design — the mapping now lives inside the engine's `libhangulKeyboardId()` function with the correct value.

## 4. Canonical Input Method Registry

This is the authoritative table (IME contract Section 3.7):

| Canonical string | libhangul keyboard ID | Description |
|---|---|---|
| `"direct"` | N/A | No composition — direct passthrough |
| `"korean_2set"` | `"2"` | Dubeolsik (standard) |
| `"korean_2set_old"` | `"2y"` | Dubeolsik with historical jamo |
| `"korean_3set_dubeol"` | `"32"` | Sebeolsik mapped to 2-set positions |
| `"korean_3set_390"` | `"39"` | Sebeolsik 390 |
| `"korean_3set_final"` | `"3f"` | Sebeolsik Final |
| `"korean_3set_noshift"` | `"3s"` | Sebeolsik Noshift |
| `"korean_3set_old"` | `"3y"` | Sebeolsik with historical jamo |
| `"korean_romaja"` | `"ro"` | Latin-to-Hangul transliteration |
| `"korean_ahnmatae"` | `"ahn"` | Ahnmatae ergonomic layout |

v1 ships `"direct"` + `"korean_2set"` only. The full table establishes naming convention.

**Normative rule**: The `input_method` string is the ONLY representation that crosses component boundaries. It flows unchanged from client to server to IME engine constructor. Inside the engine, it is decomposed into engine-specific types (e.g., libhangul keyboard IDs via `libhangulKeyboardId()`). No code outside the engine constructor performs this decomposition.

## 5. Cross-Document Verification Status

All 8 verification checks **PASS**:

1. No stale `LanguageId`/`layout_id`/`active_language`/`setActiveLanguage`/`getActiveLanguage` references in functional content (only in historical appendices)
2. Single `input_method` string used consistently everywhere
3. Mapping table exists ONLY in IME contract Section 3.7
4. Cross-references between IME contract (v0.4) and protocol docs (v0.5) correct
5. JSON examples use `"korean_2set"` style identifiers
6. `composition_state` ko_ prefix consistent everywhere
7. Session persistence uses single `input_method` field
8. `setActiveInputMethod`/`getActiveInputMethod` naming consistent

## 6. Open Items for Next Session

None identified. The identifier consensus is fully applied and verified across all documents.

## 7. File Locations

| Document | Path |
|---|---|
| IME contract v0.4 | `docs/modules/libitshell3-ime/02-design-docs/interface-contract/draft/v1.0-r4/01-interface-contract.md` |
| Protocol doc 04 (v0.5) | `docs/modules/libitshell3/02-design-docs/server-client-protocols/draft/v1.0-r5/04-input-and-renderstate.md` |
| Protocol doc 05 (v0.5) | `docs/modules/libitshell3/02-design-docs/server-client-protocols/draft/v1.0-r5/05-cjk-preedit-protocol.md` |
| Protocol doc 06 (v0.5) | `docs/modules/libitshell3/02-design-docs/server-client-protocols/draft/v1.0-r5/06-flow-control-and-auxiliary.md` |
