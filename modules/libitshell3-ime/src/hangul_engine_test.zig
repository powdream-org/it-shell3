//! Integration tests for HangulImeEngine covering the full v0.7 scenario matrix.
//! 56 tests across 16 categories (A-P) from the implementation plan §3.1.
//!
//! These tests exercise the real libhangul C library through HangulImeEngine,
//! verifying Korean Hangul composition, flush behavior, backspace jamo undo,
//! modifier handling, input method switching, and lifecycle management.

const std = @import("std");
const testing = std.testing;

const types = @import("types.zig");
const KeyEvent = types.KeyEvent;
const ImeResult = types.ImeResult;
const hangul_engine = @import("hangul_engine.zig");
const HangulImeEngine = hangul_engine.HangulImeEngine;

// ============================================================
// HID keycode constants (USB HID Usage Table, Keyboard Page 0x07)
// ============================================================
const HID = struct {
    // Letters (a=0x04 .. z=0x1D)
    const a = 0x04;
    const b = 0x05;
    const c = 0x06;
    const d = 0x07;
    const e = 0x08;
    const f = 0x09;
    const g = 0x0A;
    const h = 0x0B;
    const i = 0x0C;
    const j = 0x0D;
    const k = 0x0E;
    const l = 0x0F;
    const m = 0x10;
    const n = 0x11;
    const o = 0x12;
    const p = 0x13;
    const q = 0x14;
    const r = 0x15;
    const s = 0x16;
    const t = 0x17;
    const u = 0x18;
    const v = 0x19;
    const w = 0x1A;
    const x = 0x1B;
    const y = 0x1C;
    const z = 0x1D;

    // Digits
    const @"1" = 0x1E;
    const @"2" = 0x1F;

    // Punctuation
    const period = 0x37; // '.'

    // Special keys
    const enter = 0x28;
    const escape = 0x29;
    const backspace = 0x2A;
    const tab = 0x2B;
    const space = 0x2C;

    // Arrow keys
    const right = 0x4F;
    const left = 0x50;
    const down = 0x51;
    const up = 0x52;
};

// ============================================================
// Helper functions
// ============================================================

fn press(hid_keycode: u8) KeyEvent {
    return .{
        .hid_keycode = hid_keycode,
        .modifiers = .{},
        .shift = false,
        .action = .press,
    };
}

fn shiftPress(hid_keycode: u8) KeyEvent {
    return .{
        .hid_keycode = hid_keycode,
        .modifiers = .{},
        .shift = true,
        .action = .press,
    };
}

fn ctrlPress(hid_keycode: u8) KeyEvent {
    return .{
        .hid_keycode = hid_keycode,
        .modifiers = .{ .ctrl = true },
        .shift = false,
        .action = .press,
    };
}

fn altPress(hid_keycode: u8) KeyEvent {
    return .{
        .hid_keycode = hid_keycode,
        .modifiers = .{ .alt = true },
        .shift = false,
        .action = .press,
    };
}

fn superPress(hid_keycode: u8) KeyEvent {
    return .{
        .hid_keycode = hid_keycode,
        .modifiers = .{ .super_key = true },
        .shift = false,
        .action = .press,
    };
}

fn releaseKey(hid_keycode: u8) KeyEvent {
    return .{
        .hid_keycode = hid_keycode,
        .modifiers = .{},
        .shift = false,
        .action = .release,
    };
}

fn repeatKey(hid_keycode: u8) KeyEvent {
    return .{
        .hid_keycode = hid_keycode,
        .modifiers = .{},
        .shift = false,
        .action = .repeat,
    };
}

fn createDirectEngine() !HangulImeEngine {
    return HangulImeEngine.init("direct");
}

fn createKoreanEngine() !HangulImeEngine {
    return HangulImeEngine.init("korean_2set");
}

/// Assert that committed_text matches the expected UTF-8 string (or null).
fn expectCommitted(result: ImeResult, expected: ?[]const u8) !void {
    if (expected) |exp| {
        try testing.expect(result.committed_text != null);
        try testing.expectEqualStrings(exp, result.committed_text.?);
    } else {
        try testing.expectEqual(@as(?[]const u8, null), result.committed_text);
    }
}

/// Assert that preedit_text matches the expected UTF-8 string (or null).
fn expectPreedit(result: ImeResult, expected: ?[]const u8) !void {
    if (expected) |exp| {
        try testing.expect(result.preedit_text != null);
        try testing.expectEqualStrings(exp, result.preedit_text.?);
    } else {
        try testing.expectEqual(@as(?[]const u8, null), result.preedit_text);
    }
}

/// Assert that forward_key is set (non-null) and matches the expected HID keycode.
fn expectForward(result: ImeResult, expected_hid: ?u8) !void {
    if (expected_hid) |hid| {
        try testing.expect(result.forward_key != null);
        try testing.expectEqual(hid, result.forward_key.?.hid_keycode);
    } else {
        try testing.expectEqual(@as(?KeyEvent, null), result.forward_key);
    }
}

/// Assert preedit_changed flag.
fn expectPreeditChanged(result: ImeResult, expected: bool) !void {
    try testing.expectEqual(expected, result.preedit_changed);
}

// ============================================================
// A. Direct mode (7 tests)
// ============================================================

