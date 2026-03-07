/**
 * poc-ghostty-integration.c — Full IME + simulated ghostty pipeline PoC.
 *
 * Implements the three-phase key processing pipeline from the interface
 * contract (v0.2) with a simulated terminal buffer standing in for
 * libghostty's rendering surface.
 *
 * Pipeline per key event:
 *   Phase 0: Language switch check (toggle key)
 *   Phase 1: IME processKey() -> ImeResult
 *   Phase 2: ImeResult -> simulated ghostty API calls -> terminal buffer
 *
 * Build:
 *   cc -o poc-ghostty poc-ghostty-integration.c sim_terminal.c \
 *      libhangul/hangul/hangulctype.c \
 *      libhangul/hangul/hangulinputcontext.c \
 *      libhangul/hangul/hangulkeyboard.c \
 *      libhangul/hangul/hanja.c \
 *      -I libhangul -std=c99
 */

#include <stdio.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>
#include "hangul/hangul.h"
#include "sim_terminal.h"

/* ------------------------------------------------------------------ */
/* Constants                                                          */
/* ------------------------------------------------------------------ */

/* Terminal dimensions for PoC */
#define TERM_COLS 40
#define TERM_ROWS 4

/* HID keycode constants (USB HID Keyboard page 0x07) */
#define HID_A     0x04
#define HID_B     0x05
#define HID_C     0x06
#define HID_D     0x07
#define HID_E     0x08
#define HID_F     0x09
#define HID_G     0x0A
#define HID_H     0x0B
#define HID_I     0x0C
#define HID_J     0x0D
#define HID_K     0x0E
#define HID_L     0x0F
#define HID_M     0x10
#define HID_N     0x11
#define HID_O     0x12
#define HID_P     0x13
#define HID_Q     0x14
#define HID_R     0x15
#define HID_S     0x16
#define HID_T     0x17
#define HID_U     0x18
#define HID_V     0x19
#define HID_W     0x1A
#define HID_X     0x1B
#define HID_Y     0x1C
#define HID_Z     0x1D
#define HID_1     0x1E
#define HID_SPACE 0x2C
#define HID_ENTER 0x28
#define HID_ESC   0x29
#define HID_BS    0x2A
#define HID_TAB   0x2B
#define HID_RIGHT 0x4F
#define HID_LEFT  0x50
#define HID_DOWN  0x51
#define HID_UP    0x52
#define HID_HOME  0x4A

/* Language IDs */
#define LANG_DIRECT 0
#define LANG_KOREAN 1

/* ------------------------------------------------------------------ */
/* Key event and IME result types                                     */
/* ------------------------------------------------------------------ */

typedef struct {
    unsigned char hid_keycode;
    bool ctrl;
    bool alt;
    bool super_key;
    bool shift;
} KeyEvent;

typedef struct {
    const char* committed;     /* UTF-8 committed text, NULL if none */
    const char* preedit;       /* UTF-8 preedit text, NULL if none */
    bool forward_key;          /* true if key should be forwarded to terminal */
    const char* forward_desc;  /* human-readable description */
    KeyEvent original_key;     /* the original key event (for forwarding) */
} ImeResult;

/* ------------------------------------------------------------------ */
/* HID-to-ASCII lookup (US QWERTY subset)                             */
/* ------------------------------------------------------------------ */

static char hid_to_ascii(unsigned char hid, bool shift) {
    static const char unshifted[0x39] = {
        [0x04] = 'a', [0x05] = 'b', [0x06] = 'c', [0x07] = 'd',
        [0x08] = 'e', [0x09] = 'f', [0x0A] = 'g', [0x0B] = 'h',
        [0x0C] = 'i', [0x0D] = 'j', [0x0E] = 'k', [0x0F] = 'l',
        [0x10] = 'm', [0x11] = 'n', [0x12] = 'o', [0x13] = 'p',
        [0x14] = 'q', [0x15] = 'r', [0x16] = 's', [0x17] = 't',
        [0x18] = 'u', [0x19] = 'v', [0x1A] = 'w', [0x1B] = 'x',
        [0x1C] = 'y', [0x1D] = 'z',
    };
    /* Space */
    if (hid == HID_SPACE) return ' ';
    /* Digit 1 -> '!' when shifted */
    if (hid == HID_1) return shift ? '!' : '1';
    /* Letters */
    if (hid >= 0x04 && hid <= 0x1D) {
        char c = unshifted[hid];
        return shift ? (c - 32) : c;
    }
    return 0;
}

/* Key description for logging */
static const char* key_desc(KeyEvent key) {
    static char buf[64];
    char ascii = hid_to_ascii(key.hid_keycode, key.shift);
    if (key.ctrl && key.hid_keycode == HID_C) return "Ctrl+C";
    if (key.ctrl && key.hid_keycode == HID_D) return "Ctrl+D";
    if (key.hid_keycode == HID_ENTER) return "Enter";
    if (key.hid_keycode == HID_ESC)   return "Escape";
    if (key.hid_keycode == HID_BS)    return "Backspace";
    if (key.hid_keycode == HID_TAB)   return "Tab";
    if (key.hid_keycode == HID_RIGHT) return "Right";
    if (key.hid_keycode == HID_LEFT)  return "Left";
    if (key.hid_keycode == HID_UP)    return "Up";
    if (key.hid_keycode == HID_DOWN)  return "Down";
    if (key.hid_keycode == HID_HOME)  return "Home";
    if (key.hid_keycode == HID_SPACE) return "Space";
    if (ascii) {
        snprintf(buf, sizeof(buf), "'%c' (0x%02x)", ascii, key.hid_keycode);
        return buf;
    }
    snprintf(buf, sizeof(buf), "HID 0x%02x", key.hid_keycode);
    return buf;
}

