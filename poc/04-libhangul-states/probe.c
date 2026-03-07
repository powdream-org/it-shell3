/**
 * PoC: Probe libhangul observable composition states
 *
 * Question: What combinations of has_choseong/has_jungseong/has_jongseong
 * actually occur across keyboard layouts ("2", "3f", "39", "ro")?
 * Can we distinguish single vs compound jongseong from the public API?
 *
 * Build:
 *   cc -o probe probe.c ../ime-key-handling/libhangul/hangul/hangulctype.c \
 *      ../ime-key-handling/libhangul/hangul/hangulinputcontext.c \
 *      ../ime-key-handling/libhangul/hangul/hangulkeyboard.c \
 *      ../ime-key-handling/libhangul/hangul/hanja.c \
 *      -I ../ime-key-handling/libhangul -std=c99
 */

#include <stdio.h>
#include <stdbool.h>
#include <string.h>
#include "hangul/hangul.h"

// UCS-4 to UTF-8
static int ucs4_to_utf8(const ucschar* ucs4, char* buf, int buflen) {
    int pos = 0;
    for (int i = 0; ucs4[i] != 0 && pos < buflen - 4; i++) {
        uint32_t cp = ucs4[i];
        if (cp < 0x80) {
            buf[pos++] = (char)cp;
        } else if (cp < 0x800) {
            buf[pos++] = (char)(0xC0 | (cp >> 6));
            buf[pos++] = (char)(0x80 | (cp & 0x3F));
        } else if (cp < 0x10000) {
            buf[pos++] = (char)(0xE0 | (cp >> 12));
            buf[pos++] = (char)(0x80 | ((cp >> 6) & 0x3F));
            buf[pos++] = (char)(0x80 | (cp & 0x3F));
        }
    }
    buf[pos] = 0;
    return pos;
}

// Print current state after a keystroke
static void probe_state(HangulInputContext* hic, const char* label) {
    bool cho  = hangul_ic_has_choseong(hic);
    bool jung = hangul_ic_has_jungseong(hic);
    bool jong = hangul_ic_has_jongseong(hic);
    bool empty = hangul_ic_is_empty(hic);

    char preedit_utf8[64] = "(empty)";
    char commit_utf8[64] = "";

    const ucschar* preedit = hangul_ic_get_preedit_string(hic);
    if (preedit && preedit[0] != 0)
        ucs4_to_utf8(preedit, preedit_utf8, sizeof(preedit_utf8));

    const ucschar* commit = hangul_ic_get_commit_string(hic);
    if (commit && commit[0] != 0)
        ucs4_to_utf8(commit, commit_utf8, sizeof(commit_utf8));

    printf("  %-25s  cho=%d jung=%d jong=%d empty=%d  preedit=%-6s",
           label, cho, jung, jong, empty, preedit_utf8);
    if (commit_utf8[0])
        printf("  commit=%s", commit_utf8);
    printf("\n");
}

// Feed a key and probe
static void feed(HangulInputContext* hic, int ascii, const char* label) {
    hangul_ic_process(hic, ascii);
    probe_state(hic, label);
}

// Backspace and probe
static void bs(HangulInputContext* hic, const char* label) {
    bool consumed = hangul_ic_backspace(hic);
    printf("  %-25s  ", label);
    if (!consumed) {
        printf("NOT CONSUMED (empty buffer)\n");
        return;
    }
    bool cho  = hangul_ic_has_choseong(hic);
    bool jung = hangul_ic_has_jungseong(hic);
    bool jong = hangul_ic_has_jongseong(hic);
    bool empty = hangul_ic_is_empty(hic);

    char preedit_utf8[64] = "(empty)";
    const ucschar* preedit = hangul_ic_get_preedit_string(hic);
    if (preedit && preedit[0] != 0)
        ucs4_to_utf8(preedit, preedit_utf8, sizeof(preedit_utf8));

    printf("cho=%d jung=%d jong=%d empty=%d  preedit=%-6s\n",
           cho, jung, jong, empty, preedit_utf8);
}

static void separator(void) { printf("\n"); }