test "A1: direct_printable_lowercase" {
    var eng = try createDirectEngine();
    defer eng.deinit();
    const ime = eng.engine();
    const r = ime.processKey(press(HID.a));
    try expectCommitted(r, "a");
    try expectPreedit(r, null);
    try expectForward(r, null);
    try expectPreeditChanged(r, false);
}

test "A2: direct_printable_uppercase" {
    var eng = try createDirectEngine();
    defer eng.deinit();
    const ime = eng.engine();
    const r = ime.processKey(shiftPress(HID.a));
    try expectCommitted(r, "A");
    try expectPreedit(r, null);
    try expectForward(r, null);
    try expectPreeditChanged(r, false);
}

test "A3: direct_enter" {
    var eng = try createDirectEngine();
    defer eng.deinit();
    const ime = eng.engine();
    const r = ime.processKey(press(HID.enter));
    try expectCommitted(r, null);
    try expectPreedit(r, null);
    try expectForward(r, HID.enter);
    try expectPreeditChanged(r, false);
}

test "A4: direct_space" {
    var eng = try createDirectEngine();
    defer eng.deinit();
    const ime = eng.engine();
    const r = ime.processKey(press(HID.space));
    try expectCommitted(r, null);
    try expectPreedit(r, null);
    try expectForward(r, HID.space);
    try expectPreeditChanged(r, false);
}

test "A5: direct_ctrl_c" {
    var eng = try createDirectEngine();
    defer eng.deinit();
    const ime = eng.engine();
    const r = ime.processKey(ctrlPress(HID.c));
    try expectCommitted(r, null);
    try expectPreedit(r, null);
    try expectForward(r, HID.c);
    try expectPreeditChanged(r, false);
}

test "A6: direct_arrow" {
    var eng = try createDirectEngine();
    defer eng.deinit();
    const ime = eng.engine();
    const r = ime.processKey(press(HID.right));
    try expectCommitted(r, null);
    try expectPreedit(r, null);
    try expectForward(r, HID.right);
    try expectPreeditChanged(r, false);
}

test "A7: direct_escape" {
    var eng = try createDirectEngine();
    defer eng.deinit();
    const ime = eng.engine();
    const r = ime.processKey(press(HID.escape));
    try expectCommitted(r, null);
    try expectPreedit(r, null);
    try expectForward(r, HID.escape);
    try expectPreeditChanged(r, false);
}

// ============================================================
// B. Korean basic composition (5 tests)
// ============================================================

test "B1: korean_initial_consonant" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // r -> ㄱ
    const r = ime.processKey(press(HID.r));
    try expectCommitted(r, null);
    try expectPreedit(r, "ㄱ");
    try expectForward(r, null);
    try expectPreeditChanged(r, true);
}

test "B2: korean_add_vowel" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // r -> ㄱ
    _ = ime.processKey(press(HID.r));
    // k -> 가
    const r = ime.processKey(press(HID.k));
    try expectCommitted(r, null);
    try expectPreedit(r, "가");
    try expectForward(r, null);
    try expectPreeditChanged(r, true);
}

test "B3: korean_add_tail" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // r -> ㄱ, k -> 가
    _ = ime.processKey(press(HID.r));
    _ = ime.processKey(press(HID.k));
    // s -> 간 (ㄴ as jongseong)
    const r = ime.processKey(press(HID.s));
    try expectCommitted(r, null);
    try expectPreedit(r, "간");
    try expectForward(r, null);
    try expectPreeditChanged(r, true);
}

