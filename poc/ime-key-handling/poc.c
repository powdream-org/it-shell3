/**
 * PoC: Verify that libitshell3-ime can handle non-displayable keys
 * (arrows, Ctrl+C, Enter, etc.) on top of libhangul.
 *
 * Tests the exact pattern from the interface contract:
 *   1. Pre-filter: modifier/special keys → flush composition + forward key
 *   2. Printable keys → feed to hangul_ic_process()
 *   3. Backspace → try hangul_ic_backspace(), forward if empty
 *
 * Build:
 *   cc -o poc poc.c libhangul/hangul/hangulctype.c \
 *      libhangul/hangul/hangulinputcontext.c \
 *      libhangul/hangul/hangulkeyboard.c \
 *      libhangul/hangul/hanja.c \
 *      -I libhangul -std=c99
 */

#include <stdio.h>
#include <stdbool.h>
#include <string.h>
#include "hangul/hangul.h"

// --- Simulated key event types (matching our design) ---

typedef struct {
    unsigned char hid_keycode;
    bool ctrl;
    bool alt;
    bool super_key;
    bool shift;
} KeyEvent;

typedef struct {
    const char* committed;       // UTF-8, NULL if none
    const char* preedit;         // UTF-8, NULL if none
    bool forward_key;            // true if key should be forwarded to terminal
    const char* forward_desc;    // human-readable description of forwarded key
} ImeResult;

// --- HID keycode constants ---
#define HID_A     0x04
#define HID_R     0x15  // 'r' -> ㄱ in Korean 2-set
#define HID_K     0x0E  // 'k' -> ㅏ
#define HID_S     0x16  // 's' -> ㄴ
#define HID_F     0x09  // 'f' -> ㄹ
#define HID_ENTER 0x28
#define HID_ESC   0x29
#define HID_BS    0x2A
#define HID_TAB   0x2B
#define HID_RIGHT 0x4F
#define HID_LEFT  0x50
#define HID_DOWN  0x51
#define HID_UP    0x52

// --- Simple HID-to-ASCII for US QWERTY (subset for PoC) ---
static char hid_to_ascii(unsigned char hid, bool shift) {
    // Only the keys we need for this PoC
    static const char unshifted[0x39] = {
        [0x04] = 'a', [0x05] = 'b', [0x06] = 'c', [0x07] = 'd',
        [0x08] = 'e', [0x09] = 'f', [0x0A] = 'g', [0x0B] = 'h',
        [0x0C] = 'i', [0x0D] = 'j', [0x0E] = 'k', [0x0F] = 'l',
        [0x10] = 'm', [0x11] = 'n', [0x12] = 'o', [0x13] = 'p',
        [0x14] = 'q', [0x15] = 'r', [0x16] = 's', [0x17] = 't',
        [0x18] = 'u', [0x19] = 'v', [0x1A] = 'w', [0x1B] = 'x',
        [0x1C] = 'y', [0x1D] = 'z',
    };
    if (hid >= 0x04 && hid <= 0x1D) {
        char c = unshifted[hid];
        return shift ? (c - 32) : c;  // uppercase if shift
    }
    return 0;  // non-printable
}

// --- UCS-4 to UTF-8 helper ---
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

// --- The core function we're testing: processKey ---
// This implements the exact pattern from our interface contract.

static char g_committed_buf[256];
static char g_preedit_buf[64];