/* ------------------------------------------------------------------ */
/* UCS-4 to UTF-8 conversion                                         */
/* ------------------------------------------------------------------ */

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

/* ------------------------------------------------------------------ */
/* IME Engine state                                                   */
/* ------------------------------------------------------------------ */

typedef struct {
    HangulInputContext* hic;
    int active_language;       /* LANG_DIRECT or LANG_KOREAN */
    /* Internal buffers for ImeResult strings */
    char committed_buf[256];
    char preedit_buf[64];
} ImeEngine;

static ImeEngine* ime_engine_create(void) {
    ImeEngine* eng = calloc(1, sizeof(ImeEngine));
    if (!eng) return NULL;
    eng->hic = hangul_ic_new("2");  /* Dubeolsik 2-set */
    if (!eng->hic) { free(eng); return NULL; }
    eng->active_language = LANG_KOREAN;  /* Start in Korean mode */
    return eng;
}

static void ime_engine_destroy(ImeEngine* eng) {
    if (!eng) return;
    if (eng->hic) hangul_ic_delete(eng->hic);
    free(eng);
}

/* ------------------------------------------------------------------ */
/* Phase 1: IME processKey                                            */
/* ------------------------------------------------------------------ */

static ImeResult ime_process_key(ImeEngine* eng, KeyEvent key) {
    ImeResult result = {
        .committed = NULL, .preedit = NULL,
        .forward_key = false, .forward_desc = NULL,
        .original_key = key
    };

    /* Direct mode: bypass IME entirely */
    if (eng->active_language == LANG_DIRECT) {
        char ascii = hid_to_ascii(key.hid_keycode, key.shift);
        if (ascii && !key.ctrl && !key.alt && !key.super_key) {
            /* Printable character in direct mode -> commit directly */
            eng->committed_buf[0] = ascii;
            eng->committed_buf[1] = '\0';
            result.committed = eng->committed_buf;
            return result;
        }
        /* Non-printable or modified key -> forward */
        result.forward_key = true;
        result.forward_desc = key_desc(key);
        return result;
    }

    /* Korean mode below */

    bool has_modifier = key.ctrl || key.alt || key.super_key;
    bool is_special = (key.hid_keycode >= 0x28 && key.hid_keycode <= 0x2C) || /* Enter,Esc,BS,Tab,Space */
                      (key.hid_keycode >= 0x4A && key.hid_keycode <= 0x52);    /* Home..arrows */

    /* Backspace: try IME backspace first */
    if (key.hid_keycode == HID_BS && !has_modifier) {
        bool consumed = hangul_ic_backspace(eng->hic);
        if (consumed) {
            const ucschar* preedit = hangul_ic_get_preedit_string(eng->hic);
            if (preedit && preedit[0] != 0) {
                ucs4_to_utf8(preedit, eng->preedit_buf, sizeof(eng->preedit_buf));
                result.preedit = eng->preedit_buf;
            }
            return result;
        }
        /* Not consumed: forward backspace to terminal */
        result.forward_key = true;
        result.forward_desc = "Backspace";
        return result;
    }

    /* Space in Korean mode: commit composition + forward space */
    if (key.hid_keycode == HID_SPACE && !has_modifier) {
        if (!hangul_ic_is_empty(eng->hic)) {
            const ucschar* flushed = hangul_ic_flush(eng->hic);
            if (flushed && flushed[0] != 0) {
                ucs4_to_utf8(flushed, eng->committed_buf, sizeof(eng->committed_buf));
                result.committed = eng->committed_buf;
            }
        }
        result.forward_key = true;
        result.forward_desc = "Space";
        return result;
    }

    /* Modifier or special key: FLUSH preedit (not reset!) + forward */
    if (has_modifier || is_special) {
        if (!hangul_ic_is_empty(eng->hic)) {
            const ucschar* flushed = hangul_ic_flush(eng->hic);
            if (flushed && flushed[0] != 0) {
                ucs4_to_utf8(flushed, eng->committed_buf, sizeof(eng->committed_buf));
                result.committed = eng->committed_buf;
            }
        }
        result.forward_key = true;
        result.forward_desc = key_desc(key);
        return result;
    }

    /* Printable key: feed to libhangul */
    char ascii = hid_to_ascii(key.hid_keycode, key.shift);
    if (ascii == 0) {
        result.forward_key = true;
        result.forward_desc = "unmapped";
        return result;
    }

    bool consumed = hangul_ic_process(eng->hic, ascii);

    /* Read committed text */
    const ucschar* commit = hangul_ic_get_commit_string(eng->hic);
    if (commit && commit[0] != 0) {
        ucs4_to_utf8(commit, eng->committed_buf, sizeof(eng->committed_buf));
        result.committed = eng->committed_buf;
    }

    /* Read preedit */
    const ucschar* preedit = hangul_ic_get_preedit_string(eng->hic);
    if (preedit && preedit[0] != 0) {
        ucs4_to_utf8(preedit, eng->preedit_buf, sizeof(eng->preedit_buf));
        result.preedit = eng->preedit_buf;
    }

    if (!consumed) {
        if (!hangul_ic_is_empty(eng->hic)) {
            const ucschar* flushed = hangul_ic_flush(eng->hic);
            if (flushed && flushed[0] != 0) {
                ucs4_to_utf8(flushed, eng->committed_buf, sizeof(eng->committed_buf));
                result.committed = eng->committed_buf;
            }
        }
        result.forward_key = true;
        result.forward_desc = "not consumed by IME";
    }

    return result;
}