test "B4: korean_syllable_break" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // r→k→s = 간
    _ = ime.processKey(press(HID.r));
    _ = ime.processKey(press(HID.k));
    _ = ime.processKey(press(HID.s));
    // k -> commit 간, preedit 가 (ㄴ stays as jong, new syllable starts with vowel steals nothing here;
    //   actually: 간 + ㅏ -> ㄴ is stolen -> commit 가, preedit 나? No.
    //   Let me re-check: 간(ㄱ+ㅏ+ㄴ) + ㅏ -> ㄴ is stolen -> commit "가", preedit "나"
    //   Wait, the plan says: r→k→s→k -> commit "간", preedit "가"
    //   But that's syllable break by adding a NEW consonant that starts a new syllable.
    //   Actually r→k→s→k: 간 + k(ㅏ) -> tail stealing: ㄴ moves to next syllable -> commit "가", preedit "나"
    //   Hmm, but the plan §3.1 says commit "간", preedit "가" for category B4.
    //   Let me re-check: In dubeolsik, 'k' maps to ㅏ. After 간(ㄱ+ㅏ+ㄴ), pressing ㅏ:
    //   libhangul does tail stealing: ㄴ becomes choseong of new syllable -> commit "가", preedit "나"
    //   But the plan says commit "간", preedit "가" for B4 AND category E1 also has r→k→s→k.
    //   Let me trust the plan's B4: commit "간", preedit "가". Actually wait...
    //   B4 name is "syllable_break" and E1 is "tail_stealing_simple" with the SAME sequence.
    //   The plan says B4: r→k→s→k -> commit "간", preedit "가"
    //   But E1 says: r→k→s→k -> commit "간", preedit "가" with note "ㄴ stays, ㅏ starts new 가"
    //   That seems wrong for tail stealing. Let me check what libhangul actually does:
    //   간 + ㅏ: the ㄴ (jongseong) is stolen as choseong of next syllable -> commit "가", preedit "나"
    //   The plan may have an error. Let me test what libhangul ACTUALLY produces and match that.
    //   For now, I'll use what libhangul produces: commit "가", preedit "나"
    //   Actually, looking more carefully: the plan says for B4:
    //   "korean_syllable_break | r→k→s→k | commit '간', preedit '가'"
    //   This would be the case if the LAST key is a CONSONANT not a vowel.
    //   'k' in dubeolsik maps to ㅏ (vowel), not ㄱ. HID 0x0E = 'k' = ㅏ.
    //   So this IS tail stealing. Let me re-read... the plan says the test name is
    //   "syllable_break" but the description mentions "r→k→s→k" which is ambiguous.
    //   HID.k = 0x0E which maps to ASCII 'k' which in Korean 2-set maps to ㅏ.
    //   So: ㄱ+ㅏ+ㄴ+ㅏ = 가+나 (tail stealing). commit "가", preedit "나".
    //
    //   HOWEVER: The plan test B4 name is "korean_syllable_break" and the expected
    //   is commit "간", preedit "가". This would happen with a CONSONANT like ㄱ(r):
    //   r→k→s→r = ㄱ+ㅏ+ㄴ+ㄱ. After 간, adding ㄱ: if ㄴ+ㄱ can form compound
    //   jongseong (ㄵ? no, ㄵ is ㄴ+ㅈ). ㄴ+ㄱ is not a compound jongseong.
    //   So ㄱ starts a new syllable: commit "간", preedit "ㄱ".
    //   That's also not "가"...
    //
    //   I think the plan's B4 sequence should be r→k→s→r (not r→k→s→k).
    //   r→k→s→r: 간 + ㄱ -> commit "간", preedit "ㄱ" (not "가" either).
    //   Or maybe the NEXT key 'k' means: r→k→s→ then TWO more keys k→something.
    //   Actually re-reading: "r→k→s→k" where the last k would map to ㅏ.
    //   간 + ㅏ -> tail stealing -> commit "가", preedit "나".
    //
    //   I'll trust libhangul's actual behavior over the plan's expected values.
    //   Let me write the test to match libhangul: commit "가", preedit "나".
    const r = ime.processKey(press(HID.k));
    try expectCommitted(r, "가");
    try expectPreedit(r, "나");
    try expectForward(r, null);
    try expectPreeditChanged(r, true);
}

test "B5: korean_vowel_only" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // k -> ㅏ (libhangul shows vowel as preedit)
    const r = ime.processKey(press(HID.k));
    try expectCommitted(r, null);
    try expectPreedit(r, "ㅏ");
    try expectForward(r, null);
    try expectPreeditChanged(r, true);
}

// ============================================================
// C. Shift 겹자음 (double consonants via Shift) (4 tests)
// ============================================================

test "C1: korean_double_choseong_gg" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // Shift+r -> ㄲ
    const r = ime.processKey(shiftPress(HID.r));
    try expectCommitted(r, null);
    try expectPreedit(r, "ㄲ");
    try expectForward(r, null);
    try expectPreeditChanged(r, true);
}

test "C2: korean_double_choseong_dd" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // Shift+e -> ㄸ (e maps to ㄷ, Shift+e maps to ㄸ)
    const r = ime.processKey(shiftPress(HID.e));
    try expectCommitted(r, null);
    try expectPreedit(r, "ㄸ");
    try expectForward(r, null);
    try expectPreeditChanged(r, true);
}

test "C3: korean_double_choseong_in_syllable" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // Shift+r -> ㄲ, then k -> 까
    _ = ime.processKey(shiftPress(HID.r));
    const r = ime.processKey(press(HID.k));
    try expectCommitted(r, null);
    try expectPreedit(r, "까");
    try expectForward(r, null);
    try expectPreeditChanged(r, true);
}

test "C4: korean_double_choseong_ss" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // Shift+t -> ㅆ (t maps to ㅅ, Shift+t maps to ㅆ), then k -> 싸
    _ = ime.processKey(shiftPress(HID.t));
    const r = ime.processKey(press(HID.k));
    try expectCommitted(r, null);
    try expectPreedit(r, "싸");
    try expectForward(r, null);
    try expectPreeditChanged(r, true);
}

// ============================================================
// D. 겹받침 (compound jongseong) (3 tests)
// ============================================================

test "D1: korean_compound_jong_rg" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // e→k→f→r: ㄷ+ㅏ+ㄹ+ㄱ = 닭 (ㄺ compound jongseong)
    _ = ime.processKey(press(HID.e)); // ㄷ
    _ = ime.processKey(press(HID.k)); // 다
    _ = ime.processKey(press(HID.f)); // 달
    const r = ime.processKey(press(HID.r)); // 닭 (ㄹ+ㄱ = ㄺ)
    try expectCommitted(r, null);
    try expectPreedit(r, "닭");
    try expectForward(r, null);
    try expectPreeditChanged(r, true);
}

test "D2: korean_compound_jong_bs" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // d→j→q→t: ㅇ+ㅓ+ㅂ+ㅅ = 없 (ㅄ compound jongseong)
    _ = ime.processKey(press(HID.d)); // ㅇ
    _ = ime.processKey(press(HID.j)); // 어
    _ = ime.processKey(press(HID.q)); // 업
    const r = ime.processKey(press(HID.t)); // 없 (ㅂ+ㅅ = ㅄ)
    try expectCommitted(r, null);
    try expectPreedit(r, "없");
    try expectForward(r, null);
    try expectPreeditChanged(r, true);
}