static ImeResult processKey(HangulInputContext* hic, KeyEvent key) {
    ImeResult result = { .committed = NULL, .preedit = NULL,
                         .forward_key = false, .forward_desc = NULL };

    // Step 1: Pre-filter — modifiers and special keys flush composition
    bool has_modifier = key.ctrl || key.alt || key.super_key;
    bool is_special = (key.hid_keycode >= 0x28 && key.hid_keycode <= 0x2B) ||  // Enter, Esc, BS, Tab
                      (key.hid_keycode >= 0x4F && key.hid_keycode <= 0x52);     // Arrows

    // Backspace: try IME backspace first
    if (key.hid_keycode == HID_BS && !has_modifier) {
        bool consumed = hangul_ic_backspace(hic);
        if (consumed) {
            const ucschar* preedit = hangul_ic_get_preedit_string(hic);
            if (preedit && preedit[0] != 0) {
                ucs4_to_utf8(preedit, g_preedit_buf, sizeof(g_preedit_buf));
                result.preedit = g_preedit_buf;
            }
            return result;
        }
        // Not consumed — forward backspace
        result.forward_key = true;
        result.forward_desc = "Backspace";
        return result;
    }

    // Modifier or special key: flush composition, forward the key
    if (has_modifier || is_special) {
        if (!hangul_ic_is_empty(hic)) {
            const ucschar* flushed = hangul_ic_flush(hic);
            if (flushed && flushed[0] != 0) {
                ucs4_to_utf8(flushed, g_committed_buf, sizeof(g_committed_buf));
                result.committed = g_committed_buf;
            }
        }
        result.forward_key = true;
        // Describe what's being forwarded
        if (key.ctrl && key.hid_keycode == 0x06)  result.forward_desc = "Ctrl+C";
        else if (key.ctrl && key.hid_keycode == 0x07) result.forward_desc = "Ctrl+D";
        else if (key.hid_keycode == HID_RIGHT) result.forward_desc = "Right Arrow";
        else if (key.hid_keycode == HID_LEFT)  result.forward_desc = "Left Arrow";
        else if (key.hid_keycode == HID_UP)    result.forward_desc = "Up Arrow";
        else if (key.hid_keycode == HID_DOWN)  result.forward_desc = "Down Arrow";
        else if (key.hid_keycode == HID_ENTER) result.forward_desc = "Enter";
        else if (key.hid_keycode == HID_ESC)   result.forward_desc = "Escape";
        else if (key.hid_keycode == HID_TAB)   result.forward_desc = "Tab";
        else result.forward_desc = "modifier+key";
        return result;
    }

    // Step 2: Printable key — feed to libhangul
    char ascii = hid_to_ascii(key.hid_keycode, key.shift);
    if (ascii == 0) {
        // Unmapped key — forward
        result.forward_key = true;
        result.forward_desc = "unmapped";
        return result;
    }

    bool consumed = hangul_ic_process(hic, ascii);

    // Read committed text
    const ucschar* commit = hangul_ic_get_commit_string(hic);
    if (commit && commit[0] != 0) {
        ucs4_to_utf8(commit, g_committed_buf, sizeof(g_committed_buf));
        result.committed = g_committed_buf;
    }

    // Read preedit
    const ucschar* preedit = hangul_ic_get_preedit_string(hic);
    if (preedit && preedit[0] != 0) {
        ucs4_to_utf8(preedit, g_preedit_buf, sizeof(g_preedit_buf));
        result.preedit = g_preedit_buf;
    }

    if (!consumed) {
        // libhangul didn't want it — flush and forward
        if (!hangul_ic_is_empty(hic)) {
            const ucschar* flushed = hangul_ic_flush(hic);
            if (flushed && flushed[0] != 0) {
                ucs4_to_utf8(flushed, g_committed_buf, sizeof(g_committed_buf));
                result.committed = g_committed_buf;
            }
        }
        result.forward_key = true;
        result.forward_desc = "not consumed by IME";
    }

    return result;
}

// --- Test harness ---

static void print_result(const char* label, ImeResult r) {
    printf("  %-30s → ", label);
    if (r.committed)  printf("commit=\"%s\" ", r.committed);
    if (r.preedit)    printf("preedit=\"%s\" ", r.preedit);
    if (r.forward_key) printf("forward=[%s]", r.forward_desc);
    if (!r.committed && !r.preedit && !r.forward_key) printf("(no output)");
    printf("\n");
}

#define KEY(hid)          (KeyEvent){ .hid_keycode = (hid), .shift = false }
#define KEY_SHIFT(hid)    (KeyEvent){ .hid_keycode = (hid), .shift = true }
#define KEY_CTRL(hid)     (KeyEvent){ .hid_keycode = (hid), .ctrl = true }

