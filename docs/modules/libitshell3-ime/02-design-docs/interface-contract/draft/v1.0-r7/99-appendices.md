# IME Interface Contract v0.7 — Appendices

> **Version**: v0.7
> **Date**: 2026-03-07
> **Part of the IME Interface Contract v0.7. See [01-overview.md](01-overview.md) for the document index.**
> **Changes from v0.6**: See [Appendix I: Changes from v0.6](#appendix-i-changes-from-v06)

## Appendix A: Stale Documentation Notes

The following existing documents contain outdated information that conflicts with this interface contract:

| Document | Issue | Status |
|----------|-------|--------|
| `docs/modules/libitshell3/01-overview/13-render-state-protocol.md` | References NSTextInputContext for server-side preedit (lines 277-284). Should reference libitshell3-ime's `processKey()` flow. | Stale -- needs update |
| `docs/modules/libitshell3/01-overview/09-recommended-architecture.md` | Contains client-driven preedit API (`itshell3_preedit_start/update/end`). With native IME, preedit is server-driven. | Stale -- needs update |
| `docs/modules/libitshell3/01-overview/14-architecture-validation-report.md` | States "~300-400 lines of pure Zig, no external library needed" (line 113). We chose libhangul wrapper instead. | Inconsistent -- note the decision |
| `docs/modules/libitshell3-ime/01-overview/04-architecture.md` | `InputMode` uses `english` (should be `direct`). `flush()` returns `?[]const u8` (should return `ImeResult`). `KeyboardLayout` is an enum (should be string ID). No `ImeEngine` trait. | Superseded by this document |
| `interface-design.md` (deleted) | Was the predecessor document. Section 1.4 Modifier Flush Policy specified RESET (discard) -- incorrect. All unique content merged into this document (v0.2). Deleted. |

## Appendix B: v1 Scope

For Phase 1.5 (native IME), implement only:

- **HangulImeEngine** as the single engine type, supporting dubeolsik (`"korean_2set"`) and direct mode. Initial active input method is `"direct"` (pass-through); user toggles to `"korean_2set"` via the input method switch key.
- **Direct mode** passthrough (`"direct"`, HID -> ASCII, no composition).
- **Input method toggle** via `setActiveInputMethod()` called by libitshell3.
- **No candidate support** (Korean doesn't need it; Hanja is explicitly excluded).
- **No separate C API** (internal to libitshell3).
- **No external keyboard XML loading** (libhangul compiled without `ENABLE_EXTERNAL_KEYBOARDS`).
- Additional layouts ("3f", "39", "ro", etc.) deferred to Phase 6 (polish). Adding them is a config change, not an API change -- libhangul supports all 9 internally.

## Appendix C: Changes from v0.1

This section documents all changes made from the v0.1 interface contract based on the team review (principal-architect, ime-expert, ghostty-expert).

### C.1 Vtable Simplification

**Removed methods** (3 methods removed, vtable reduced from 11 to 8):
- `getSupportedLanguages()` -- framework (libitshell3) knows available languages at creation time.
- `setEnabledLanguages()` -- framework manages language rotation list, not the engine.
- Language management renamed: `getMode()`/`setMode()` -> `getActiveLanguage()`/`setActiveLanguage()` (later renamed to `getActiveInputMethod()`/`setActiveInputMethod()` — see Appendix F).

**Removed types**:
- `LanguageDescriptor` -- libitshell3 hardcodes language metadata (name, is_composing) since it creates the engine.

**Rationale**: In fcitx5 and ibus, language enumeration and enable/disable are framework-level concerns. The engine just processes keys and switches language when told.

### C.2 Modifier Flush Policy Correction

**v0.1**: Ambiguous (interface-design.md said RESET for Ctrl/Alt/Super; v0.1 contract and PoC used FLUSH).

**v0.2**: Explicitly **FLUSH (commit)** for all modifiers. No exceptions.

**Evidence**: Verified in ibus-hangul source (`ibus_hangul_engine_process_key_event()` calls `hangul_ic_flush()` on `IBUS_CONTROL_MASK`) and fcitx5-hangul source (calls `flush()` on modifier detection). Both commit the preedit; neither discards it. The claim in `interface-design.md` that RESET matches ibus-hangul was incorrect.

### C.3 setActiveLanguage Same-Language Semantics

**v0.1**: Not specified.

**v0.2**: Explicitly a **no-op** when called with the already-active language. Returns empty `ImeResult`, no flush.

**Rationale**: Matches fcitx5/ibus behavior. Prevents surprising flush on accidental double-toggle.

### C.4 setActiveLanguage Atomicity

**v0.1**: Implicit.

**v0.2**: Explicitly documented that `setActiveLanguage()` flushes and switches atomically. Callers must NOT call `flush()` then `setActiveLanguage()` separately.

### C.5 libhangul Cleanup Clarification

**v0.1**: Not specified whether `hangul_ic_reset()` is needed after `hangul_ic_flush()`.

**v0.2**: Explicitly documented that `hangul_ic_flush()` alone is sufficient. Verified in libhangul source: `hangul_ic_flush()` calls `hangul_buffer_clear()` which zeroes all jamo fields (`choseong`, `jungseong`, `jongseong = 0`) and clears the stack. `hangul_ic_is_empty()` returns true after flush.

### C.6 ghostty Integration Additions

**Language switch ghostty path**: Added `handleLanguageSwitch()` pseudocode showing `key = .unidentified` for committed text from `setActiveLanguage()`. (Later renamed to `handleInputMethodSwitch()` and `setActiveInputMethod()` — see [Appendix F](#appendix-f-identifier-consensus-changes).)

**ghostty language awareness**: Explicitly documented that ghostty Surface has zero language-related state. Language indicator is purely FrameUpdate metadata.

**Focus change behavior**: Documented that `active_language` persists across deactivate/activate cycles. (Later renamed to `active_input_method` — see [Appendix F](#appendix-f-identifier-consensus-changes).)

### C.7 forward_key from setActiveLanguage

**v0.1**: Not specified.

**v0.2**: Explicitly always null. Toggle key is consumed by Phase 0. If it leaked through (e.g., Right Alt), ghostty would produce garbage escape sequences.

### C.8 LanguageId Naming

**v0.1**: Used both `InputMode` (in interface-design.md) and `LanguageId` (in v0.1 contract).

**v0.2**: Standardized on `LanguageId` throughout. Methods are `getActiveLanguage()`/`setActiveLanguage()`, not `getMode()`/`setMode()`.

### C.9 ghostty Keycode Space Clarification

**v0.1**: `mapHidToGhosttyKey()` output described as `ghostty_input_key_e` without specifying the keycode space.

**v0.2**: Clarified that `ghostty_input_key_s.keycode` expects **platform-native keycodes** (`uint32_t`), not USB HID usage codes. On macOS these are Carbon virtual key codes, on Linux they are XKB keycodes. The mapping is derivable from ghostty's `keycodes.zig` `raw_entries` table.

### C.10 Explicit Preedit Clearing Requirement

**v0.1**: Preedit clearing shown in example code but not called out as a mandatory requirement.

**v0.2**: Explicitly documented that ghostty does **not** auto-clear preedit state. From `Surface.zig`: "The core surface will NOT reset the preedit state on charCallback or keyCallback." libitshell3 must call `ghostty_surface_preedit(null, 0)` explicitly whenever `preedit_changed = true` and `preedit_text = null`.

## Appendix D: Changes from v0.2

This section documents all changes made from the v0.2 interface contract based on PoC validation (`poc/02-ime-ghostty-real/poc-ghostty-real.m` — 22/24 tests pass, 2 skipped due to libghostty VT parser bug).

### D.1 Space Key Handling (Resolution 12)

**v0.2**: Space not documented in scenario matrix or modifier flush policy table.

**v0.3**: Added Space to both tables. Space during composition flushes (commits preedit), then forwards Space. When forwarding Space via `ghostty_surface_key()`, the key event MUST include `.text = " "` and `.unshifted_codepoint = ' '` because Space is a printable key — ghostty's key encoder needs the text field to produce the space character. Other forwarded special keys (Enter, Escape, arrows) work with `.text = null` because they have dedicated encoding paths.

**Evidence**: PoC Test 7 ("한" + Space + "글") produces correct terminal output with this pattern.

### D.2 Press+Release Pairs Required (Resolution 13)

**v0.2**: `handleKeyEvent` pseudocode showed only press events for `ghostty_surface_key()`.

**v0.3**: Every `ghostty_surface_key()` press event MUST be followed by a corresponding release event with `.action = .release` and `.text = null`. This is required for ghostty's internal key state tracking and forward-compatibility with Kitty keyboard protocol. Legacy mode ignores releases (harmless no-op).

**Evidence**: All 24 PoC tests send press+release pairs and pass.

### D.3 Keycode Criticality by Event Type (Resolution 14)

**v0.2**: Stated that `mapHidToGhosttyKey()` must produce platform-native keycodes (Resolution 10) but did not document criticality differences by event type.

**v0.3**: Added keycode criticality table. For committed text (`.text` set), keycode is non-critical — ghostty uses `.text` for PTY output. For forwarded keys (`.text = null`), keycode is critical — ghostty uses it for escape sequence encoding. Documented that the PoC's use of `ghostty_input_key_e` enum values as keycodes is a masked bug (works for committed text, would fail for forwarded key escape sequences).

### D.4 preedit_changed Optimization Guidance (Resolution 15)

**v0.2**: Defined `preedit_changed: bool` but did not specify whether it's mandatory or an optimization.

**v0.3**: `preedit_changed` is mandatory for the production implementation. Added guidance: engine MUST set it accurately (true on null<->non-null transitions or content changes, false when unchanged). Callers MAY ignore it and call `ghostty_surface_preedit()` unconditionally as a debugging fallback — this is always correct but wasteful.

### D.5 hangul_ic_process() Return-False Handling (Resolution 16)

**v0.2**: Not documented.

**v0.3**: Added "Phase 1: hangul_ic_process() Return-False Handling" subsection to Section 2 and cross-reference in Section 3.7. Documents the algorithm for handling keys rejected by libhangul (punctuation, numbers, etc.): check commit/preedit strings regardless of return value, flush if non-empty, forward rejected key.

### D.6 Direct Mode Scenario Matrix Expansion (Resolution 17)

**v0.2**: Only one row for direct mode: "English 'a' (direct mode)".

**v0.3**: Added 6 direct mode rows: Shift+'a', Enter, Space, Ctrl+C, Arrow, Escape. Documented direct mode branch behavior: printable without modifiers -> committed text; everything else -> forward key. Direct mode never has preedit.

### D.7 ghostty Event Loop Note (Informational)

**v0.2**: Not mentioned.

**v0.3**: Added note in Section 5 that ghostty requires regular `ghostty_app_tick()` calls for I/O processing. Forward reference to daemon architecture document.

### D.8 Left/Home Arrow Key Crash Note (Informational)

**v0.2**: Not mentioned.

**v0.3**: Added known limitation in Section 5 documenting the Left/Home arrow key crash in certain libghostty builds (`invalid enum value in terminal.stream.Stream.nextNonUtf8`). This is a libghostty VT parser issue, not an IME issue. IME flush-on-cursor-move verified via Right arrow.

## Appendix E: Changes from v0.3

This section documents all changes made from the v0.3 interface contract based on cross-document consistency review between Protocol v0.4 and IME Contract v0.3. Review participants: protocol-architect, ime-expert, cjk-specialist.

Review artifacts:
- `docs/modules/libitshell3-ime/02-design-docs/interface-contract/draft/v1.0-r3/review-notes-cross-review.md`
- `docs/modules/libitshell3/02-design-docs/server-client-protocols/draft/v1.0-r4/review-notes-cross-review-ime.md`

### E.1 HID_KEYCODE_MAX Constant (Issue 1)

**v0.3**: No explicit boundary constant for valid HID keycodes.

**v0.4**: Added `pub const HID_KEYCODE_MAX: u8 = 0xE7` to Section 3.1 (KeyEvent). Added inline doc comment on `hid_keycode` field noting the valid range `0x00–HID_KEYCODE_MAX`. Added server validation note in the constant's doc comment: "The server MUST NOT pass keycodes above HID_KEYCODE_MAX to processKey(). Keycodes above this value bypass the IME engine entirely and are routed directly to ghostty."

**Rationale**: The IME engine handles only USB HID Keyboard/Keypad page (0x07), which is bounded at 0xE7. Documenting this boundary as a named constant clarifies the contract. The wire protocol carries u16 keycodes to support future HID pages; narrowing to u8 at the IME boundary is correct practice for a domain that is provably bounded.

### E.2 Wire-to-KeyEvent Mapping Cross-Reference (Issue 2)

**v0.3**: No cross-reference to the server's wire-to-KeyEvent decomposition.

**v0.4**: Added design note in Section 3.1: "Wire-to-KeyEvent mapping: The server decomposes the protocol wire modifier bitmask into KeyEvent fields. See protocol doc 04 Section 2.1 for the full mapping table (wire Shift bit -> `KeyEvent.shift`, wire bits 1–3 -> `KeyEvent.modifiers`)."

**Rationale**: The IME contract's separation of `shift: bool` from `Modifiers` is only meaningful if the server correctly decomposes the wire bitmask. Cross-referencing the protocol makes this decomposition explicit.

### E.3 CapsLock/NumLock Intentional Omission (Issue 3)

**v0.3**: No explanation for why CapsLock/NumLock state is not in the KeyEvent.

**v0.4**: Added design note in Section 3.1: "CapsLock and NumLock (wire modifier bits 4–5) are intentionally not consumed by the IME engine. Lock key state does not affect Hangul composition — jamo selection depends solely on the Shift key. CapsLock as a language toggle key is detected in Phase 0 (libitshell3), not by the IME."

**Rationale**: Prevents future implementors from wondering whether CapsLock/NumLock should be added. Matches ibus-hangul and fcitx5-hangul, neither of which consumes these lock states.

### E.4 composition_state Field Added to ImeResult (Issue 5)

**v0.3**: ImeResult had no `composition_state` field.

**v0.4**: Added `composition_state: ?[]const u8 = null` field to ImeResult (Section 3.2) with doc comment explaining: engine-specific string, null when no composition active or direct mode, points to static string literals (valid indefinitely), server passes through to PreeditUpdate JSON without interpretation.

**Rationale**: The IME engine internally knows the Hangul composition stage. Forcing the server to reverse-engineer this from NFC decomposition of the preedit string is redundant and error-prone. The field uses `?[]const u8` (nullable string) rather than a typed enum to satisfy Design Principle #1 ("Single interface for all languages") — Korean-specific composition stages cannot be shared with future Japanese/Chinese engines.

### E.5 Scenario Matrix Updated with composition_state (Issue 5)

**v0.3**: Scenario matrix had 4 columns.

**v0.4**: Added `composition_state` column to the scenario matrix in Section 3.2 with appropriate values for each row. Korean composition scenarios show `"ko_leading_jamo"`, `"ko_syllable_no_tail"`, etc. All flush/direct/release rows show null.

### E.6 LanguageId Protocol String Mapping Cross-Reference (Issue 10)

**v0.3**: No documentation of the relationship between LanguageId enum values and protocol string identifiers.

**v0.4 (cross-review)**: Added a note in Section 3.4 (LanguageId): "Protocol string identifiers encode both language and keyboard layout (e.g., `"korean_2set"`). The server maps these to `LanguageId` (language) + `layout_id` (keyboard variant). For example, `"korean_2set"` maps to `LanguageId.korean` + `layout_id = "2"`. See protocol doc 04, Section 2.1 for the full identifier table."

**Superseded by Appendix F**: The identifier consensus removed `LanguageId` and `layout_id` entirely. Section 3.4 was rewritten to "Input Method Identifiers" with a single canonical string model. See [F.1](#f1-languageid-enum-removed-from-public-api) and [F.2](#f2-layout_id-removed-from-public-api).

**Rationale**: Originally documented the separation of concerns between `LanguageId` enum and protocol strings. The identifier consensus eliminated this separation entirely — the protocol string flows directly to the engine.

### E.7 reset()+setActiveLanguage() Discard-and-Switch Pattern (Issue 8)

**v0.3**: Section 3.6 only described the normal language-switch (commit) path.

**v0.4 (cross-review)**: Added note in Section 3.6: "`reset()` followed by `setActiveLanguage()` is safe for discard-and-switch when the caller holds the per-pane lock. After `reset()`, the engine is empty and `setActiveLanguage()` performs a no-flush language switch. This pattern implements the protocol's `commit_current=false` on InputMethodSwitch."

**Superseded by Appendix F**: `setActiveLanguage()` was renamed to `setActiveInputMethod()`. The discard-and-switch pattern remains valid with the new method name. See [F.3](#f3-vtable-methods-renamed).

**Rationale**: The protocol supports `commit_current=false` for InputMethodSwitch. No new IME method is needed — the server orchestrates cancel via `reset()` + `setActiveInputMethod()` under per-session lock.

### E.8 CompositionStates String Constants Added to HangulImeEngine (Issue 5)

**v0.3**: HangulImeEngine had no composition state constants.

**v0.4**: Added `CompositionStates` nested struct to Section 3.7 with six string constants: `empty`, `ko_leading_jamo`, `ko_vowel_only`, `ko_syllable_no_tail`, `ko_syllable_with_tail`, `ko_double_tail`. Added naming convention note explaining the `ko_` prefix requirement for language-specific constants, and the rationale for `empty` being language-agnostic. (Note: `empty` was subsequently removed in v0.5 — see [G.3](#g3-compositionstatesempty-removed-issue-25b).)

**Rationale**: Provides canonical string values for `ImeResult.composition_state`. The `ko_` prefix prevents collision when future Japanese/Chinese engines define their own state strings.

### E.9 Session Persistence Fields Note (RestoreSession gap)

**v0.3**: Section 3.7 defined `active_language` and `layout_id` fields but did not explicitly connect them to session persistence requirements.

**v0.4 (cross-review)**: Added persistence note in Section 3.7: "Session persistence fields: `active_language` (LanguageId) and `layout_id` (string) are the fields that must be saved per pane for session persistence. On session restore, the server creates a new `HangulImeEngine` with the saved `layout_id` and calls `setActiveLanguage(saved_language_id)`. Composition state is never persisted — it is flushed on pane deactivation before the session is saved."

**Superseded by Appendix F**: Session persistence simplified to a single `input_method` field (e.g., `"korean_2set"`). No separate `active_language` or `layout_id`. See [F.5](#f5-session-persistence-simplified).

Also added `composition_state` memory model clarification to Section 6 (Memory Ownership): "Points to static string literals. Valid indefinitely — not invalidated by any method call." (This part remains valid.)

**Rationale**: Closes the RestoreSession IME initialization gap identified in cross-review. The identifier consensus further simplified the persistence model.

## Appendix F: Identifier Consensus Changes

This section documents all changes made to the v0.4 interface contract based on the three-way identifier design consensus (protocol-architect, ime-expert, cjk-specialist). The consensus resolved the inconsistency between the protocol's single-string identifiers and the IME contract's `LanguageId` enum + `layout_id` pair.

### F.1 LanguageId Enum Removed from Public API

**v0.4-pre**: `LanguageId` was a public `enum(u8)` type with `direct = 0`, `korean = 1`. Used in `getActiveLanguage()` return type and `setActiveLanguage()` parameter type.

**v0.4**: `LanguageId` removed from the public API entirely. Replaced by `input_method: []const u8` — a single canonical string (e.g., `"direct"`, `"korean_2set"`). Section 3.4 rewritten from "LanguageId" to "Input Method Identifiers".

**Rationale**: The `(LanguageId, layout_id)` pair required a server-side mapping table between protocol strings and IME types. This table produced the `"korean_3set_390" -> "3f"` bug (should be `"39"`). A single string flowing from protocol to IME eliminates the mapping table and this bug class. The engine internally derives a private `EngineMode` enum for hot-path dispatch.

### F.2 layout_id Removed from Public API

**v0.4-pre**: `HangulImeEngine` had a `layout_id: []const u8` field storing the libhangul keyboard ID (e.g., `"2"`). Constructor took `layout_id` as parameter.

**v0.4**: Replaced by `active_input_method: []const u8` storing the canonical protocol string (e.g., `"korean_2set"`). Constructor takes `input_method` as parameter. The engine maps the protocol string to a libhangul keyboard ID internally via `libhangulKeyboardId()`.

**Rationale**: The engine is the only consumer of libhangul keyboard IDs (information expert principle). The mapping lives in exactly one place — the engine constructor — and is unit-testable in isolation.

### F.3 Vtable Methods Renamed

**v0.4-pre**: `getActiveLanguage() -> LanguageId`, `setActiveLanguage(LanguageId) -> ImeResult`.

**v0.4**: `getActiveInputMethod() -> []const u8`, `setActiveInputMethod([]const u8) -> error{UnsupportedInputMethod}!ImeResult`.

**Rationale**: Aligns method names with the protocol field name `active_input_method`. One vocabulary across the entire stack. Error union added because the engine must validate input method strings — receiving an unsupported string is a server bug that should be surfaced explicitly.

### F.4 Canonical Input Method Registry Added

**v0.4-pre**: No canonical list of valid input method strings. Protocol doc 05 Section 4.3 had a mapping table (with the 3f/39 bug).

**v0.4**: Added canonical input method registry table to Section 3.7 with all 9 libhangul keyboard IDs correctly mapped. This is the single source of truth — protocol docs reference it via cross-reference, never duplicate it.

**Rationale**: Eliminates the cross-component mapping table that caused the 3f/39 bug. The registry is owned by the IME contract (the IME implementor knows libhangul's keyboard IDs).

### F.5 Session Persistence Simplified

**v0.4-pre**: Two fields persisted per pane: `active_language` (LanguageId) + `layout_id` (string).

**v0.4**: Single field: `input_method` (string, e.g., `"korean_2set"`). No reverse-mapping needed on restore.

### F.6 setActiveInputMethod String Parameter Ownership

**v0.4-pre**: Not applicable (parameter was `LanguageId` enum, a value type).

**v0.4**: Added string parameter ownership note in Section 3.6: the `method` parameter is borrowed for the duration of the call. The engine copies the string into its own storage. The caller does not need to keep the pointer alive after the call returns.

### F.7 Naming Convention Established

**Consensus**: Input method identifiers use `{language}_{human_readable_variant}` format. The language prefix serves as a namespace. `"direct"` is a special case with no prefix.

The `ko_` prefix is reserved for composition state constants (`"ko_leading_jamo"`, etc.), which are engine-internal runtime state. Input method identifiers use the full `"korean_"` prefix because they are user-facing configuration values.

**Rationale**: Human-readable names are self-documenting in protocol traces and debug logs. Engine-native IDs (like libhangul's `"2"`, `"3f"`) are implementation details that should not leak into the protocol. The Ahnmatae layout (libhangul ID `"ahn"`) demonstrated that engine-native IDs cannot be reliably extracted from protocol strings via simple string slicing.

---

## Appendix G: Changes from v0.4

### G.1 Memory Invalidation List Expanded (Issue 2.2)

**v0.4**: `ImeResult` doc comment stated slices are valid until the next call to `processKey()`, `flush()`, `reset()`, or `setActiveInputMethod()`.

**v0.5**: Added `deactivate()` to the invalidation list. `deactivate()` may flush and reset internal buffers, invalidating any previously returned slices.

### G.2 Composition State Prefix Convention Formalized (Issue 2.1)

**v0.4**: Naming convention note in Section 3.7 stated only that language-specific constants use a language prefix (`ko_`, `ja_`, `zh_`), and that `empty` is the sole language-agnostic constant.

**v0.5**: Replaced with a normative rule specifying the prefix granularity: when a language has exactly one composition state graph shared by all input method variants, use ISO 639-1 prefix (`ko_`, `ja_`); when a language has multiple input methods with distinct state graphs, use `{iso639}_{method}_` prefix (`zh_pinyin_`, `zh_bopomofo_`, `zh_cangjie_`). Added a concrete application table. Added normative note that when the same input method supports multiple character sets (e.g., Pinyin for Traditional and Simplified Chinese), the prefix reflects the state graph, not the character set — character set selection is a configuration parameter distinguished by the `input_method` identifier (e.g., `"chinese_pinyin_traditional"` vs `"chinese_pinyin_simplified"`), not by the composition state prefix.

### G.3 `CompositionStates.empty` Removed (Issue 2.5b)

**v0.4**: `CompositionStates` struct contained `pub const empty = "empty";` as a language-agnostic constant for the no-composition state.

**v0.5**: `empty` constant removed. `ImeResult.composition_state = null` is the canonical representation for no active composition. Using a string `"empty"` was redundant with the existing `null` semantics already defined by the `?[]const u8` type. Added normative note after the `CompositionStates` struct.

### G.4 `ko_vowel_only` Reachability Documented (Issue 2.5a)

**v0.4**: `ko_vowel_only` was listed in `CompositionStates` without explanation of when it is reachable in practice.

**v0.5**: Added reachability note: `ko_vowel_only` occurs in 3-set (Sebeolsik) layouts where consonant and vowel keys are physically separated. In 2-set (Dubeolsik), libhangul inserts an implicit ㅇ leading consonant, producing `ko_syllable_no_tail` instead. The scenario matrix illustrates 2-set behavior (v1 default) and is not exhaustive.

### G.5 Appendix E.9 Link Fixed (Issue 2.3)

**v0.4**: Appendix E.9 contained a broken link `[F.6](#f6-session-persistence-simplified)` pointing to a non-existent anchor.

**v0.5**: Corrected to `[F.5](#f5-session-persistence-simplified)`, which is the correct anchor for the "Session Persistence Simplified" entry in Appendix F.

### G.6 Section 3.7 Anchor Fix (Verification V-1)

**v0.4**: The `ko_vowel_only` reachability note in Section 3.7 contained a broken anchor `#32-imeresult-orthogonality-scenario-matrix`.

**v0.5**: Corrected to `#32-imeresult-output-from-ime`, which matches the actual heading of Section 3.2.

---

## Appendix H: Changes from v0.5

This section documents all changes made from the v0.5 interface contract. Sources: design-resolutions-per-tab-engine.md (Resolutions 1–16), owner decisions 1–4 (02-owner-decisions.md), macOS IME suppression PoC findings (handover-to-v06.md).

### H.1 Per-Session Engine Architecture (Owner Decision 3 + Resolutions 1–8, 16)

**v0.5**: Each `Pane` held its own `ImeEngine` instance. Session persistence stored `input_method` per pane.

**v0.6**: Each `Session` holds one shared `ImeEngine` instance. All panes within a session share the same engine and the same `active_input_method` state. A new pane inherits the session's current input method automatically.

**Affected sections:**
- **Section 3.5** (ImeEngine): Doc comment updated: "libitshell3's Session holds an ImeEngine" (was "Pane"). Doc comments for `activate`, `deactivate`, and `flush` updated to reflect session-level semantics (Resolutions 3, 4, 16).
- **Section 3.7** (HangulImeEngine): Session persistence note updated: "saved per session" (was "saved per pane").
- **Section 3.8** (MockImeEngine): Test example updated to use `Session.initWithEngine()`.
- **Section 4** (Responsibility Matrix): "Per-pane ImeEngine lifecycle" updated to "Per-session ImeEngine lifecycle". Added rows for routing ImeResult to correct pane and new pane inheriting input method. Added note that engine is pane-agnostic (Resolution 6). Added note that server is the routing layer.
- **Section 5** (ghostty Integration): `handleKeyEvent` now takes `session` + `focused_pane` parameters and calls `session.engine.processKey()`. `handleInputMethodSwitch` uses `session.engine` and `session.focused_pane`. Added new `handleIntraSessionFocusChange()` code example (Resolution 2). Updated focus change description from "pane loses focus" to "session loses focus/tab switch".
- **Section 9** (Session Persistence): Entire section rewritten. Per-pane IME JSON schema replaced with per-session schema. Both `input_method` and `keyboard_layout` now stored at session level.

**Rationale**: Owner decision: switching to Korean in one pane should affect all panes in the same tab. A shared engine provides this naturally.

### H.2 activate()/deactivate() Semantics Clarified (Resolution 3)

**v0.5**: `activate`/`deactivate` were described as "pane gained/lost focus".

**v0.6**: Redefined as session-level focus methods. `flush()` is used for intra-session pane focus changes; `activate()`/`deactivate()` are for inter-session/tab switching and app-level focus transitions.

| Event | Engine method |
|---|---|
| Intra-session pane focus change | `flush()` |
| Inter-session tab switch (away) | `deactivate()` |
| Inter-session tab switch (to) | `activate()` |
| App loses OS focus | `deactivate()` |
| Session close | `deactivate()` then `deinit()` |

### H.3 deactivate() Must Flush — Normative Requirement (Resolution 4)

**v0.5**: Not explicitly required.

**v0.6**: Added normative requirement in Section 3.5 `deactivate` doc comment: "Engine MUST flush pending composition before returning. The returned ImeResult contains the flushed text. Calling flush() before deactivate() is redundant but harmless."

### H.4 Shared Engine Memory Ownership Invariant (Resolution 5)

**v0.5**: No shared engine invariant (engines were per-pane).

**v0.6**: Added "Shared Engine Invariant" paragraph to Section 6 (Memory Ownership): the caller MUST consume `ImeResult` before making any subsequent call to the same engine instance. This prevents buffer corruption from overlapping calls to the shared engine.

### H.5 Hanja Explicitly Excluded (Owner Decision 1)

**v0.5**: Section 10 Q1 asked whether Hanja conversion should be in v1 scope.

**v0.6**: Q1 removed. Added normative exclusion note in Section 7 (Future Extensibility): "Korean Hanja conversion is explicitly excluded. The candidate callback mechanism is reserved for future Chinese/Japanese engines only." Appendix B updated: "No candidate support (Korean doesn't need it; Hanja is explicitly excluded)."

### H.6 Dead Keys → Separate Engine (Owner Decision 2)

**v0.5**: Section 10 Q2 asked whether dead keys should be in direct mode or a separate engine.

**v0.6**: Q2 removed. Added settled decision note in Section 7 (Future Extensibility): "European dead keys will be a separate engine (`\"european_deadkey\"`), NOT a feature of direct mode. Direct mode must remain pure passthrough."

### H.7 Section 10 (Open Questions) Removed

**v0.5**: Section 10 contained 4 open questions (Q1–Q4).

**v0.6**: All four questions resolved:
- Q1 (Hanja): Resolved by owner — excluded (see H.5).
- Q2 (Dead keys): Resolved by owner — separate engine (see H.6).
- Q3 (Per-pane vs global mode): Resolved by owner — per-session shared engine (see H.1).
- Q4 (macOS IME suppression): Resolved by PoC — validated, documented in Section 5 (see H.8).

Section 10 is removed entirely as it has no remaining content.

### H.8 macOS/iOS IME Suppression PoC Findings Incorporated (Owner Decision 4 — PoC Completed)

**v0.5**: Section 10 Q4 described macOS IME suppression as an open question with a pending PoC.

**v0.6**: Q4 removed. Added "macOS and iOS Client IME Suppression (PoC Validated)" subsection to Section 5 with:
- Platform comparison table (macOS vs iOS key capture mechanisms)
- Key findings: `event.characters` unreliable, `keyCode` rock-solid across input sources
- Validation that `processKey(hid_keycode, shift, modifiers)` maps naturally to both platforms
- Reference to `poc/03-macos-ime-suppression/`

### H.9 Section 3.4 keyboard_layout Scope Updated

**v0.5**: Section 3.4 referred to `keyboard_layout` as a "separate per-pane field".

**v0.6**: Updated to "separate per-session field" to match the per-session architecture.

### H.10 Appendix E.7 Discard-and-Switch Lock Scope Updated

**v0.5**: Appendix E.7 referred to "the per-pane lock" for the discard-and-switch pattern.

**v0.6**: Updated to "the per-session lock" to match the per-session architecture.

---

## Appendix I: Changes from v0.6

This section documents all changes made from the v0.6 interface contract. Sources: cross-team preedit overhaul design resolutions (`docs/modules/libitshell3/02-design-docs/server-client-protocols/draft/v1.0-r8/design-resolutions/01-preedit-overhaul.md`, Resolutions 15–16), cross-team request (`docs/modules/libitshell3-ime/02-design-docs/interface-contract/draft/v1.0-r6/cross-team-requests/01-protocol-composition-state-removal.md`), v0.6 handover (`docs/modules/libitshell3-ime/02-design-docs/interface-contract/draft/v1.0-r6/handover/handover-to-v0.7.md`).

### I.1 `composition_state` Field Removed from ImeResult (Resolution 15, Change 1)

**v0.6**: `ImeResult` contained `composition_state: ?[]const u8 = null` with doc comment referencing `HangulImeEngine.CompositionStates`.

**v0.7**: Field removed entirely.

**Rationale**: No component consumed this value. The server passed it through to PreeditUpdate JSON, but no client read it. A PoC (`poc/04-libhangul-states/probe.c`) confirmed factual errors in the documented states: `ko_vowel_only` IS reachable in 2-set (contrary to doc claim), `ko_double_tail` is not distinguishable from `ko_syllable_with_tail` via libhangul's public API, and 3-set keyboards produce states with no corresponding constant. The field was a documentation exercise, not a feature.

### I.2 `composition_state` Column Removed from Scenario Matrix (Resolution 15, Change 2)

**v0.6**: Scenario matrix in Section 3.2 had 5 columns: `committed_text`, `preedit_text`, `forward_key`, `preedit_changed`, `composition_state`.

**v0.7**: Matrix retains 4 columns: `committed_text`, `preedit_text`, `forward_key`, `preedit_changed`.

### I.3 `CompositionStates` Struct Removed from HangulImeEngine (Resolution 15, Change 3)

**v0.6**: `HangulImeEngine` (Section 3.7) contained a nested `CompositionStates` struct with 5 string constants: `ko_leading_jamo`, `ko_vowel_only`, `ko_syllable_no_tail`, `ko_syllable_with_tail`, `ko_double_tail`.

**v0.7**: Struct removed entirely.

**Rationale**: Constants were only used for `ImeResult.composition_state`, which is removed.

### I.4 Composition-State Naming Convention Removed (Resolution 15, Change 4)

**v0.6**: Section 3.7 contained a normative rule specifying composition state prefix granularity (`ko_` prefix for Korean, `zh_pinyin_`/`zh_bopomofo_`/`zh_cangjie_` for Chinese variants) and a concrete application table.

**v0.7**: Removed entirely. Input method identifier naming convention (`"korean_*"` format) in Section 3.4 is unaffected — it serves a different purpose (user-facing configuration values, not engine-internal state).

### I.5 `composition_state` Removed from setActiveInputMethod Examples (Resolution 15, Change 5)

**v0.6**: Section 3.6 `setActiveInputMethod` return value examples included `.composition_state = null` in both Case 1 (different method) and Case 2 (same method) `ImeResult` examples.

**v0.7**: `.composition_state = null` removed from all `ImeResult` examples in Section 3.6.

### I.6 `composition_state` Memory Model Note Removed (Resolution 15, Change 6)

**v0.6**: Section 6 (Memory Ownership) contained the note: "Points to static string literals. Valid indefinitely — not invalidated by any method call."

**v0.7**: Note removed. Section 6 only documents fields that exist in `ImeResult`.

### I.7 `itshell3_preedit_cb` Revision Note Added (Resolution 16)

**v0.6**: Section 8 contained a speculative `itshell3_preedit_cb` callback signature with `cursor_x` and `cursor_y` parameters.

**v0.7**: Added note that `cursor_x` and `cursor_y` parameters are obsolete under the "preedit is cell data" model and will be removed when the C API is implemented. The callback's purpose should be re-evaluated: with preedit rendering via cell data, the callback may serve only non-rendering uses (status bar, accessibility) with a simplified signature of `(pane_id, text, text_len, userdata)`.