test "D3: korean_compound_jong_lg" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // d→l→f→r: ㅇ+ㅣ+ㄹ+ㄱ = 읽 (ㄺ compound jongseong)
    _ = ime.processKey(press(HID.d)); // ㅇ
    _ = ime.processKey(press(HID.l)); // 이
    _ = ime.processKey(press(HID.f)); // 일
    const r = ime.processKey(press(HID.r)); // 읽 (ㄹ+ㄱ = ㄺ)
    try expectCommitted(r, null);
    try expectPreedit(r, "읽");
    try expectForward(r, null);
    try expectPreeditChanged(r, true);
}

// ============================================================
// E. 받침 탈취 (tail stealing / onset reassignment) (3 tests)
// ============================================================

test "E1: korean_tail_stealing_simple" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // r→k→s = 간, then k(ㅏ): tail stealing -> commit "가", preedit "나"
    _ = ime.processKey(press(HID.r)); // ㄱ
    _ = ime.processKey(press(HID.k)); // 가
    _ = ime.processKey(press(HID.s)); // 간
    const r = ime.processKey(press(HID.k)); // commit 가, preedit 나
    try expectCommitted(r, "가");
    try expectPreedit(r, "나");
    try expectForward(r, null);
    try expectPreeditChanged(r, true);
}

test "E2: korean_tail_stealing_compound" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // e→k→f→r = 닭, then h(ㅗ): compound ㄺ splits, ㄱ stolen
    // -> commit "달", preedit "고"
    _ = ime.processKey(press(HID.e)); // ㄷ
    _ = ime.processKey(press(HID.k)); // 다
    _ = ime.processKey(press(HID.f)); // 달
    _ = ime.processKey(press(HID.r)); // 닭
    const r = ime.processKey(press(HID.h)); // commit 달, preedit 고
    try expectCommitted(r, "달");
    try expectPreedit(r, "고");
    try expectForward(r, null);
    try expectPreeditChanged(r, true);
}

test "E3: korean_full_word_dalgogi" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // Full sequence for "닭고기": e→k→f→r→h→r→l
    _ = ime.processKey(press(HID.e)); // ㄷ
    _ = ime.processKey(press(HID.k)); // 다
    _ = ime.processKey(press(HID.f)); // 달
    _ = ime.processKey(press(HID.r)); // 닭

    // h(ㅗ): compound split, commit "달", preedit "고"
    var r = ime.processKey(press(HID.h));
    try expectCommitted(r, "달");
    try expectPreedit(r, "고");

    // r(ㄱ): 고+ㄱ = 곡 (jongseong)
    r = ime.processKey(press(HID.r));
    try expectPreedit(r, "곡");

    // l(ㅣ): tail stealing -> commit "고", preedit "기"
    r = ime.processKey(press(HID.l));
    try expectCommitted(r, "고");
    try expectPreedit(r, "기");
}

// ============================================================
// F. 연속 입력 (multi-syllable sequences) (3 tests)
// ============================================================

test "F1: korean_word_hangul" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // "한글": g→k→s→r→m→f
    // g(ㅎ)→k(ㅏ)→s(ㄴ) = 한
    _ = ime.processKey(press(HID.g)); // ㅎ
    _ = ime.processKey(press(HID.k)); // 하
    var r = ime.processKey(press(HID.s)); // 한
    try expectPreedit(r, "한");

    // r(ㄱ): new consonant after 한. ㄴ+ㄱ is not compound jong.
    // So this might start new syllable or... let me check:
    // Actually 한 has jongseong ㄴ. Adding ㄱ: ㄴ+ㄱ -> not a compound jongseong.
    // So ㄱ starts a new syllable: commit "한", preedit "ㄱ"
    r = ime.processKey(press(HID.r));
    try expectCommitted(r, "한");
    try expectPreedit(r, "ㄱ");

    // m(ㅡ): ㄱ+ㅡ = 그
    r = ime.processKey(press(HID.m));
    try expectPreedit(r, "그");

    // f(ㄹ): 그+ㄹ = 글 (jongseong)
    r = ime.processKey(press(HID.f));
    try expectPreedit(r, "글");
}

test "F2: korean_word_sarang" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // "사랑": t→k→f→k→s→r
    // t(ㅅ)→k(ㅏ) = 사
    _ = ime.processKey(press(HID.t)); // ㅅ
    _ = ime.processKey(press(HID.k)); // 사

    // f(ㄹ): 사+ㄹ = 살 (jongseong)
    var r = ime.processKey(press(HID.f));
    try expectPreedit(r, "살");

    // k(ㅏ): tail stealing -> commit "사", preedit "라"
    r = ime.processKey(press(HID.k));
    try expectCommitted(r, "사");
    try expectPreedit(r, "라");

    // s(ㄴ): 라+ㄴ = 란
    r = ime.processKey(press(HID.s));
    try expectPreedit(r, "란");

    // r(ㄱ): ㄴ+ㄱ is not compound jong -> commit "란", preedit "ㄱ"
    // Wait: but the expected result is "사랑". Let me reconsider.
    // "사랑" = 사 + 랑. So after "라", adding ㄴ(s) gives "란", then ㄱ(r)?
    // That gives "란" + ㄱ = new syllable. That would be 사란ㄱ, not 사랑.
    // To get "랑": ㄹ+ㅏ+ㅇ. So after "라", we need ㅇ(d), not ㄴ(s).
    // The plan says: t→k→f→k→s→r for "사랑" but that seems wrong for the word.
    // "사랑" = ㅅ+ㅏ+ㄹ+ㅏ+ㅇ = t→k→f→k→d
    // The plan sequence t→k→f→k→s→r may produce something different.
    // Let me follow the plan's SEQUENCE and verify libhangul's actual output.
    // After 라(la) + s(ㄴ) = 란. Then r(ㄱ) -> ㄴ+ㄱ not compound -> commit "란", preedit "ㄱ"
    // I'll test what the plan sequence actually produces.
    r = ime.processKey(press(HID.r));
    // ㄴ+ㄱ is not a compound jongseong, so ㄱ starts new syllable
    try expectCommitted(r, "란");
    try expectPreedit(r, "ㄱ");
}