/* Flush (commit) pending composition. Used for language switch, pane deactivate. */
static ImeResult ime_flush(ImeEngine* eng) {
    ImeResult result = {
        .committed = NULL, .preedit = NULL,
        .forward_key = false, .forward_desc = NULL
    };
    if (!hangul_ic_is_empty(eng->hic)) {
        const ucschar* flushed = hangul_ic_flush(eng->hic);
        if (flushed && flushed[0] != 0) {
            ucs4_to_utf8(flushed, eng->committed_buf, sizeof(eng->committed_buf));
            result.committed = eng->committed_buf;
        }
    }
    return result;
}

/* Set active language. Flushes atomically if switching away from Korean. */
static ImeResult ime_set_language(ImeEngine* eng, int lang_id) {
    ImeResult result = {
        .committed = NULL, .preedit = NULL,
        .forward_key = false, .forward_desc = NULL
    };
    if (eng->active_language == lang_id) {
        return result;  /* No-op for same language */
    }
    /* Flush pending composition before switching */
    if (eng->active_language == LANG_KOREAN) {
        result = ime_flush(eng);
    }
    eng->active_language = lang_id;
    return result;
}

/* ------------------------------------------------------------------ */
/* Phase 2: Simulated ghostty API calls                               */
/*                                                                    */
/* These simulate what libitshell3 would do with ImeResult:            */
/*   committed_text -> ghostty_surface_key (text goes to PTY)         */
/*   preedit_text   -> ghostty_surface_preedit (overlay on surface)   */
/*   forward_key    -> ghostty_surface_key (escape seq to PTY)        */
/* ------------------------------------------------------------------ */

static void sim_ghostty_surface_key(SimTerminal* term, const char* text, const char* desc) {
    printf("  API: ghostty_surface_key(text=\"%s\") [%s]\n", text ? text : "NULL", desc);
    if (text) {
        sim_terminal_put_string(term, text);
    }
}

static void sim_ghostty_surface_preedit(SimTerminal* term, const char* utf8_text, int len) {
    if (utf8_text && len > 0) {
        printf("  API: ghostty_surface_preedit(\"%s\", %d)\n", utf8_text, len);
        sim_terminal_set_preedit(term, utf8_text);
    } else {
        printf("  API: ghostty_surface_preedit(NULL, 0)  [clear]\n");
        sim_terminal_clear_preedit(term);
    }
}

/* Forward a special/modifier key to the terminal */
static void sim_ghostty_forward_key(SimTerminal* term, KeyEvent key, const char* desc) {
    printf("  API: ghostty_surface_key(forward=%s)\n", desc);
    /* Simulate the effect of special keys on the terminal buffer */
    if (key.hid_keycode == HID_ENTER) {
        sim_terminal_newline(term);
    } else if (key.hid_keycode == HID_BS) {
        sim_terminal_backspace(term);
    } else if (key.hid_keycode == HID_LEFT) {
        sim_terminal_move_cursor(term, SIM_TERM_LEFT);
    } else if (key.hid_keycode == HID_RIGHT) {
        sim_terminal_move_cursor(term, SIM_TERM_RIGHT);
    } else if (key.hid_keycode == HID_UP) {
        sim_terminal_move_cursor(term, SIM_TERM_UP);
    } else if (key.hid_keycode == HID_DOWN) {
        sim_terminal_move_cursor(term, SIM_TERM_DOWN);
    } else if (key.hid_keycode == HID_HOME) {
        sim_terminal_move_cursor(term, SIM_TERM_HOME);
    } else if (key.hid_keycode == HID_TAB) {
        /* Tab -> insert spaces (simplified) */
        sim_terminal_put_string(term, "    ");
    } else if (key.hid_keycode == HID_SPACE) {
        sim_terminal_put_char(term, " ");
    }
    /* Ctrl+C, Ctrl+D, Escape: in real ghostty these would produce signals/escapes.
     * For the PoC we just log them without terminal buffer effect. */
}

/* ------------------------------------------------------------------ */
/* Integrated pipeline: key event -> IME -> ghostty -> terminal       */
/* ------------------------------------------------------------------ */

static void process_and_display(ImeEngine* eng, SimTerminal* term, KeyEvent key) {
    printf("[Key: %s]\n", key_desc(key));

    /* Phase 1: IME */
    ImeResult r = ime_process_key(eng, key);

    /* Log IME result */
    if (r.committed || r.preedit) {
        printf("  IME -> ");
        if (r.committed) printf("commit=\"%s\" ", r.committed);
        if (r.preedit)   printf("preedit=\"%s\"", r.preedit);
        printf("\n");
    } else if (r.forward_key) {
        printf("  IME -> forward [%s]\n", r.forward_desc);
    } else {
        printf("  IME -> (no output)\n");
    }

    /* Phase 2: ghostty API calls */
    if (r.committed) {
        sim_ghostty_surface_key(term, r.committed, "committed text");
    }
    if (r.preedit) {
        sim_ghostty_surface_preedit(term, r.preedit, (int)strlen(r.preedit));
    } else {
        /* No preedit means composition ended -- clear overlay */
        sim_ghostty_surface_preedit(term, NULL, 0);
    }
    if (r.forward_key) {
        sim_ghostty_forward_key(term, r.original_key, r.forward_desc);
    }

    /* Visual output */
    sim_terminal_dump(term);
    printf("\n");
}

