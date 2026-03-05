# Handover: IME Interface Contract v0.5 -> v0.6 Revision

> **Date**: 2026-03-05
> **Author**: principal-architect
> **Target**: v0.6 revision team
> **Prerequisite reading**: `review-notes-01.md` (in `v0.4/` directory -- the issues that drove this revision)

---

## 1. What v0.5 Accomplished

v0.5 resolved all 5 open issues from the v0.4 review notes, plus an owner-raised follow-up on Traditional vs Simplified Chinese. Three required team discussion (3-0 unanimous consensus on all); two were mechanical fixes.

### 1.1 Composition State Prefix Convention Formalized (Issue 2.1)

**Decision: Hybrid C/D -- ISO 639-1 default, method-based where state graphs diverge.**

Normative rule added to Section 3.7: when a language has exactly one composition state graph shared by all its input method variants, use ISO 639-1 prefix (`ko_`, `ja_`). When a language has multiple input methods with distinct composition state graphs, use `{iso639}_{method}_` prefix (`zh_pinyin_`, `zh_bopomofo_`, `zh_cangjie_`). The discriminating factor is the composition model, not the region or locale.

Concrete application table added:

| Language | Prefix | Rationale |
|----------|--------|-----------|
| Korean | `ko_` (unchanged) | One state graph for all variants (2-set, 3-set, romaja, etc.) |
| Japanese | `ja_` | One state graph expected |
| Chinese Pinyin | `zh_pinyin_` | Distinct state graph from Bopomofo/Cangjie |
| Chinese Bopomofo | `zh_bopomofo_` | Distinct state graph |
| Chinese Cangjie | `zh_cangjie_` | Distinct state graph |

**Traditional vs Simplified clarification** (owner follow-up): When the same input method supports multiple character sets (e.g., Pinyin for both Traditional and Simplified Chinese), the composition state prefix reflects the state graph, not the character set. Character set selection is a configuration parameter of the engine, distinguished by the `input_method` identifier (e.g., `"chinese_pinyin_traditional"` vs `"chinese_pinyin_simplified"`), not by the composition state prefix.

Key evidence: libhangul's `HangulInputContext` uses the same 3-slot buffer (choseong/jungseong/jongseong) regardless of keyboard layout -- layout only changes the key-to-jamo mapping table. Chinese Pinyin/Bopomofo/Cangjie have genuinely distinct state vocabularies (zero shared states). Pinyin-Traditional and Pinyin-Simplified share the same state graph (only the candidate dictionary differs).

**Impact**: Zero `ko_` constants renamed. Settled decision preserved.

### 1.2 `"non_korean"` Removal Agreed for Protocol Doc 05 (Issue 2.4)

The team agreed (3-0) to remove the `"non_korean"` row from protocol doc 05 Section 3.1. A generic placeholder contradicts the method-based prefix convention -- future engines will define their own prefixed composition states (`ja_kana_composing`, `zh_pinyin_input`, etc.), never a catch-all `"non_korean"`. **Note**: This change is deferred to protocol v0.6. The required changes are documented in `protocol-changes-for-v06.md`. Protocol doc 05 v0.5 still contains `"non_korean"`.

### 1.3 `ko_vowel_only` Reachability Documented (Issue 2.5a)

Added reachability note to Section 3.7: `ko_vowel_only` is produced in 3-set (Sebeolsik) layouts where consonant and vowel keys are physically separated. In 2-set (Dubeolsik, v1 default), libhangul inserts an implicit leading consonant, producing `ko_syllable_no_tail` instead. The scenario matrix illustrates 2-set behavior and is not exhaustive.

### 1.4 `CompositionStates.empty` Removed (Issue 2.5b)

Removed `pub const empty = "empty"` from `CompositionStates`. `ImeResult.composition_state = null` is the canonical representation for no active composition. Having both `null` and `"empty"` was a bug surface (callers would need to check both). The corresponding changes to protocol doc 05 (Section 3.1 state table, PreeditStart JSON example, Section 3.3 transition table, Section 11.1 error recovery prose) are deferred to protocol v0.6 -- see `protocol-changes-for-v06.md`.