test "F3: korean_three_syllables" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // r→k→s→k→e→k: sequence producing multiple syllables
    // r(ㄱ)→k(ㅏ)→s(ㄴ) = 간
    _ = ime.processKey(press(HID.r)); // ㄱ
    _ = ime.processKey(press(HID.k)); // 가
    _ = ime.processKey(press(HID.s)); // 간

    // k(ㅏ): tail stealing -> commit "가", preedit "나"
    var r = ime.processKey(press(HID.k));
    try expectCommitted(r, "가");
    try expectPreedit(r, "나");

    // e(ㄷ): ㄴ stays as jong? No, 나 has no jongseong. So:
    // 나 + ㄷ: ㄷ becomes jongseong -> 낟? Actually ㄷ CAN be jongseong -> 낟
    // Hmm, let me think. 나(ㄴ+ㅏ) + ㄷ -> 낟? Or does ㄷ start new syllable?
    // In dubeolsik, consonant after CV syllable becomes jongseong: 나+ㄷ = 낟
    // But ㄷ as jongseong... yes ㄷ is a valid jongseong.
    r = ime.processKey(press(HID.e));
    // 나 + ㄷ(jongseong) = likely "낟" or libhangul may handle differently
    // Let's check: 나(ㄴ+ㅏ) + ㄷ -> jongseong added -> Unicode syllable with ㄴ+ㅏ+ㄷ
    // = 0xAC00 + (2*21+0)*28 + 7 = ... Actually the syllable 낟 may not be common but is valid.
    // The test just verifies multi-syllable flow, exact char depends on libhangul.

    // k(ㅏ): tail stealing -> commit "나" (or "낟" without ㄷ), preedit "다"
    r = ime.processKey(press(HID.k));
    try expectPreedit(r, "다");
    try expectPreeditChanged(r, true);
}

// ============================================================
// G. Space 띄어쓰기 (4 tests)
// ============================================================

test "G1: flush_space_during_composition" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // r→k→s = 간, then Space
    _ = ime.processKey(press(HID.r));
    _ = ime.processKey(press(HID.k));
    _ = ime.processKey(press(HID.s));
    const r = ime.processKey(press(HID.space));
    try expectCommitted(r, "간");
    try expectPreedit(r, null);
    try expectForward(r, HID.space);
    try expectPreeditChanged(r, true);
}

test "G2: space_after_committed" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // Compose and flush first
    _ = ime.processKey(press(HID.r));
    _ = ime.processKey(press(HID.k));
    _ = ime.processKey(press(HID.enter)); // flush 가, forward Enter
    // Now press Space with no active composition
    const r = ime.processKey(press(HID.space));
    try expectCommitted(r, null);
    try expectPreedit(r, null);
    try expectForward(r, HID.space);
}

test "G3: space_then_continue" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // r→k = 가, Space flushes, then r→k = new 가
    _ = ime.processKey(press(HID.r));
    _ = ime.processKey(press(HID.k));

    var r = ime.processKey(press(HID.space));
    try expectCommitted(r, "가");
    try expectForward(r, HID.space);

    // Start new composition
    _ = ime.processKey(press(HID.r));
    r = ime.processKey(press(HID.k));
    try expectPreedit(r, "가");
    try expectCommitted(r, null);
}

test "G4: space_empty_composition" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // Space with no composition active
    const r = ime.processKey(press(HID.space));
    try expectCommitted(r, null);
    try expectPreedit(r, null);
    try expectForward(r, HID.space);
    try expectPreeditChanged(r, false);
}

// ============================================================
// H. Backspace 자소 삭제 (5 tests)
// ============================================================

test "H1: backspace_jamo_undo_chain" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // r→k→s = 간
    _ = ime.processKey(press(HID.r));
    _ = ime.processKey(press(HID.k));
    _ = ime.processKey(press(HID.s));

    // BS: 간→가
    var r = ime.processKey(press(HID.backspace));
    try expectPreedit(r, "가");
    try expectCommitted(r, null);
    try expectForward(r, null);
    try expectPreeditChanged(r, true);

    // BS: 가→ㄱ
    r = ime.processKey(press(HID.backspace));
    try expectPreedit(r, "ㄱ");
    try expectCommitted(r, null);
    try expectForward(r, null);
    try expectPreeditChanged(r, true);

    // BS: ㄱ→empty
    r = ime.processKey(press(HID.backspace));
    try expectPreedit(r, null);
    try expectCommitted(r, null);
    try expectForward(r, null);
    try expectPreeditChanged(r, true);
}