/* Convenience: process a key and display, with language switch */
static void switch_language_and_display(ImeEngine* eng, SimTerminal* term, int lang_id) {
    const char* lang_name = (lang_id == LANG_KOREAN) ? "Korean" : "Direct (English)";
    printf("[Language Switch -> %s]\n", lang_name);
    ImeResult r = ime_set_language(eng, lang_id);
    if (r.committed) {
        printf("  Flush on switch: commit=\"%s\"\n", r.committed);
        sim_ghostty_surface_key(term, r.committed, "flush on lang switch");
    }
    sim_ghostty_surface_preedit(term, NULL, 0);
    sim_terminal_dump(term);
    printf("\n");
}

/* ------------------------------------------------------------------ */
/* Key event construction macros                                      */
/* ------------------------------------------------------------------ */

#define KEY(hid)         ((KeyEvent){ .hid_keycode = (hid) })
#define KEY_SHIFT(hid)   ((KeyEvent){ .hid_keycode = (hid), .shift = true })
#define KEY_CTRL(hid)    ((KeyEvent){ .hid_keycode = (hid), .ctrl = true })

/* ------------------------------------------------------------------ */
/* Test Scenarios                                                     */
/* ------------------------------------------------------------------ */

static void group1_basic_composition(ImeEngine* eng, SimTerminal* term) {
    printf("╔══════════════════════════════════════════════════╗\n");
    printf("║  Group 1: Basic Composition                     ║\n");
    printf("╚══════════════════════════════════════════════════╝\n\n");

    /* Test 1: r,k,s,r -> 간ㄱ (syllable break) */
    printf("--- Test 1: r,k,s,r -> syllable break ---\n");
    sim_terminal_reset(term);
    hangul_ic_reset(eng->hic);
    process_and_display(eng, term, KEY(HID_R));  /* preedit=ㄱ */
    process_and_display(eng, term, KEY(HID_K));  /* preedit=가 */
    process_and_display(eng, term, KEY(HID_S));  /* preedit=간 */
    process_and_display(eng, term, KEY(HID_R));  /* commit=간, preedit=ㄱ */

    /* Test 2: Arrow during composition -> flush + cursor move */
    printf("--- Test 2: Arrow during composition ---\n");
    sim_terminal_reset(term);
    hangul_ic_reset(eng->hic);
    process_and_display(eng, term, KEY(HID_R));     /* preedit=ㄱ */
    process_and_display(eng, term, KEY(HID_K));     /* preedit=가 */
    process_and_display(eng, term, KEY(HID_RIGHT)); /* flush 가, forward Right */

    /* Test 3: Ctrl+C during composition -> flush + forward */
    printf("--- Test 3: Ctrl+C during composition ---\n");
    sim_terminal_reset(term);
    hangul_ic_reset(eng->hic);
    process_and_display(eng, term, KEY(HID_R));     /* preedit=ㄱ */
    process_and_display(eng, term, KEY(HID_K));     /* preedit=가 */
    process_and_display(eng, term, KEY(HID_S));     /* preedit=간 */
    process_and_display(eng, term, KEY_CTRL(HID_C)); /* flush 간, forward Ctrl+C */

    /* Test 4: Enter during composition -> flush + newline */
    printf("--- Test 4: Enter during composition ---\n");
    sim_terminal_reset(term);
    hangul_ic_reset(eng->hic);
    process_and_display(eng, term, KEY(HID_R));     /* preedit=ㄱ */
    process_and_display(eng, term, KEY(HID_ENTER)); /* flush ㄱ, forward Enter */

    /* Test 5: Backspace chain: 간 -> 가 -> ㄱ -> empty -> delete char */
    printf("--- Test 5: Backspace chain (jamo undo) ---\n");
    sim_terminal_reset(term);
    hangul_ic_reset(eng->hic);
    process_and_display(eng, term, KEY(HID_R));  /* preedit=ㄱ */
    process_and_display(eng, term, KEY(HID_K));  /* preedit=가 */
    process_and_display(eng, term, KEY(HID_S));  /* preedit=간 */
    process_and_display(eng, term, KEY(HID_BS)); /* preedit=가 */
    process_and_display(eng, term, KEY(HID_BS)); /* preedit=ㄱ */
    process_and_display(eng, term, KEY(HID_BS)); /* empty */
    process_and_display(eng, term, KEY(HID_BS)); /* forward backspace to terminal */
}

