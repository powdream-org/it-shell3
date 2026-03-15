# IME Interface Contract — Appendices

## Appendix A: v1 Scope

For Phase 1.5 (native IME), implement only:

- **HangulImeEngine** as the single engine type, supporting dubeolsik
  (`"korean_2set"`) and direct mode. Initial active input method is `"direct"`
  (pass-through); user toggles to `"korean_2set"` via the input method switch
  key.
- **Direct mode** passthrough (`"direct"`, HID -> ASCII, no composition).
- **Input method toggle** via `setActiveInputMethod()` called by libitshell3.
- **No candidate support** (Korean doesn't need it; Hanja is explicitly
  excluded).
- **No separate C API** (internal to libitshell3).
- **No external keyboard XML loading** (libhangul compiled without
  `ENABLE_EXTERNAL_KEYBOARDS`).
- Additional layouts ("3f", "39", "ro", etc.) deferred to Phase 6 (polish).
  Adding them is a config change, not an API change — libhangul supports all 9
  internally.

---

## Appendix B: Changes from v0.1

This section documents all changes made from the v0.1 interface contract based
on the team review (principal-architect, ime-expert, ghostty-expert).

### B.1 Vtable Simplification

**Removed methods** (3 methods removed, vtable reduced from 11 to 8):

- `getSupportedLanguages()` — framework (libitshell3) knows available languages
  at creation time.
- `setEnabledLanguages()` — framework manages language rotation list, not the
  engine.
- Language management renamed: `getMode()`/`setMode()` ->
  `getActiveLanguage()`/`setActiveLanguage()` (later renamed to
  `getActiveInputMethod()`/`setActiveInputMethod()` — see Appendix D).

**Removed types**:

- `LanguageDescriptor` — libitshell3 hardcodes language metadata (name,
  is_composing) since it creates the engine.

**Rationale**: In fcitx5 and ibus, language enumeration and enable/disable are
framework-level concerns. The engine just processes keys and switches language
when told.

### B.2 Modifier Flush Policy Correction

**v0.1**: Ambiguous (interface-design.md said RESET for Ctrl/Alt/Super; v0.1
contract and PoC used FLUSH).

**v0.2**: Explicitly **FLUSH (commit)** for all modifiers. No exceptions.

**Evidence**: Verified in ibus-hangul source
(`ibus_hangul_engine_process_key_event()` calls `hangul_ic_flush()` on
`IBUS_CONTROL_MASK`) and fcitx5-hangul source (calls `flush()` on modifier
detection). Both commit the preedit; neither discards it. The claim in
`interface-design.md` that RESET matches ibus-hangul was incorrect.

### B.3 setActiveLanguage Same-Language Semantics

**v0.1**: Not specified.

**v0.2**: Explicitly a **no-op** when called with the already-active language.
Returns empty `ImeResult`, no flush.

**Rationale**: Matches fcitx5/ibus behavior. Prevents surprising flush on
accidental double-toggle.

### B.4 setActiveLanguage Atomicity

**v0.1**: Implicit.

**v0.2**: Explicitly documented that `setActiveLanguage()` flushes and switches
atomically. Callers must NOT call `flush()` then `setActiveLanguage()`
separately.

### B.5 forward_key from setActiveLanguage

**v0.1**: Not specified.

**v0.2**: Explicitly always null. Toggle key is consumed by Phase 0. If it
leaked through (e.g., Right Alt), ghostty would produce garbage escape
sequences.

### B.6 LanguageId Naming

**v0.1**: Used both `InputMode` (in interface-design.md) and `LanguageId` (in
v0.1 contract).

**v0.2**: Standardized on `LanguageId` throughout. Methods are
`getActiveLanguage()`/`setActiveLanguage()`, not `getMode()`/`setMode()`.

---

## Appendix C: Changes from v0.3

This section documents all changes made from the v0.3 interface contract based
on cross-document consistency review between Protocol v0.4 and IME Contract
v0.3. Review participants: protocol-architect, ime-expert, cjk-specialist.

Review artifacts:

- `docs/modules/libitshell3-ime/02-design-docs/interface-contract/draft/v1.0-r3/review-notes-cross-review.md`
- `docs/modules/libitshell3-protocol/02-design-docs/server-client-protocols/draft/v1.0-r4/review-notes-cross-review-ime.md`

### C.1 HID_KEYCODE_MAX Constant (Issue 1)

**v0.3**: No explicit boundary constant for valid HID keycodes.

**v0.4**: Added `pub const HID_KEYCODE_MAX: u8 = 0xE7` to KeyEvent. Added inline
doc comment noting the valid range `0x00–HID_KEYCODE_MAX`. Added server
validation note: "The server MUST NOT pass keycodes above HID_KEYCODE_MAX to
processKey(). Keycodes above this value bypass the IME engine entirely and are
routed directly to ghostty."

**Rationale**: The IME engine handles only USB HID Keyboard/Keypad page (0x07),
which is bounded at 0xE7. The wire protocol carries u16 keycodes to support
future HID pages; narrowing to u8 at the IME boundary is correct practice for a
domain that is provably bounded.

### C.2 Wire-to-KeyEvent Mapping Cross-Reference (Issue 2)

**v0.3**: No cross-reference to the server's wire-to-KeyEvent decomposition.

**v0.4**: Added design note: "Wire-to-KeyEvent mapping: The server decomposes
the protocol wire modifier bitmask into KeyEvent fields (wire Shift bit ->
`KeyEvent.shift`, wire bits 1–3 -> `KeyEvent.modifiers`)."

**Rationale**: The IME contract's separation of `shift: bool` from `Modifiers`
is only meaningful if the server correctly decomposes the wire bitmask.

### C.3 CapsLock/NumLock Intentional Omission (Issue 3)

**v0.3**: No explanation for why CapsLock/NumLock state is not in the KeyEvent.

**v0.4**: Added design note: "CapsLock and NumLock are intentionally not
consumed by the IME engine. Lock key state does not affect Hangul composition —
jamo selection depends solely on the Shift key. CapsLock as a language toggle
key is detected in Phase 0 (libitshell3), not by the IME."

**Rationale**: Prevents future implementors from wondering whether
CapsLock/NumLock should be added. Matches ibus-hangul and fcitx5-hangul, neither
of which consumes these lock states.

---

## Appendix D: Identifier Consensus Changes

This section documents all changes made to the v0.4 interface contract based on
the three-way identifier design consensus (protocol-architect, ime-expert,
cjk-specialist). The consensus resolved the inconsistency between the protocol's
single-string identifiers and the IME contract's `LanguageId` enum + `layout_id`
pair.

### D.1 LanguageId Enum Removed from Public API

**v0.4-pre**: `LanguageId` was a public `enum(u8)` with `direct = 0`,
`korean = 1`. Used in `getActiveLanguage()` return type and
`setActiveLanguage()` parameter type.

**v0.4**: `LanguageId` removed from the public API entirely. Replaced by
`input_method: []const u8` — a single canonical string (e.g., `"direct"`,
`"korean_2set"`).

**Rationale**: The `(LanguageId, layout_id)` pair required a server-side mapping
table between protocol strings and IME types. This table produced the
`"korean_3set_390" -> "3f"` bug (should be `"39"`). A single string flowing from
protocol to IME eliminates the mapping table and this bug class. The engine
internally derives a private `EngineMode` enum for hot-path dispatch.

### D.2 layout_id Removed from Public API

**v0.4-pre**: `HangulImeEngine` had a `layout_id: []const u8` field storing the
libhangul keyboard ID (e.g., `"2"`). Constructor took `layout_id` as parameter.

**v0.4**: Replaced by `active_input_method: []const u8` storing the canonical
protocol string (e.g., `"korean_2set"`). The engine maps the protocol string to
a libhangul keyboard ID internally via `libhangulKeyboardId()`.

**Rationale**: The engine is the only consumer of libhangul keyboard IDs
(information expert principle). The mapping lives in exactly one place — the
engine constructor — and is unit-testable in isolation.

### D.3 Vtable Methods Renamed

**v0.4-pre**: `getActiveLanguage() -> LanguageId`,
`setActiveLanguage(LanguageId) -> ImeResult`.