test "H2: backspace_from_compound_jong" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // e→k→f→r = 닭 (compound ㄺ)
    _ = ime.processKey(press(HID.e));
    _ = ime.processKey(press(HID.k));
    _ = ime.processKey(press(HID.f));
    _ = ime.processKey(press(HID.r));

    // BS: 닭→달 (compound ㄺ → ㄹ)
    const r = ime.processKey(press(HID.backspace));
    try expectPreedit(r, "달");
    try expectCommitted(r, null);
    try expectForward(r, null);
    try expectPreeditChanged(r, true);
}

test "H3: backspace_empty_forward" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // Backspace with no composition -> forward
    const r = ime.processKey(press(HID.backspace));
    try expectCommitted(r, null);
    try expectPreedit(r, null);
    try expectForward(r, HID.backspace);
    try expectPreeditChanged(r, false);
}

test "H4: backspace_after_syllable_committed" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // r→k→s→k: commit syllable, then BS on new preedit
    // r→k→s = 간
    _ = ime.processKey(press(HID.r));
    _ = ime.processKey(press(HID.k));
    _ = ime.processKey(press(HID.s));

    // k(ㅏ): tail stealing -> commit "가", preedit "나"
    var r = ime.processKey(press(HID.k));
    try expectCommitted(r, "가");
    try expectPreedit(r, "나");

    // BS: preedit "나" -> undo -> depends on libhangul stack
    // After tail stealing, the new syllable is 나(ㄴ+ㅏ). BS removes last jamo (ㅏ) -> preedit "ㄴ"
    r = ime.processKey(press(HID.backspace));
    try expectPreedit(r, "ㄴ");
    try expectCommitted(r, null);
    try expectForward(r, null);
}

test "H5: backspace_to_empty_then_forward" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // r = ㄱ, BS = empty, BS = forward
    _ = ime.processKey(press(HID.r));

    var r = ime.processKey(press(HID.backspace));
    try expectPreedit(r, null);
    try expectCommitted(r, null);
    try expectForward(r, null);
    try expectPreeditChanged(r, true);

    r = ime.processKey(press(HID.backspace));
    try expectPreedit(r, null);
    try expectCommitted(r, null);
    try expectForward(r, HID.backspace);
    try expectPreeditChanged(r, false);
}

// ============================================================
// I. hangul_ic_process returns false (2 tests)
// ============================================================

test "I1: process_false_period" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // g(ㅎ) then '.' (period) — libhangul rejects period
    _ = ime.processKey(press(HID.g)); // preedit ㅎ
    const r = ime.processKey(press(HID.period));
    // Period not consumed: flush ㅎ, forward period
    try expectCommitted(r, "ㅎ");
    try expectPreedit(r, null);
    try expectForward(r, HID.period);
    try expectPreeditChanged(r, true);
}

test "I2: process_false_number" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // g→k = 하, then '1' — libhangul rejects number
    _ = ime.processKey(press(HID.g));
    _ = ime.processKey(press(HID.k));
    const r = ime.processKey(press(HID.@"1"));
    // Number not consumed: flush 하, forward '1'
    try expectCommitted(r, "하");
    try expectPreedit(r, null);
    try expectForward(r, HID.@"1");
    try expectPreeditChanged(r, true);
}

// ============================================================
// J. Modifier flush (3 tests)
// ============================================================

test "J1: flush_ctrl_c" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // r→k = 가, then Ctrl+C
    _ = ime.processKey(press(HID.r));
    _ = ime.processKey(press(HID.k));
    const r = ime.processKey(ctrlPress(HID.c));
    try expectCommitted(r, "가");
    try expectPreedit(r, null);
    try expectForward(r, HID.c);
    try expectPreeditChanged(r, true);
}

test "J2: flush_alt_key" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // r→k = 가, then Alt+x
    _ = ime.processKey(press(HID.r));
    _ = ime.processKey(press(HID.k));
    const r = ime.processKey(altPress(HID.x));
    try expectCommitted(r, "가");
    try expectPreedit(r, null);
    try expectForward(r, HID.x);
    try expectPreeditChanged(r, true);
}

test "J3: flush_super_key" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // r→k = 가, then Cmd+s
    _ = ime.processKey(press(HID.r));
    _ = ime.processKey(press(HID.k));
    const r = ime.processKey(superPress(HID.s));
    try expectCommitted(r, "가");
    try expectPreedit(r, null);
    try expectForward(r, HID.s);
    try expectPreeditChanged(r, true);
}

// ============================================================
// K. Special key flush (5 tests)
// ============================================================

test "K1: flush_enter" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // r→k = 가, then Enter
    _ = ime.processKey(press(HID.r));
    _ = ime.processKey(press(HID.k));
    const r = ime.processKey(press(HID.enter));
    try expectCommitted(r, "가");
    try expectPreedit(r, null);
    try expectForward(r, HID.enter);
    try expectPreeditChanged(r, true);
}

test "K2: flush_tab" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // r→k = 가, then Tab
    _ = ime.processKey(press(HID.r));
    _ = ime.processKey(press(HID.k));
    const r = ime.processKey(press(HID.tab));
    try expectCommitted(r, "가");
    try expectPreedit(r, null);
    try expectForward(r, HID.tab);
    try expectPreeditChanged(r, true);
}

test "K3: flush_escape" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // r→k = 가, then Escape
    _ = ime.processKey(press(HID.r));
    _ = ime.processKey(press(HID.k));
    const r = ime.processKey(press(HID.escape));
    try expectCommitted(r, "가");
    try expectPreedit(r, null);
    try expectForward(r, HID.escape);
    try expectPreeditChanged(r, true);
}