static void group2_buffer_accumulation(ImeEngine* eng, SimTerminal* term) {
    printf("╔══════════════════════════════════════════════════╗\n");
    printf("║  Group 2: Buffer Accumulation                   ║\n");
    printf("╚══════════════════════════════════════════════════╝\n\n");

    /* Test 6: Type "한글" (two syllables) */
    printf("--- Test 6: Type \"han-geul\" (한글) ---\n");
    sim_terminal_reset(term);
    hangul_ic_reset(eng->hic);
    eng->active_language = LANG_KOREAN;
    /* 한: h(ㅎ)=g(0x0A), a(ㅏ)=k(0x0E), n(ㄴ)=s(0x16) */
    /* Actually: ㅎ=g, ㅏ=k, ㄴ=s -> 한 */
    process_and_display(eng, term, KEY(HID_G));  /* ㅎ -> preedit=ㅎ */
    process_and_display(eng, term, KEY(HID_K));  /* ㅏ -> preedit=하 */
    process_and_display(eng, term, KEY(HID_S));  /* ㄴ -> preedit=한 */
    /* 글: ㄱ=r, ㅡ=m(0x10), ㄹ=f */
    process_and_display(eng, term, KEY(HID_R));  /* commit=한, preedit=ㄱ */
    process_and_display(eng, term, KEY(HID_M));  /* ㅡ -> preedit=그 */
    process_and_display(eng, term, KEY(HID_F));  /* ㄹ -> preedit=글 */
    /* Flush to see final buffer */
    printf("[Flush remaining]\n");
    ImeResult flush_r = ime_flush(eng);
    if (flush_r.committed) {
        sim_ghostty_surface_key(term, flush_r.committed, "final flush");
        sim_ghostty_surface_preedit(term, NULL, 0);
    }
    sim_terminal_dump(term);
    printf("\n");

    /* Test 7: Type "한" + Space + "글" */
    printf("--- Test 7: \"han\" + Space + \"geul\" (한 글) ---\n");
    sim_terminal_reset(term);
    hangul_ic_reset(eng->hic);
    process_and_display(eng, term, KEY(HID_G));     /* ㅎ */
    process_and_display(eng, term, KEY(HID_K));     /* ㅏ -> 하 */
    process_and_display(eng, term, KEY(HID_S));     /* ㄴ -> 한 */
    process_and_display(eng, term, KEY(HID_SPACE)); /* flush 한 + space */
    process_and_display(eng, term, KEY(HID_R));     /* ㄱ */
    process_and_display(eng, term, KEY(HID_M));     /* ㅡ -> 그 */
    process_and_display(eng, term, KEY(HID_F));     /* ㄹ -> 글 */
    printf("[Flush remaining]\n");
    flush_r = ime_flush(eng);
    if (flush_r.committed) {
        sim_ghostty_surface_key(term, flush_r.committed, "final flush");
        sim_ghostty_surface_preedit(term, NULL, 0);
    }
    sim_terminal_dump(term);
    printf("\n");

    /* Test 8: Type "hello" in direct mode */
    printf("--- Test 8: \"hello\" in direct mode ---\n");
    sim_terminal_reset(term);
    hangul_ic_reset(eng->hic);
    eng->active_language = LANG_DIRECT;
    process_and_display(eng, term, KEY(HID_H));
    process_and_display(eng, term, KEY(HID_E));
    process_and_display(eng, term, KEY(HID_L));
    process_and_display(eng, term, KEY(HID_L));
    process_and_display(eng, term, KEY(HID_O));
    eng->active_language = LANG_KOREAN;  /* restore for next tests */

    /* Test 9: Mixed: "hi" (direct) -> Korean "한글" */
    printf("--- Test 9: Mixed direct + Korean ---\n");
    sim_terminal_reset(term);
    hangul_ic_reset(eng->hic);
    eng->active_language = LANG_DIRECT;
    process_and_display(eng, term, KEY(HID_H));
    process_and_display(eng, term, KEY(HID_I));
    /* Switch to Korean */
    switch_language_and_display(eng, term, LANG_KOREAN);
    process_and_display(eng, term, KEY(HID_G));  /* ㅎ */
    process_and_display(eng, term, KEY(HID_K));  /* ㅏ -> 하 */
    process_and_display(eng, term, KEY(HID_S));  /* ㄴ -> 한 */
    process_and_display(eng, term, KEY(HID_R));  /* commit 한, preedit ㄱ */
    process_and_display(eng, term, KEY(HID_M));  /* ㅡ -> 그 */
    process_and_display(eng, term, KEY(HID_F));  /* ㄹ -> 글 */
    printf("[Flush remaining]\n");
    flush_r = ime_flush(eng);
    if (flush_r.committed) {
        sim_ghostty_surface_key(term, flush_r.committed, "final flush");
        sim_ghostty_surface_preedit(term, NULL, 0);
    }
    sim_terminal_dump(term);
    printf("\n");
}