**v0.4**: `getActiveInputMethod() -> []const u8`,
`setActiveInputMethod([]const u8) -> error{UnsupportedInputMethod}!ImeResult`.

**Rationale**: Aligns method names with the protocol field name
`active_input_method`. Error union added because receiving an unsupported string
is a server bug that should be surfaced explicitly.

### D.4 Canonical Input Method Registry Added

**v0.4-pre**: No canonical list of valid input method strings. Protocol doc 05
Section 4.3 had a mapping table (with the 3f/39 bug).

**v0.4**: Added canonical input method registry table with all 9 libhangul
keyboard IDs correctly mapped. This is the single source of truth — protocol
docs reference it via cross-reference, never duplicate it.

**Rationale**: Eliminates the cross-component mapping table that caused the
3f/39 bug. The registry is owned by the IME contract (the IME implementor knows
libhangul's keyboard IDs).

### D.5 Session Persistence Simplified

**v0.4-pre**: Two fields persisted per pane: `active_language` (LanguageId) +
`layout_id` (string).

**v0.4**: Single field: `input_method` (string, e.g., `"korean_2set"`). No
reverse-mapping needed on restore.

### D.6 setActiveInputMethod String Parameter Ownership

**v0.4-pre**: Not applicable (parameter was `LanguageId` enum, a value type).

**v0.4**: The `method` parameter is borrowed for the duration of the call. The
engine copies the string into its own storage. The caller does not need to keep
the pointer alive after the call returns.

### D.7 Naming Convention Established

**Consensus**: Input method identifiers use
`{language}_{human_readable_variant}` format. `"direct"` is a special case with
no prefix.

**Rationale**: Human-readable names are self-documenting in protocol traces and
debug logs. Engine-native IDs (like libhangul's `"2"`, `"3f"`) are
implementation details that should not leak into the protocol. The Ahnmatae
layout (libhangul ID `"ahn"`) demonstrated that engine-native IDs cannot be
reliably extracted from protocol strings via simple string slicing.

---

## Appendix E: Changes from v0.4

### E.1 Memory Invalidation List Expanded (Issue 2.2)

**v0.4**: `ImeResult` doc comment stated slices are valid until the next call to
`processKey()`, `flush()`, `reset()`, or `setActiveInputMethod()`.

**v0.5**: Added `deactivate()` to the invalidation list. `deactivate()` may
flush and reset internal buffers, invalidating any previously returned slices.

---

## Appendix F: Changes from v0.5

This section documents all changes made from the v0.5 interface contract.
Sources: design-resolutions-per-tab-engine.md (Resolutions 1–16), owner
decisions 1–4 (02-owner-decisions.md), macOS IME suppression PoC findings
(handover-to-v06.md).

### F.1 Per-Session Engine Architecture (Owner Decision 3 + Resolutions 1–8, 16)

**v0.5**: Each `Pane` held its own `ImeEngine` instance. Session persistence
stored `input_method` per pane.

**v0.6**: Each `Session` holds one shared `ImeEngine` instance. All panes within
a session share the same engine and the same `active_input_method` state. A new
pane inherits the session's current input method automatically.

**Rationale**: Owner decision: switching to Korean in one pane should affect all
panes in the same tab. A shared engine provides this naturally.

### F.2 activate()/deactivate() Semantics Clarified (Resolution 3)

**v0.5**: `activate`/`deactivate` were described as "pane gained/lost focus".

**v0.6**: Redefined as session-level focus methods. `flush()` is used for
intra-session pane focus changes; `activate()`/`deactivate()` are for
inter-session/tab switching and app-level focus transitions.

| Event                           | Engine method                  |
| ------------------------------- | ------------------------------ |
| Intra-session pane focus change | `flush()`                      |
| Inter-session tab switch (away) | `deactivate()`                 |
| Inter-session tab switch (to)   | `activate()`                   |
| App loses OS focus              | `deactivate()`                 |
| Session close                   | `deactivate()` then `deinit()` |

### F.3 deactivate() Must Flush — Normative Requirement (Resolution 4)

**v0.5**: Not explicitly required.

**v0.6**: Added normative requirement: "Engine MUST flush pending composition
before returning. The returned ImeResult contains the flushed text. Calling
flush() before deactivate() is redundant but harmless."

### F.4 Shared Engine Memory Ownership Invariant (Resolution 5)

**v0.5**: No shared engine invariant (engines were per-pane).

**v0.6**: Added "Shared Engine Invariant": the caller MUST consume `ImeResult`
before making any subsequent call to the same engine instance. This prevents
buffer corruption from overlapping calls to the shared engine.

### F.5 Hanja Explicitly Excluded (Owner Decision 1)

**v0.5**: Open question whether Hanja conversion should be in v1 scope.

**v0.6**: Permanently excluded. "Korean Hanja conversion is explicitly excluded.
The candidate callback mechanism is reserved for future Chinese/Japanese engines
only." This is a permanent design decision, not a deferral.

### F.6 Dead Keys → Separate Engine (Owner Decision 2)

**v0.5**: Open question whether dead keys should be in direct mode or a separate
engine.

**v0.6**: Permanently decided: separate engine (`"european_deadkey"`). Direct
mode must remain pure passthrough. This is a permanent design decision.

### F.7 Section 10 (Open Questions) Removed

**v0.5**: Section 10 contained 4 open questions (Q1–Q4).

**v0.6**: All four questions resolved:

- Q1 (Hanja): Resolved by owner — excluded (see F.5).
- Q2 (Dead keys): Resolved by owner — separate engine (see F.6).
- Q3 (Per-pane vs global mode): Resolved by owner — per-session shared engine
  (see F.1).
- Q4 (macOS IME suppression): Resolved by PoC — validated (see F.8).

### F.8 macOS/iOS IME Suppression PoC Findings Incorporated (Owner Decision 4)

**v0.5**: macOS IME suppression was an open question with a pending PoC.

**v0.6**: PoC validated. Key findings: `event.characters` unreliable, `keyCode`
rock-solid across input sources. Validation that
`processKey(hid_keycode, shift, modifiers)` maps naturally to both platforms.
Reference: `poc/03-macos-ime-suppression/`.

### F.9 Section 3.4 keyboard_layout Scope Updated

**v0.5**: `keyboard_layout` referred to as a "separate per-pane field".

**v0.6**: Updated to "separate per-session field" to match the per-session
architecture.

---

## Appendix G: Changes from v0.6

This section documents all changes made from the v0.6 interface contract.
Sources: cross-team preedit overhaul design resolutions (Resolutions 15–16),
cross-team request
(`draft/v1.0-r6/cross-team-requests/01-protocol-composition-state-removal.md`),
v0.6 handover (`draft/v1.0-r6/handover/handover-to-v0.7.md`).

### G.1 `composition_state` Field Removed from ImeResult (Resolution 15, Change 1)

**v0.6**: `ImeResult` contained `composition_state: ?[]const u8 = null`.

**v0.7**: Field removed entirely.

**Rationale**: No component consumed this value. A PoC
(`poc/04-libhangul-states/probe.c`) confirmed factual errors in the documented
states: `ko_vowel_only` IS reachable in 2-set (contrary to doc claim),
`ko_double_tail` is not distinguishable from `ko_syllable_with_tail` via
libhangul's public API, and 3-set keyboards produce states with no corresponding
constant. The field was a documentation exercise, not a feature.

### G.2 `composition_state` Column Removed from Scenario Matrix (Resolution 15, Change 2)

**v0.6**: Scenario matrix had 5 columns including `composition_state`.

**v0.7**: Matrix retains 4 columns: `committed_text`, `preedit_text`,
`forward_key`, `preedit_changed`.

### G.3 `CompositionStates` Struct Removed from HangulImeEngine (Resolution 15, Change 3)

**v0.6**: `HangulImeEngine` contained a nested `CompositionStates` struct with 5
string constants: `ko_leading_jamo`, `ko_vowel_only`, `ko_syllable_no_tail`,
`ko_syllable_with_tail`, `ko_double_tail`.

**v0.7**: Struct removed entirely. Constants were only used for
`ImeResult.composition_state`, which is removed.

### G.4 Composition-State Naming Convention Removed (Resolution 15, Change 4)

**v0.6**: Normative rule specifying composition state prefix granularity (`ko_`
for Korean, `zh_pinyin_`/`zh_bopomofo_`/`zh_cangjie_` for Chinese variants).

**v0.7**: Removed entirely. Input method identifier naming convention
(`"korean_*"` format) is unaffected — it serves a different purpose.

### G.5 `composition_state` Removed from setActiveInputMethod Examples (Resolution 15, Change 5)

**v0.6**: `setActiveInputMethod` return value examples included
`.composition_state = null`.

**v0.7**: `.composition_state = null` removed from all `ImeResult` examples.

### G.6 `composition_state` Memory Model Note Removed (Resolution 15, Change 6)

**v0.6**: Memory Ownership section contained: "Points to static string literals.
Valid indefinitely — not invalidated by any method call."

**v0.7**: Note removed. Section only documents fields that exist in `ImeResult`.

### G.7 `itshell3_preedit_cb` Revision Note Added (Resolution 16)

**v0.6**: Speculative `itshell3_preedit_cb` callback with `cursor_x` and
`cursor_y` parameters.

**v0.7**: Added note that `cursor_x`/`cursor_y` are obsolete under the "preedit
is cell data" model. The callback's purpose should be re-evaluated — with
preedit rendering via cell data, a simplified signature of
`(pane_id, text, text_len, userdata)` may suffice.

---

## Appendix H: Changes from v0.7

**Cross-team revision**: Daemon behavioral content extracted to daemon design
docs v0.3 per cross-team request
(`draft/v1.0-r7/cross-team-requests/01-daemon-behavior-extraction.md`). The IME
contract now focuses on engine API, type definitions, and engine-internal
behavior. Daemon-side integration is defined in daemon design docs.

### H.1 Processing Pipeline Reduced to Phase 1 Only (I1)

**v0.7**: 01-overview described the full 3-phase pipeline (Phase 0: global
shortcuts, Phase 1: IME engine, Phase 2: ghostty integration).

**v0.8**: Only Phase 1 (IME engine processing) retained. Phases 0 and 2 replaced
with reference to daemon design docs.

### H.2 IME-Before-Keybindings Rationale Removed (I2)

**v0.7**: "Why IME Runs Before Keybindings" explaining daemon call ordering.

**v0.8**: Removed. This is a daemon architectural decision.

### H.3 Responsibility Matrix Reduced to IME-Side Only (I3)

**v0.7**: Responsibility matrix contained both IME engine and daemon
responsibilities (22 rows).

**v0.8**: Reduced to IME engine responsibilities only (5 rows).

### H.4 ghostty Integration Replaced with Reference (I4)

**v0.7**: 04-ghostty-integration contained 300+ lines covering ImeResult→ghostty
mapping, handleKeyEvent pseudocode, preedit clearing rules, HID mapping tables,
focus change handling, macOS/iOS IME suppression.

**v0.8**: Entire section replaced with brief reference to daemon design docs.
Memory ownership retained as it describes engine-internal buffer behavior.

### H.5 Wire-to-KeyEvent Decomposition Replaced with Reference (I9)

**v0.7**: 02-types design notes contained wire modifier bitmask decomposition
detail and CapsLock/NumLock handling rationale.

**v0.8**: Replaced with brief reference to daemon design docs. KeyEvent type
definition retained.

### H.6 Engine Lifecycle Doc Comments Updated (I5)

**v0.7**: vtable comments described when the daemon calls each method.

**v0.8**: Comments describe what the engine does when called (behavioral
contract). When/why the daemon calls them is referenced to daemon design docs.

### H.7 Session Persistence Reduced to Constructor Detail (I7)

**v0.7**: 05-extensibility contained full persistence schema, save/restore
timing, flush-on-save policy.

**v0.8**: Reduced to engine constructor accepting canonical `input_method`
string. Persistence procedures referenced to daemon design docs.

### H.8 C API Boundary Reduced to One-Liner (I8)

**v0.7**: Full discussion of no public C header, hypothetical future C API,
`itshell3.h` callback signatures.

**v0.8**: Reduced to: "libitshell3-ime exports a Zig API only; it has no public
C header."