test "K4: flush_arrow" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // r→k = 가, then Arrow
    _ = ime.processKey(press(HID.r));
    _ = ime.processKey(press(HID.k));
    const r = ime.processKey(press(HID.right));
    try expectCommitted(r, "가");
    try expectPreedit(r, null);
    try expectForward(r, HID.right);
    try expectPreeditChanged(r, true);
}

test "K5: flush_arrow_no_composition" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // Arrow with no composition
    const r = ime.processKey(press(HID.right));
    try expectCommitted(r, null);
    try expectPreedit(r, null);
    try expectForward(r, HID.right);
    try expectPreeditChanged(r, false);
}

// ============================================================
// L. Input method switching (4 tests)
// ============================================================

test "L1: switch_with_composition" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // Korean mode, r→k = 가, switch to direct
    _ = ime.processKey(press(HID.r));
    _ = ime.processKey(press(HID.k));
    const r = try ime.setActiveInputMethod("direct");
    try expectCommitted(r, "가");
    try expectPreedit(r, null);
    try expectForward(r, null);
    try expectPreeditChanged(r, true);
}

test "L2: switch_without_composition" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // Korean mode, no composition, switch to direct
    const r = try ime.setActiveInputMethod("direct");
    try expectCommitted(r, null);
    try expectPreedit(r, null);
    try expectForward(r, null);
    try expectPreeditChanged(r, false);
}

test "L3: switch_same_method" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // Korean -> Korean: no-op
    _ = ime.processKey(press(HID.r)); // preedit ㄱ
    const r = try ime.setActiveInputMethod("korean_2set");
    // Same method: no flush, no-op
    try expectCommitted(r, null);
    try expectPreedit(r, null);
    try expectForward(r, null);
    try expectPreeditChanged(r, false);
    // Composition should still be active
    try testing.expect(!ime.isEmpty());
}

test "L4: switch_unsupported" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    const result = ime.setActiveInputMethod("japanese_romaji");
    try testing.expectError(error.UnsupportedInputMethod, result);
}

// ============================================================
// M. Lifecycle (3 tests)
// ============================================================

test "M1: deactivate_flushes" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // r→k = 가, deactivate flushes
    _ = ime.processKey(press(HID.r));
    _ = ime.processKey(press(HID.k));
    const r = ime.deactivate();
    try expectCommitted(r, "가");
    try expectPreedit(r, null);
}

test "M2: deactivate_empty" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // No composition, deactivate
    const r = ime.deactivate();
    try expectCommitted(r, null);
    try expectPreedit(r, null);
}

test "M3: activate_preserves_method" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // Verify Korean is active
    try testing.expectEqualStrings("korean_2set", ime.getActiveInputMethod());
    // Deactivate then activate
    _ = ime.deactivate();
    ime.activate();
    // Input method should still be korean_2set
    try testing.expectEqualStrings("korean_2set", ime.getActiveInputMethod());
}

// ============================================================
// N. preedit_changed accuracy (3 tests)
// ============================================================

test "N1: preedit_changed_false_direct" {
    var eng = try createDirectEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // Direct mode: preedit_changed is always false
    var r = ime.processKey(press(HID.a));
    try expectPreeditChanged(r, false);
    r = ime.processKey(press(HID.enter));
    try expectPreeditChanged(r, false);
    r = ime.processKey(ctrlPress(HID.c));
    try expectPreeditChanged(r, false);
    r = ime.processKey(press(HID.right));
    try expectPreeditChanged(r, false);
}

test "N2: preedit_changed_transitions" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // Each preedit change should set preedit_changed=true
    var r = ime.processKey(press(HID.r)); // null -> ㄱ
    try expectPreeditChanged(r, true);
    r = ime.processKey(press(HID.k)); // ㄱ -> 가
    try expectPreeditChanged(r, true);
    r = ime.processKey(press(HID.s)); // 가 -> 간
    try expectPreeditChanged(r, true);
    // Flush via Enter: 간 -> null
    r = ime.processKey(press(HID.enter));
    try expectPreeditChanged(r, true);
}

test "N3: preedit_changed_false_no_change" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // Release event: no preedit change
    var r = ime.processKey(releaseKey(HID.r));
    try expectPreeditChanged(r, false);
    // Modifier with no composition: no preedit change
    r = ime.processKey(ctrlPress(HID.c));
    try expectPreeditChanged(r, false);
}

// ============================================================
// O. Release events (1 test)
// ============================================================

test "O1: release_ignored" {
    // Direct mode release
    var eng_d = try createDirectEngine();
    defer eng_d.deinit();
    const ime_d = eng_d.engine();
    var r = ime_d.processKey(releaseKey(HID.r));
    try expectCommitted(r, null);
    try expectPreedit(r, null);
    try expectForward(r, null);
    try expectPreeditChanged(r, false);

    // Korean mode release
    var eng_k = try createKoreanEngine();
    defer eng_k.deinit();
    const ime_k = eng_k.engine();
    r = ime_k.processKey(releaseKey(HID.r));
    try expectCommitted(r, null);
    try expectPreedit(r, null);
    try expectForward(r, null);
    try expectPreeditChanged(r, false);
}

// ============================================================
// P. Repeat events (1 test)
// ============================================================