static void group3_editing_with_cursor(ImeEngine* eng, SimTerminal* term) {
    printf("╔══════════════════════════════════════════════════╗\n");
    printf("║  Group 3: Editing with Cursor                   ║\n");
    printf("╚══════════════════════════════════════════════════╝\n\n");

    /* Test 10: Type "가나다" -> Left*3 -> type "마" -> insertion */
    printf("--- Test 10: Insert at cursor (가나다 -> 가마나다) ---\n");
    sim_terminal_reset(term);
    hangul_ic_reset(eng->hic);
    eng->active_language = LANG_KOREAN;
    /* Type 가: r(ㄱ) k(ㅏ) */
    process_and_display(eng, term, KEY(HID_R));
    process_and_display(eng, term, KEY(HID_K));
    /* Type 나: s(ㄴ) k(ㅏ) -> syllable break commits 가 */
    process_and_display(eng, term, KEY(HID_S));  /* 간 preedit (ㄴ as jongseong) */
    process_and_display(eng, term, KEY(HID_K));  /* commit 가, preedit 나 */
    /* Type 다: e(ㄷ)=c? no... ㄷ is 'e' key. Let me check: HID_E=0x08 */
    /* Actually in dubeolsik: ㄷ = 'e' position (HID_E=0x08) */
    process_and_display(eng, term, KEY(HID_E));  /* commit 나, preedit ㄷ */
    process_and_display(eng, term, KEY(HID_K));  /* preedit 다 */
    /* Flush to commit 다 */
    printf("[Flush]\n");
    ImeResult flush_r = ime_flush(eng);
    if (flush_r.committed) {
        sim_ghostty_surface_key(term, flush_r.committed, "flush");
        sim_ghostty_surface_preedit(term, NULL, 0);
    }
    sim_terminal_dump(term);
    printf("\n");
    /* Now move left 3 times (past 다, 나... each Korean char is 2 cells) */
    process_and_display(eng, term, KEY(HID_LEFT));
    process_and_display(eng, term, KEY(HID_LEFT));
    /* Type 마: a(ㅁ)=a(HID_A), k(ㅏ) */
    process_and_display(eng, term, KEY(HID_A));  /* ㅁ preedit */
    process_and_display(eng, term, KEY(HID_K));  /* 마 preedit */
    /* Flush 마 */
    printf("[Flush]\n");
    flush_r = ime_flush(eng);
    if (flush_r.committed) {
        sim_ghostty_surface_key(term, flush_r.committed, "flush");
        sim_ghostty_surface_preedit(term, NULL, 0);
    }
    sim_terminal_dump(term);
    printf("\n");

    /* Test 11: Type "테스트" -> Backspace -> "테스" */
    printf("--- Test 11: Backspace deletes last syllable ---\n");
    sim_terminal_reset(term);
    hangul_ic_reset(eng->hic);
    /* 테: ㅌ=x(HID_X=0x1B), ㅔ=p(HID_P=0x13) */
    /* Actually dubeolsik: ㅌ=x, ㅔ=p */
    process_and_display(eng, term, KEY(HID_X));  /* ㅌ preedit */
    process_and_display(eng, term, KEY(HID_P));  /* 테 preedit */
    /* 스: ㅅ=t(HID_T=0x17), ㅡ=m(HID_M=0x10) */
    process_and_display(eng, term, KEY(HID_T));  /* commit 테, preedit ㅅ */
    process_and_display(eng, term, KEY(HID_M));  /* preedit 스 */
    /* 트: ㅌ=x, ㅡ=m */
    process_and_display(eng, term, KEY(HID_X));  /* commit 스, preedit ㅌ */
    process_and_display(eng, term, KEY(HID_M));  /* preedit 트 */
    /* Backspace removes ㅡ from 트 -> ㅌ */
    process_and_display(eng, term, KEY(HID_BS)); /* preedit ㅌ */
    /* Backspace removes ㅌ -> empty */
    process_and_display(eng, term, KEY(HID_BS)); /* empty preedit */
    /* Buffer should show "테스" */

    /* Test 12: Type "한" -> Enter -> "글" -> two lines */
    printf("--- Test 12: Enter creates new line ---\n");
    sim_terminal_reset(term);
    hangul_ic_reset(eng->hic);
    process_and_display(eng, term, KEY(HID_G));     /* ㅎ */
    process_and_display(eng, term, KEY(HID_K));     /* 하 */
    process_and_display(eng, term, KEY(HID_S));     /* 한 */
    process_and_display(eng, term, KEY(HID_ENTER)); /* flush 한, newline */
    process_and_display(eng, term, KEY(HID_R));     /* ㄱ */
    process_and_display(eng, term, KEY(HID_M));     /* 그 */
    process_and_display(eng, term, KEY(HID_F));     /* 글 */
    printf("[Flush]\n");
    flush_r = ime_flush(eng);
    if (flush_r.committed) {
        sim_ghostty_surface_key(term, flush_r.committed, "flush");
        sim_ghostty_surface_preedit(term, NULL, 0);
    }
    sim_terminal_dump(term);
    printf("\n");

    /* Test 13: Type "abc" -> Home -> Korean -> inserted before "abc" */
    printf("--- Test 13: Korean before English (Home + compose) ---\n");
    sim_terminal_reset(term);
    hangul_ic_reset(eng->hic);
    eng->active_language = LANG_DIRECT;
    process_and_display(eng, term, KEY(HID_A));
    process_and_display(eng, term, KEY(HID_B));
    process_and_display(eng, term, KEY(HID_C));
    /* Move cursor to Home */
    process_and_display(eng, term, KEY(HID_HOME));
    /* Switch to Korean */
    switch_language_and_display(eng, term, LANG_KOREAN);
    /* Type ㄱ */
    process_and_display(eng, term, KEY(HID_R));  /* preedit ㄱ */
    process_and_display(eng, term, KEY(HID_K));  /* preedit 가 */
    printf("[Flush]\n");
    flush_r = ime_flush(eng);
    if (flush_r.committed) {
        sim_ghostty_surface_key(term, flush_r.committed, "flush");
        sim_ghostty_surface_preedit(term, NULL, 0);
    }
    sim_terminal_dump(term);
    printf("\n");
}

static void group4_modifiers(ImeEngine* eng, SimTerminal* term) {
    printf("╔══════════════════════════════════════════════════╗\n");
    printf("║  Group 4: Modifiers                             ║\n");
    printf("╚══════════════════════════════════════════════════╝\n\n");

    eng->active_language = LANG_KOREAN;

    /* Test 14: Ctrl+C with no composition -> forward only */
    printf("--- Test 14: Ctrl+C no composition ---\n");
    sim_terminal_reset(term);
    hangul_ic_reset(eng->hic);
    process_and_display(eng, term, KEY_CTRL(HID_C));

    /* Test 15: Escape during composition -> flush + forward */
    printf("--- Test 15: Escape during composition ---\n");
    sim_terminal_reset(term);
    hangul_ic_reset(eng->hic);
    process_and_display(eng, term, KEY(HID_R));    /* preedit ㄱ */
    process_and_display(eng, term, KEY(HID_K));    /* preedit 가 */
    process_and_display(eng, term, KEY(HID_ESC));  /* flush 가, forward Esc */

    /* Test 16: Tab during composition -> flush + tab */
    printf("--- Test 16: Tab during composition ---\n");
    sim_terminal_reset(term);
    hangul_ic_reset(eng->hic);
    process_and_display(eng, term, KEY(HID_R));    /* preedit ㄱ */
    process_and_display(eng, term, KEY(HID_TAB));  /* flush ㄱ, forward Tab */

    /* Test 17: Ctrl+D no composition -> forward EOF */
    printf("--- Test 17: Ctrl+D no composition ---\n");
    sim_terminal_reset(term);
    hangul_ic_reset(eng->hic);
    process_and_display(eng, term, KEY_CTRL(HID_D));
}