### 1.5 Mechanical Fixes (Issues 2.2, 2.3)

- **Issue 2.2**: Added `deactivate()` to the ImeResult doc comment invalidation list (Section 3.2, line 195). Was already present in Section 6 (Memory Ownership).
- **Issue 2.3**: Fixed broken cross-reference in Appendix E.9: `[F.6]` corrected to `[F.5]` (Session Persistence Simplified).

### 1.6 Verification Fixes (found during cross-verification)

Three additional issues found and fixed during the cross-verification round:
- **V-1**: Broken anchor in Section 3.7 `ko_vowel_only` note: `#32-imeresult-orthogonality-scenario-matrix` corrected to `#32-imeresult-output-from-ime`. Documented in Appendix G.6 of the contract.
- **V-2**: Protocol doc 05 Section 11.1: residual `empty` reference in error recovery prose. Deferred to protocol v0.6 -- see `protocol-changes-for-v06.md`.
- **V-3**: Protocol doc 05 Section 15 Open Questions: unprefixed state names and "enum" terminology. Deferred to protocol v0.6 -- see `protocol-changes-for-v06.md`.

IME contract changes (V-1) documented in Appendix G. Protocol doc changes (V-2, V-3) deferred to protocol v0.6.

---

## 2. Owner Decisions on Section 10 Open Questions

All four open questions in Section 10 have been decided by the owner (see `review-notes-02-owner-decisions.md`). The v0.6 revision must apply these decisions to the contract.

### 2.1 Hanja Key — Excluded (Q1)

**Decision: Do not support Hanja conversion in Korean IME mode.**

Korean Hanja conversion is explicitly excluded (not deferred). The candidate callback mechanism (Section 7) remains for future non-Korean engines (Chinese candidate selection), but will not be used for Korean.

**v0.6 action**: Remove Section 10 Q1. No other contract changes needed — Section 7 stays as-is.

### 2.2 Dead Keys — Separate Engine (Q2)

**Decision: European dead key composition must be a separate engine (e.g., `"european_deadkey"`), NOT added to direct mode.**

Direct mode remains the simplest possible passthrough (HID → ASCII, zero composition).

**v0.6 action**: Replace Section 10 Q2 with the settled decision.

### 2.3 Per-Pane → Per-Tab Engine Singleton (Q3)

**Decision: Global singleton engine instance per tab (session), not per-pane.**

All panes within a tab share the same input method state. Switching to Korean in one pane affects all panes in the same tab.

**v0.6 action** (architectural change):
- Update engine ownership model (one engine per tab/session, not per pane)
- Update session persistence (one `input_method` per tab, not per pane)
- Clarify preedit exclusivity (still one active preedit per focused pane, but the engine is shared)
- Remove Section 10 Q3 and replace with the settled decision

### 2.4 macOS IME Suppression — PoC Complete (Q4)

**Decision: PoC validates feasibility. The approach is confirmed.**

The PoC (`poc/macos-ime-suppression/`) validated all assumptions:
- Not calling `interpretKeyEvents:` is sufficient to bypass OS IME — no other suppression technique needed
- `performKeyEquivalent:` correctly handles system shortcuts (Cmd+Q, Cmd+H, etc.)
- `NSTextInputClient` can be implemented for clipboard/services/accessibility without interfering with keyboard input
- `NSEvent.keyCode` is physical key position (unchanged regardless of macOS input source), which is exactly what libitshell3-ime needs

**v0.6 action**: Replace Section 10 Q4 with the settled decision and reference the PoC findings.

### 2.5 Potential Future Review Triggers

These are not open items but situations that would trigger further revision:

- **Implementation begins**: Actual Zig code may reveal edge cases not covered by the spec (e.g., libhangul buffer behavior under rapid keystroke bursts, exact preedit_changed semantics for compound operations).
- **3-set layout support**: When 3-set keyboard layouts are implemented (Phase 7), verify that `ko_vowel_only` transitions behave as documented.
- **Chinese/Japanese engine design**: When Chinese or Japanese engines are designed, the composition state prefix convention and candidate callback design (Section 7) will need to be exercised against real requirements.