int main(void) {
    // ==========================================
    // TEST GROUP 1: 2-set (Dubeolsik, "2")
    // ==========================================
    printf("========================================\n");
    printf("KEYBOARD: 2-set (Dubeolsik, \"2\")\n");
    printf("========================================\n\n");

    HangulInputContext* hic = hangul_ic_new("2");

    // 1a: Consonant only
    printf("--- 1a: Consonant only ---\n");
    feed(hic, 'r', "'r' -> ?");  // ㄱ
    hangul_ic_reset(hic);
    separator();

    // 1b: Vowel only (does implicit ieung happen?)
    printf("--- 1b: Vowel only (2-set) ---\n");
    feed(hic, 'k', "'k' (vowel) -> ?");  // ㅏ or ㅇ+ㅏ?
    hangul_ic_reset(hic);
    separator();

    // 1c: Multiple vowels
    printf("--- 1c: Multiple vowels ---\n");
    feed(hic, 'h', "'h' (ㅗ) -> ?");
    feed(hic, 'k', "'k' (ㅏ) -> ?");  // compound ㅘ?
    hangul_ic_reset(hic);
    separator();

    // 1d: Consonant + vowel
    printf("--- 1d: Consonant + vowel ---\n");
    feed(hic, 'r', "'r' (ㄱ)");
    feed(hic, 'k', "'k' (ㅏ) -> 가");
    hangul_ic_reset(hic);
    separator();

    // 1e: Full syllable with tail
    printf("--- 1e: Full syllable (C+V+C) ---\n");
    feed(hic, 'r', "'r' (ㄱ)");
    feed(hic, 'k', "'k' (ㅏ) -> 가");
    feed(hic, 's', "'s' (ㄴ) -> 간");
    hangul_ic_reset(hic);
    separator();

    // 1f: Double tail (compound jongseong)
    printf("--- 1f: Compound jongseong (ㄹ+ㄱ=ㄺ) ---\n");
    feed(hic, 'r', "'r' (ㄱ)");
    feed(hic, 'k', "'k' (ㅏ) -> 가");
    feed(hic, 'f', "'f' (ㄹ) -> 갈");
    feed(hic, 'r', "'r' (ㄱ) -> 갈+ㄱ=ㄺ?");
    hangul_ic_reset(hic);
    separator();

    // 1g: Jamo reassignment (vowel after C+V+C)
    printf("--- 1g: Jamo reassignment ---\n");
    feed(hic, 'r', "'r' (ㄱ)");
    feed(hic, 'k', "'k' (ㅏ) -> 가");
    feed(hic, 's', "'s' (ㄴ) -> 간");
    feed(hic, 'k', "'k' (ㅏ) -> commit 가, preedit 나?");
    hangul_ic_reset(hic);
    separator();

    // 1h: Jamo reassignment from compound jongseong
    printf("--- 1h: Jamo reassignment from compound jong ---\n");
    feed(hic, 'r', "'r' (ㄱ)");
    feed(hic, 'k', "'k' (ㅏ)");
    feed(hic, 'f', "'f' (ㄹ) -> 갈");
    feed(hic, 'r', "'r' (ㄱ) -> compound");
    feed(hic, 'k', "'k' (ㅏ) -> split?");
    hangul_ic_reset(hic);
    separator();

    // 1i: Backspace decomposition trace
    printf("--- 1i: Backspace through 한 ---\n");
    feed(hic, 'g', "'g' (ㅎ)");
    feed(hic, 'k', "'k' (ㅏ) -> 하");
    feed(hic, 's', "'s' (ㄴ) -> 한");
    bs(hic, "BS (한->하)");
    bs(hic, "BS (하->ㅎ)");
    bs(hic, "BS (ㅎ->empty)");
    bs(hic, "BS (empty)");
    separator();

    // 1j: Backspace through compound jongseong
    printf("--- 1j: Backspace through compound jong ---\n");
    feed(hic, 'r', "'r' (ㄱ)");
    feed(hic, 'k', "'k' (ㅏ)");
    feed(hic, 'f', "'f' (ㄹ) -> 갈");
    feed(hic, 'r', "'r' (ㄱ) -> compound");
    bs(hic, "BS (compound->single jong)");
    bs(hic, "BS (jong->no jong)");
    bs(hic, "BS (no jong->cho only)");
    bs(hic, "BS (cho->empty)");
    separator();

    // 1k: Invalid jongseong (ㅃ has no jong form)
    printf("--- 1k: Invalid jongseong (ㅃ) ---\n");
    feed(hic, 'r', "'r' (ㄱ)");
    feed(hic, 'k', "'k' (ㅏ) -> 가");
    feed(hic, 'Q', "'Q' (ㅃ, no jong) -> ?");
    hangul_ic_reset(hic);
    separator();

    hangul_ic_delete(hic);

    // ==========================================
    // TEST GROUP 2: 3-set Final ("3f")
    // ==========================================
    printf("========================================\n");
    printf("KEYBOARD: 3-set Final (\"3f\")\n");
    printf("========================================\n\n");

    hic = hangul_ic_new("3f");

    // 3-set layout: vowels are separate keys
    // In 3f: vowel keys are on right hand
    // Let's try feeding a vowel directly
    // 3f key mapping (from libhangul keyboard xml):
    //   'k' maps to jungseong in 3f? Need to check.
    //   Actually in 3f, the mapping is different from 2-set.
    //   Let's try common 3f mappings.

    // 3f layout reference (approximate):
    //   Choseong (right bottom): 'r'->ㄱ varies by layout
    //   Jungseong (right top): varies
    //   Jongseong (left): varies
    //   Let's just try various ASCII chars and see what sticks.

    printf("--- 2a: Vowel-only in 3-set ---\n");
    // In 3f, 'l' is typically a vowel key (ㅣ)
    // Try several keys to find vowel-only state
    printf("  Trying various keys to find standalone vowel...\n");

    // Reset and try each key individually
    char test_keys[] = "abcdefghijklmnopqrstuvwxyz";
    for (int i = 0; test_keys[i]; i++) {
        hangul_ic_reset(hic);
        hangul_ic_process(hic, test_keys[i]);
        bool cho  = hangul_ic_has_choseong(hic);
        bool jung = hangul_ic_has_jungseong(hic);
        bool jong = hangul_ic_has_jongseong(hic);
        if (jung && !cho && !jong) {
            char preedit_utf8[64] = "";
            const ucschar* p = hangul_ic_get_preedit_string(hic);
            if (p && p[0]) ucs4_to_utf8(p, preedit_utf8, sizeof(preedit_utf8));
            printf("  FOUND: key='%c' -> cho=0 jung=1 jong=0 preedit=%s\n",
                   test_keys[i], preedit_utf8);
        }
        if (!jung && !cho && jong) {
            char preedit_utf8[64] = "";
            const ucschar* p = hangul_ic_get_preedit_string(hic);
            if (p && p[0]) ucs4_to_utf8(p, preedit_utf8, sizeof(preedit_utf8));
            printf("  FOUND jong-only: key='%c' -> cho=0 jung=0 jong=1 preedit=%s\n",
                   test_keys[i], preedit_utf8);
        }
    }
    hangul_ic_reset(hic);
    separator();

    // 2b: Try building a syllable in 3f
    printf("--- 2b: Full syllable in 3-set (need to find right keys) ---\n");
    // In 3f layout, typical mapping for ㄱ+ㅏ+ㄴ:
    // We'll scan for a choseong key, a jungseong key, and try composing
    printf("  Scanning for choseong keys...\n");
    for (int i = 0; test_keys[i]; i++) {
        hangul_ic_reset(hic);
        hangul_ic_process(hic, test_keys[i]);
        bool cho  = hangul_ic_has_choseong(hic);
        bool jung = hangul_ic_has_jungseong(hic);
        bool jong = hangul_ic_has_jongseong(hic);
        if (cho && !jung && !jong) {
            char preedit_utf8[64] = "";
            const ucschar* p = hangul_ic_get_preedit_string(hic);
            if (p && p[0]) ucs4_to_utf8(p, preedit_utf8, sizeof(preedit_utf8));
            printf("    choseong: key='%c' preedit=%s\n", test_keys[i], preedit_utf8);
        }
    }
    hangul_ic_reset(hic);
    separator();

    hangul_ic_delete(hic);

    // ==========================================
    // TEST GROUP 3: 3-set 390 ("39")
    // ==========================================
    printf("========================================\n");
    printf("KEYBOARD: 3-set 390 (\"39\")\n");
    printf("========================================\n\n");

    hic = hangul_ic_new("39");

    printf("--- 3a: Scan for vowel-only state ---\n");
    for (int i = 0; test_keys[i]; i++) {
        hangul_ic_reset(hic);
        hangul_ic_process(hic, test_keys[i]);
        bool cho  = hangul_ic_has_choseong(hic);
        bool jung = hangul_ic_has_jungseong(hic);
        bool jong = hangul_ic_has_jongseong(hic);
        if (jung && !cho && !jong) {
            char preedit_utf8[64] = "";
            const ucschar* p = hangul_ic_get_preedit_string(hic);
            if (p && p[0]) ucs4_to_utf8(p, preedit_utf8, sizeof(preedit_utf8));
            printf("  FOUND vowel-only: key='%c' -> cho=0 jung=1 jong=0 preedit=%s\n",
                   test_keys[i], preedit_utf8);
        }
    }
    hangul_ic_reset(hic);
    separator();

    hangul_ic_delete(hic);

    // ==========================================
    // TEST GROUP 4: Romaja ("ro")
    // ==========================================
    printf("========================================\n");
    printf("KEYBOARD: Romaja (\"ro\")\n");
    printf("========================================\n\n");

    hic = hangul_ic_new("ro");

    printf("--- 4a: Vowel in romaja ---\n");
    feed(hic, 'a', "'a' (ㅏ) -> ?");
    hangul_ic_reset(hic);
    separator();

    printf("--- 4b: Consonant then vowel in romaja ---\n");
    feed(hic, 'g', "'g' (ㄱ) -> ?");
    feed(hic, 'a', "'a' (ㅏ) -> ?");
    hangul_ic_reset(hic);
    separator();

    hangul_ic_delete(hic);

    // ==========================================
    // TEST GROUP 5: 2-set with options
    // ==========================================
    printf("========================================\n");
    printf("KEYBOARD: 2-set with COMBI_ON_DOUBLE_STROKE\n");
    printf("========================================\n\n");

    hic = hangul_ic_new("2");
    hangul_ic_set_option(hic, HANGUL_IC_OPTION_COMBI_ON_DOUBLE_STROKE, true);

    printf("--- 5a: Double consonant via double stroke ---\n");
    feed(hic, 'r', "'r' (ㄱ)");
    feed(hic, 'r', "'r' (ㄱ+ㄱ=ㄲ?)");
    hangul_ic_reset(hic);
    separator();

    hangul_ic_delete(hic);

    printf("========================================\n");
    printf("KEYBOARD: 2-set with AUTO_REORDER\n");
    printf("========================================\n\n");

    hic = hangul_ic_new("2");
    hangul_ic_set_option(hic, HANGUL_IC_OPTION_AUTO_REORDER, true);

    printf("--- 5b: Vowel then consonant with auto-reorder ---\n");
    feed(hic, 'k', "'k' (ㅏ) -> ?");
    feed(hic, 'r', "'r' (ㄱ) -> ?");  // does auto-reorder make this 가?
    hangul_ic_reset(hic);
    separator();

    hangul_ic_delete(hic);

    // ==========================================
    // SUMMARY
    // ==========================================
    printf("========================================\n");
    printf("EXHAUSTIVE STATE SCAN: 2-set all a-z\n");
    printf("========================================\n\n");

    hic = hangul_ic_new("2");

    // For each key, what state does it produce from empty?
    printf("  key  cho jung jong  preedit\n");
    printf("  ---  --- ---- ----  -------\n");
    for (int i = 0; test_keys[i]; i++) {
        hangul_ic_reset(hic);
        bool consumed = hangul_ic_process(hic, test_keys[i]);
        bool cho  = hangul_ic_has_choseong(hic);
        bool jung = hangul_ic_has_jungseong(hic);
        bool jong = hangul_ic_has_jongseong(hic);
        char preedit_utf8[64] = "";
        const ucschar* p = hangul_ic_get_preedit_string(hic);
        if (p && p[0]) ucs4_to_utf8(p, preedit_utf8, sizeof(preedit_utf8));
        printf("   %c    %d    %d    %d    %-6s  consumed=%d\n",
               test_keys[i], cho, jung, jong, preedit_utf8, consumed);
    }
    separator();

    hangul_ic_delete(hic);

    printf("Done.\n");
    return 0;
}