static void group5_edge_cases(ImeEngine* eng, SimTerminal* term) {
    printf("╔══════════════════════════════════════════════════╗\n");
    printf("║  Group 5: Edge Cases                            ║\n");
    printf("╚══════════════════════════════════════════════════╝\n\n");

    eng->active_language = LANG_KOREAN;

    /* Test 18: Rapid syllable breaks: r,k,s,k,s,k -> 간악? */
    /* Let's trace: r=ㄱ, k=ㅏ -> 가, s=ㄴ -> 간, k=ㅏ -> commit 간 + preedit 나?
     * Actually: s(ㄴ) after 가 -> 간 (jongseong), then k(ㅏ) -> 가+나 split:
     * commit 가, preedit 나. Then s(ㄴ) -> 난, k(ㅏ) -> commit 나, preedit 나 */
    printf("--- Test 18: Rapid syllable breaks (r,k,s,k,s,k) ---\n");
    sim_terminal_reset(term);
    hangul_ic_reset(eng->hic);
    process_and_display(eng, term, KEY(HID_R));  /* ㄱ */
    process_and_display(eng, term, KEY(HID_K));  /* 가 */
    process_and_display(eng, term, KEY(HID_S));  /* 간 */
    process_and_display(eng, term, KEY(HID_K));  /* commit 가, preedit 나 */
    process_and_display(eng, term, KEY(HID_S));  /* 난 */
    process_and_display(eng, term, KEY(HID_K));  /* commit 나, preedit 나 */
    printf("[Flush]\n");
    ImeResult flush_r = ime_flush(eng);
    if (flush_r.committed) {
        sim_ghostty_surface_key(term, flush_r.committed, "flush");
        sim_ghostty_surface_preedit(term, NULL, 0);
    }
    sim_terminal_dump(term);
    printf("\n");

    /* Test 19: Shift+R (ㄲ) + k (ㅏ) -> 까 -> Enter */
    printf("--- Test 19: Double consonant (Shift+R = ㄲ) ---\n");
    sim_terminal_reset(term);
    hangul_ic_reset(eng->hic);
    process_and_display(eng, term, KEY_SHIFT(HID_R)); /* ㄲ */
    process_and_display(eng, term, KEY(HID_K));       /* 까 */
    process_and_display(eng, term, KEY(HID_ENTER));   /* flush 까, Enter */

    /* Test 20: Compose -> language switch -> compose again */
    printf("--- Test 20: Language switch mid-composition ---\n");
    sim_terminal_reset(term);
    hangul_ic_reset(eng->hic);
    eng->active_language = LANG_KOREAN;
    process_and_display(eng, term, KEY(HID_R));  /* ㄱ */
    process_and_display(eng, term, KEY(HID_K));  /* 가 */
    /* Switch to direct (flushes 가) */
    switch_language_and_display(eng, term, LANG_DIRECT);
    process_and_display(eng, term, KEY(HID_H));  /* 'h' */
    process_and_display(eng, term, KEY(HID_I));  /* 'i' */
    /* Switch back to Korean */
    switch_language_and_display(eng, term, LANG_KOREAN);
    process_and_display(eng, term, KEY(HID_S));  /* ㄴ */
    process_and_display(eng, term, KEY(HID_K));  /* 나 */
    printf("[Flush]\n");
    flush_r = ime_flush(eng);
    if (flush_r.committed) {
        sim_ghostty_surface_key(term, flush_r.committed, "flush");
        sim_ghostty_surface_preedit(term, NULL, 0);
    }
    sim_terminal_dump(term);
    printf("\n");

    /* Test 21: Empty backspace -> forward to terminal */
    printf("--- Test 21: Empty backspace (no composition) ---\n");
    sim_terminal_reset(term);
    hangul_ic_reset(eng->hic);
    eng->active_language = LANG_KOREAN;
    /* Put some text first */
    eng->active_language = LANG_DIRECT;
    process_and_display(eng, term, KEY(HID_A));
    process_and_display(eng, term, KEY(HID_B));
    eng->active_language = LANG_KOREAN;
    /* Backspace with no composition -> forwarded */
    process_and_display(eng, term, KEY(HID_BS));

    /* Test 22: Korean -> pane deactivate (flush) -> reactivate -> new composition */
    printf("--- Test 22: Pane deactivate/reactivate ---\n");
    sim_terminal_reset(term);
    hangul_ic_reset(eng->hic);
    eng->active_language = LANG_KOREAN;
    process_and_display(eng, term, KEY(HID_R));  /* ㄱ */
    process_and_display(eng, term, KEY(HID_K));  /* 가 */
    /* Simulate pane deactivate */
    printf("[Pane Deactivate]\n");
    ImeResult deact = ime_flush(eng);
    if (deact.committed) {
        printf("  Deactivate flush: commit=\"%s\"\n", deact.committed);
        sim_ghostty_surface_key(term, deact.committed, "deactivate flush");
        sim_ghostty_surface_preedit(term, NULL, 0);
    }
    sim_terminal_dump(term);
    printf("\n");
    /* Simulate reactivate */
    printf("[Pane Reactivate]\n");
    /* New composition */
    process_and_display(eng, term, KEY(HID_S));  /* ㄴ */
    process_and_display(eng, term, KEY(HID_K));  /* 나 */
    printf("[Flush]\n");
    flush_r = ime_flush(eng);
    if (flush_r.committed) {
        sim_ghostty_surface_key(term, flush_r.committed, "flush");
        sim_ghostty_surface_preedit(term, NULL, 0);
    }
    sim_terminal_dump(term);
    printf("\n");
}