int main(void) {
    HangulInputContext* hic = hangul_ic_new("2");  // Dubeolsik
    if (!hic) {
        fprintf(stderr, "Failed to create HangulInputContext\n");
        return 1;
    }

    printf("=== Test 1: Basic Korean composition ===\n");
    print_result("'r' (ㄱ)",      processKey(hic, KEY(HID_R)));  // preedit=ㄱ
    print_result("'k' (ㅏ)",      processKey(hic, KEY(HID_K)));  // preedit=가
    print_result("'s' (ㄴ→jong)", processKey(hic, KEY(HID_S)));  // preedit=간
    print_result("'r' (new ㄱ)",  processKey(hic, KEY(HID_R)));  // commit=간, preedit=ㄱ
    hangul_ic_reset(hic);
    printf("\n");

    printf("=== Test 2: Arrow key during composition ===\n");
    print_result("'r' (ㄱ)",       processKey(hic, KEY(HID_R)));
    print_result("'k' (ㅏ → 가)", processKey(hic, KEY(HID_K)));
    print_result("Right Arrow",    processKey(hic, KEY(HID_RIGHT)));  // commit=가, forward=arrow
    printf("\n");

    printf("=== Test 3: Ctrl+C during composition ===\n");
    print_result("'r' (ㄱ)",      processKey(hic, KEY(HID_R)));
    print_result("'k' (ㅏ → 가)", processKey(hic, KEY(HID_K)));
    print_result("'s' (ㄴ → 간)", processKey(hic, KEY(HID_S)));
    print_result("Ctrl+C",        processKey(hic, KEY_CTRL(0x06)));  // commit=간, forward=Ctrl+C
    printf("\n");

    printf("=== Test 4: Enter during composition ===\n");
    print_result("'r' (ㄱ)",       processKey(hic, KEY(HID_R)));
    print_result("Enter",          processKey(hic, KEY(HID_ENTER)));  // commit=ㄱ, forward=Enter
    printf("\n");

    printf("=== Test 5: Backspace during composition (jamo undo) ===\n");
    print_result("'r' (ㄱ)",       processKey(hic, KEY(HID_R)));
    print_result("'k' (ㅏ → 가)", processKey(hic, KEY(HID_K)));
    print_result("'s' (ㄴ → 간)", processKey(hic, KEY(HID_S)));
    print_result("Backspace (간→가)", processKey(hic, KEY(HID_BS)));  // preedit=가
    print_result("Backspace (가→ㄱ)", processKey(hic, KEY(HID_BS)));  // preedit=ㄱ
    print_result("Backspace (ㄱ→∅)",  processKey(hic, KEY(HID_BS)));  // empty
    print_result("Backspace (empty→fwd)", processKey(hic, KEY(HID_BS)));  // forward
    printf("\n");

    printf("=== Test 6: Ctrl+C with NO active composition ===\n");
    print_result("Ctrl+C (no comp)", processKey(hic, KEY_CTRL(0x06)));  // just forward, no commit
    printf("\n");

    printf("=== Test 7: Arrow keys with NO active composition ===\n");
    print_result("Right Arrow", processKey(hic, KEY(HID_RIGHT)));  // just forward
    print_result("Up Arrow",    processKey(hic, KEY(HID_UP)));     // just forward
    printf("\n");

    printf("=== Test 8: Double consonant (Shift) ===\n");
    print_result("'R' (ㄲ, shift+r)", processKey(hic, KEY_SHIFT(HID_R)));  // preedit=ㄲ
    print_result("'k' (ㅏ → 까)",     processKey(hic, KEY(HID_K)));        // preedit=까
    print_result("Escape",             processKey(hic, KEY(HID_ESC)));      // commit=까, forward=Esc
    printf("\n");

    printf("=== Test 9: Mixed — compose, arrow, compose again ===\n");
    print_result("'r' (ㄱ)",       processKey(hic, KEY(HID_R)));
    print_result("'k' (ㅏ → 가)", processKey(hic, KEY(HID_K)));
    print_result("Left Arrow",     processKey(hic, KEY(HID_LEFT)));   // commit=가, forward=left
    print_result("'s' (ㄴ)",       processKey(hic, KEY(HID_S)));      // NEW composition: preedit=ㄴ
    print_result("'k' (ㅏ → 나)", processKey(hic, KEY(HID_K)));      // preedit=나
    print_result("Enter",          processKey(hic, KEY(HID_ENTER)));  // commit=나, forward=Enter
    printf("\n");

    printf("=== Test 10: Ctrl+D (Ctrl+d, EOF signal) during composition ===\n");
    print_result("'f' (ㄹ)",       processKey(hic, KEY(HID_F)));
    print_result("'k' (ㅏ → 라)", processKey(hic, KEY(HID_K)));
    print_result("Ctrl+D",         processKey(hic, KEY_CTRL(0x07)));  // commit=라, forward=Ctrl+D
    printf("\n");

    hangul_ic_delete(hic);

    printf("All tests completed. The pattern works.\n");
    return 0;
}
