# Verification Round 1 Issues

**Round**: 1
**Date**: 2026-03-06
**Verifiers**: cross-ref-verifier (sonnet), terminology-verifier (sonnet), semantic-verifier (sonnet), history-guardian (opus)

---

## Confirmed Issues

### V1-01 (critical)

**Source documents**:
- `02-types.md` Section 3.2 (`preedit_changed` field definition)
- `03-engine-interface.md` Section 3.6 (`setActiveInputMethod` Case 1 return value)

**Description**: `preedit_changed` semantics are contradictory between the two sections. Section 3.2 defines `preedit_changed = true` only on actual preedit state transitions: null->non-null, non-null->null, or non-null->different-non-null. Under this definition, switching input method with no active composition (null->null) must return `preedit_changed = false`. However, Section 3.6 Case 1 mandates `preedit_changed = true` unconditionally for any switch to a different input method, including the null->null case. These two normative statements cannot both be satisfied.

**Expected correction**: Reconcile the two definitions. Either broaden Section 3.2's definition to include input-method-switch as a preedit-changed trigger (even when preedit remains null), or narrow Section 3.6 Case 1 to return `preedit_changed = false` when preedit was already null.

**Consensus note**: All four verifiers confirmed this is a genuine normative contradiction between two current spec sections. No historical-record defense applies — both are current normative text.

---

### V1-02 (critical)

**Source documents**:
- `design-resolutions-per-tab-engine.md` Resolution 1
- `99-appendices.md` Appendix B (v1 Scope)

**Description**: The initial/default input method for a newly created session is contradicted. Resolution 1 states: "Created on session creation: `HangulImeEngine.init(allocator, "direct")`" — explicitly using `"direct"` as the creation argument. Appendix B states: "HangulImeEngine with dubeolsik (`"korean_2set"`) as default." These are normative statements that directly contradict each other on what the engine's initial input method should be.

**Expected correction**: Clarify the distinction between "default engine type" (which engine implementation to instantiate) and "initial active input method" (what mode the engine starts in). If `"direct"` is the correct initial input method (engine starts in pass-through mode), update Appendix B to clarify that `"korean_2set"` refers to the engine's available language, not the startup mode.

**Consensus note**: All four verifiers confirmed this is a genuine normative contradiction. History-guardian confirmed both statements are current normative text (Appendix B is a v1 scope definition, not a historical changelog entry).

---

## Dismissed Issues

| ID | Original severity | Reason for dismissal |
|----|-------------------|----------------------|
| T-1 | critical | Appendix C headings use `setActiveLanguage` — historical record correct for v0.1/v0.2 era. Rename notes present in C.1 and Appendix F. |
| T-2 | minor | Appendix C.6 `handleLanguageSwitch` — historical record with rename note already present. |
| T-3 | critical | Appendix C.6 `active_language` — historical record; rename covered by Appendix F forward reference. |
| T-4 | critical | Appendix E.8 lists 6 `CompositionStates` including `empty` — inline note about removal already present. |
| T-5 | critical | Appendix E.7 heading uses `setActiveLanguage` — heading describes v0.2 change; rename note present in "Superseded by Appendix F" section. |
| T-6 | minor | Design resolutions metadata "per-tab engine" — verbatim quote of owner decision name. |
| T-8 | critical | Appendix H.10 vs E.7 — E.7 line 223 is a labeled v0.4 historical quote (correct for v0.4); line 227 is updated v0.6 rationale. Different temporal contexts, confirmed by checking v0.5 source. |