static void group6_visual_verification(ImeEngine* eng, SimTerminal* term) {
    printf("╔══════════════════════════════════════════════════╗\n");
    printf("║  Group 6: Visual Verification                   ║\n");
    printf("╚══════════════════════════════════════════════════╝\n\n");

    /* Test 23: Full sentence: "안녕하세요" -> Enter -> "Hello!" */
    printf("--- Test 23: Full sentence ---\n");
    sim_terminal_reset(term);
    hangul_ic_reset(eng->hic);
    eng->active_language = LANG_KOREAN;
    /* 안: ㅇ=d(HID_D=0x07), ㅏ=k, ㄴ=s */
    process_and_display(eng, term, KEY(HID_D));  /* ㅇ */
    process_and_display(eng, term, KEY(HID_K));  /* 아 */
    process_and_display(eng, term, KEY(HID_S));  /* 안 */
    /* 녕: ㄴ=s, ㅕ=u(HID_U=0x18), ㅇ=d */
    process_and_display(eng, term, KEY(HID_S));  /* commit 안, preedit ㄴ */
    process_and_display(eng, term, KEY(HID_U));  /* 녀 */
    process_and_display(eng, term, KEY(HID_D));  /* 녕 */
    /* 하: ㅎ=g, ㅏ=k */
    process_and_display(eng, term, KEY(HID_G));  /* commit 녕, preedit ㅎ */
    process_and_display(eng, term, KEY(HID_K));  /* 하 */
    /* 세: ㅅ=t, ㅔ=p */
    process_and_display(eng, term, KEY(HID_T));  /* commit 하, preedit ㅅ */
    process_and_display(eng, term, KEY(HID_P));  /* 세 */
    /* 요: ㅇ=d, ㅛ=y? Actually ㅛ = 'y' in dubeolsik? No.
     * Dubeolsik: ㅛ is mapped to 'y' position? Let me check:
     * y(HID_Y=0x1C) -> ㅛ in dubeolsik? Actually 'y' key = ㅛ?
     * No wait, in dubeolsik layout: y -> no. Let me reconsider.
     * Dubeolsik vowels:
     *   k=ㅏ, o=ㅐ, i=ㅑ, O=ㅒ, j=ㅓ, p=ㅔ, u=ㅕ, P=ㅖ,
     *   h=ㅗ, y=ㅛ, n=ㅜ, b=ㅠ, m=ㅡ, l=ㅣ
     * Yes, y = ㅛ. So ㅛ = HID_Y.
     */
    process_and_display(eng, term, KEY(HID_D));  /* commit 세, preedit ㅇ */
    process_and_display(eng, term, KEY(HID_Y));  /* 요 */
    /* Flush and Enter */
    process_and_display(eng, term, KEY(HID_ENTER)); /* flush 요, Enter */
    /* Switch to English and type "Hello!" */
    switch_language_and_display(eng, term, LANG_DIRECT);
    process_and_display(eng, term, KEY_SHIFT(HID_H)); /* 'H' */
    process_and_display(eng, term, KEY(HID_E));       /* 'e' */
    process_and_display(eng, term, KEY(HID_L));       /* 'l' */
    process_and_display(eng, term, KEY(HID_L));       /* 'l' */
    process_and_display(eng, term, KEY(HID_O));       /* 'o' */
    process_and_display(eng, term, KEY_SHIFT(HID_1)); /* '!' */

    /* Test 24: Wide char cursor alignment */
    printf("--- Test 24: Wide char cursor alignment ---\n");
    sim_terminal_reset(term);
    hangul_ic_reset(eng->hic);
    eng->active_language = LANG_DIRECT;
    /* Type "A" then Korean "가" then "B" -> check alignment */
    process_and_display(eng, term, KEY(HID_A));
    switch_language_and_display(eng, term, LANG_KOREAN);
    process_and_display(eng, term, KEY(HID_R));  /* ㄱ */
    process_and_display(eng, term, KEY(HID_K));  /* 가 */
    /* Flush 가 */
    printf("[Flush]\n");
    ImeResult flush_r = ime_flush(eng);
    if (flush_r.committed) {
        sim_ghostty_surface_key(term, flush_r.committed, "flush");
        sim_ghostty_surface_preedit(term, NULL, 0);
    }
    sim_terminal_dump(term);
    switch_language_and_display(eng, term, LANG_DIRECT);
    process_and_display(eng, term, KEY(HID_B));  /* 'B' after wide char */
    /* Final state: "A가B" with proper alignment */
}

/* ------------------------------------------------------------------ */
/* Main                                                               */
/* ------------------------------------------------------------------ */

int main(void) {
    printf("================================================================\n");
    printf("  IME + Simulated Ghostty Pipeline PoC\n");
    printf("  24 test scenarios across 6 groups\n");
    printf("================================================================\n\n");

    ImeEngine* eng = ime_engine_create();
    if (!eng) {
        fprintf(stderr, "Failed to create IME engine\n");
        return 1;
    }

    SimTerminal* term = sim_terminal_create(TERM_COLS, TERM_ROWS);
    if (!term) {
        fprintf(stderr, "Failed to create simulated terminal\n");
        ime_engine_destroy(eng);
        return 1;
    }

    group1_basic_composition(eng, term);
    group2_buffer_accumulation(eng, term);
    group3_editing_with_cursor(eng, term);
    group4_modifiers(eng, term);
    group5_edge_cases(eng, term);
    group6_visual_verification(eng, term);

    printf("================================================================\n");
    printf("  All 24 test scenarios completed.\n");
    printf("================================================================\n");

    sim_terminal_destroy(term);
    ime_engine_destroy(eng);
    return 0;
}