test "P1: repeat_key" {
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();
    // Press r to start composition
    _ = ime.processKey(press(HID.r)); // preedit ㄱ
    // Repeat k — should be treated same as press
    const r = ime.processKey(repeatKey(HID.k));
    try expectPreedit(r, "가");
    try expectCommitted(r, null);
    try expectForward(r, null);
    try expectPreeditChanged(r, true);
}

// ============================================================
// Q. Edge cases for coverage gaps (additional tests)
// ============================================================

test "Q1: composing_mode_non_printable_non_special_key" {
    // Tests processKeyComposing line 140: fallback flush+forward for
    // keys that are non-printable, non-special (e.g., F-keys, CapsLock).
    // HID 0x39 = CapsLock, 0x3A = F1. Both are outside printable range
    // (0x04-0x38) and not in the special key set.
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();

    // Start composition
    _ = ime.processKey(press(HID.r)); // preedit ㄱ
    // Press F1 (HID 0x3A) — non-printable, non-special
    const r = ime.processKey(press(0x3A));
    try expectCommitted(r, "ㄱ");
    try expectPreedit(r, null);
    try expectForward(r, 0x3A);
    try expectPreeditChanged(r, true);
}

test "Q2: composing_mode_non_printable_no_composition" {
    // Same path but with no active composition — tests flushAndForward
    // with empty hangul_ic.
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();

    // Press F1 with no composition
    const r = ime.processKey(press(0x3A));
    try expectCommitted(r, null);
    try expectPreedit(r, null);
    try expectForward(r, 0x3A);
    try expectPreeditChanged(r, false);
}

test "Q3: switch_direct_to_korean" {
    // Tests setActiveInputMethodImpl switching TO korean (libhangul keyboard update).
    var eng = try createDirectEngine();
    defer eng.deinit();
    const ime = eng.engine();

    // Switch from direct to korean_2set
    const r = try ime.setActiveInputMethod("korean_2set");
    try expectCommitted(r, null);
    try expectPreedit(r, null);
    try expectPreeditChanged(r, false);
    try testing.expectEqualStrings("korean_2set", ime.getActiveInputMethod());

    // Verify composing mode works after switch
    const r2 = ime.processKey(press(HID.r));
    try expectPreedit(r2, "ㄱ");
    try expectPreeditChanged(r2, true);
}

test "Q4: switch_korean_to_different_korean" {
    // Tests switching between two Korean layouts (keyboard ID update path).
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();

    // Switch from korean_2set to korean_3set_390
    const r = try ime.setActiveInputMethod("korean_3set_390");
    try expectCommitted(r, null);
    try expectPreedit(r, null);
    try expectPreeditChanged(r, false);
    try testing.expectEqualStrings("korean_3set_390", ime.getActiveInputMethod());
}

test "Q5: direct_mode_release_event" {
    // Tests that release events in direct mode return empty.
    var eng = try createDirectEngine();
    defer eng.deinit();
    const ime = eng.engine();
    const r = ime.processKey(releaseKey(HID.a));
    try expectCommitted(r, null);
    try expectPreedit(r, null);
    try expectForward(r, null);
    try expectPreeditChanged(r, false);
}

test "Q6: direct_mode_repeat_event" {
    // Tests that repeat events in direct mode work like press.
    var eng = try createDirectEngine();
    defer eng.deinit();
    const ime = eng.engine();
    const r = ime.processKey(repeatKey(HID.a));
    try expectCommitted(r, "a");
    try expectPreedit(r, null);
    try expectForward(r, null);
    try expectPreeditChanged(r, false);
}

test "Q7: flush_explicit_with_composition" {
    // Tests flush() via the ImeEngine interface with active composition.
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();

    _ = ime.processKey(press(HID.r)); // ㄱ
    _ = ime.processKey(press(HID.k)); // 가
    try testing.expect(!ime.isEmpty());

    const r = ime.flush();
    try expectCommitted(r, "가");
    try expectPreedit(r, null);
    try expectPreeditChanged(r, true);
    try testing.expect(ime.isEmpty());
}

test "Q8: flush_explicit_empty" {
    // Tests flush() with no active composition.
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();

    try testing.expect(ime.isEmpty());
    const r = ime.flush();
    try expectCommitted(r, null);
    try expectPreedit(r, null);
    try expectPreeditChanged(r, false);
}

test "Q9: reset_discards_composition" {
    // Tests reset() discards without committing.
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();

    _ = ime.processKey(press(HID.r)); // ㄱ
    _ = ime.processKey(press(HID.k)); // 가
    try testing.expect(!ime.isEmpty());

    ime.reset();
    try testing.expect(ime.isEmpty());

    // Verify no residual state — new composition starts fresh
    const r = ime.processKey(press(HID.r));
    try expectPreedit(r, "ㄱ");
    try expectCommitted(r, null);
}

test "Q10: process_false_with_no_prior_composition" {
    // Tests feedLibhangul not-consumed path when there was no prior composition.
    // Press a number key as the FIRST key in composing mode.
    var eng = try createKoreanEngine();
    defer eng.deinit();
    const ime = eng.engine();

    // Press '1' (HID 0x1E) as first key — libhangul rejects it
    const r = ime.processKey(press(HID.@"1"));
    try expectCommitted(r, null);
    try expectPreedit(r, null);
    try expectForward(r, HID.@"1");
    // preedit_changed should be false (was null, still null)
    try expectPreeditChanged(r, false);
}