---

## 3. Protocol Doc Coordination Note

Protocol doc 05 (`05-cjk-preedit-protocol.md`) requires the following changes, which are **deferred to protocol v0.6**. These changes are agreed (3-0) but not yet applied to protocol doc 05 v0.5. See `protocol-changes-for-v06.md` for the full specification.

| Change | Location | Issue | Status |
|--------|----------|-------|--------|
| `"non_korean"` row removed | Section 3.1 state table | Issue 2.4 | Deferred to v0.6 |
| `"empty"` row removed | Section 3.1 state table | Issue 2.5b | Deferred to v0.6 |
| PreeditStart `composition_state` field removed | Section 2.1 | Issue 2.5b | Deferred to v0.6 |
| Transition table `empty` -> `null` | Section 3.3 | Issue 2.5b (V-2) | Deferred to v0.6 |
| Error recovery `empty` -> `null` | Section 11.1 | Issue 2.5b (V-2) | Deferred to v0.6 |
| Naming convention cross-reference added | Section 3.1 | Issue 2.1 | Deferred to v0.6 |
| `ko_vowel_only` 2-set/3-set note added | Section 3.1 | Issue 2.5a | Deferred to v0.6 |
| Open Questions prefixed names + terminology | Section 15 | V-3 | Deferred to v0.6 |

The protocol team should apply these when producing protocol doc 05 v0.6. The IME contract Section 3.7 is the normative source for composition state naming conventions.

---

## 4. File Locations

### IME Contract

| Document | Path |
|----------|------|
| IME contract v0.5 (current) | `docs/libitshell3-ime/02-design-docs/interface-contract/v0.5/01-interface-contract.md` |
| Review notes (resolved) | `docs/libitshell3-ime/02-design-docs/interface-contract/v0.4/review-notes-01.md` |
| This handover | `docs/libitshell3-ime/02-design-docs/interface-contract/v0.5/handover-for-v06-revision.md` |
| Owner decisions on open questions | `docs/libitshell3-ime/02-design-docs/interface-contract/v0.5/review-notes-02-owner-decisions.md` |

### PoC

| Document | Path |
|----------|------|
| macOS IME suppression PoC source | `poc/macos-ime-suppression/PoC.m` |
| macOS IME suppression PoC findings | `poc/macos-ime-suppression/README.md` |

### Protocol Docs (v0.5, cross-reference targets)

| Document | Path |
|----------|------|
| Protocol doc 05 (CJK preedit) | `docs/libitshell3/02-design-docs/server-client-protocols/v0.5/05-cjk-preedit-protocol.md` |
| Protocol doc 04 (input/renderstate) | `docs/libitshell3/02-design-docs/server-client-protocols/v0.5/04-input-and-renderstate.md` |
| Protocol doc 06 (flow control) | `docs/libitshell3/02-design-docs/server-client-protocols/v0.5/06-flow-control-and-auxiliary.md` |

### Earlier Artifacts

| Document | Path |
|----------|------|
| v0.4 contract | `docs/libitshell3-ime/02-design-docs/interface-contract/v0.4/01-interface-contract.md` |
| v0.4 handover | `docs/libitshell3-ime/02-design-docs/interface-contract/v0.4/handover-for-v05-revision.md` |
| v0.4 identifier consensus handover | `docs/libitshell3-ime/02-design-docs/interface-contract/v0.4/handover-identifier-consensus.md` |
| v0.3 cross-review notes (IME side) | `docs/libitshell3-ime/02-design-docs/interface-contract/v0.3/review-notes-cross-review.md` |
| v0.3 cross-review notes (protocol side) | `docs/libitshell3/02-design-docs/server-client-protocols/v0.4/review-notes-cross-review-ime.md` |

### PoC

| Document | Path |
|----------|------|
| PoC source | `poc/ime-ghostty-real/poc-ghostty-real.m` |
| PoC findings | `poc/ime-ghostty-real/FINDINGS.md` |
