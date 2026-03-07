/**
 * sim_terminal.c — Simulated terminal buffer implementation.
 *
 * Provides an 80×24 (configurable) terminal grid with:
 *  - Wide character support (Korean = 2 cells, ASCII = 1 cell)
 *  - Cursor tracking and movement
 *  - Character insertion, backspace, newline, scrolling
 *  - Preedit overlay (separate from buffer)
 *  - Visual screen dump with box drawing
 */

#include "sim_terminal.h"

#include <locale.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

/* Maximum bytes in a single UTF-8 codepoint */
#define MAX_UTF8_BYTES 4

/* Maximum preedit string length in bytes */
#define MAX_PREEDIT 128

/**
 * A single cell in the terminal grid.
 *
 * For wide characters (width 2), the first cell holds the character and
 * the second cell is a "continuation" cell (is_continuation = true,
 * utf8 is empty). This mirrors how real terminals handle CJK.
 */
typedef struct {
    char utf8[MAX_UTF8_BYTES + 1]; /* UTF-8 encoded character, NUL-terminated */
    int  width;                     /* Display width: 0 (empty/continuation), 1, or 2 */
    bool is_continuation;           /* True if this cell is the right half of a wide char */
} Cell;

struct SimTerminal {
    int   cols;
    int   rows;
    Cell* grid;    /* rows * cols cells, row-major */
    int   cur_row;
    int   cur_col;
    char  preedit[MAX_PREEDIT]; /* UTF-8 preedit string */
};

/* ---- Internal helpers ---- */

static Cell* cell_at(SimTerminal* term, int row, int col) {
    return &term->grid[row * term->cols + col];
}

static void cell_clear(Cell* c) {
    c->utf8[0] = '\0';
    c->width = 0;
    c->is_continuation = false;
}

static void clear_row(SimTerminal* term, int row) {
    for (int c = 0; c < term->cols; c++) {
        cell_clear(cell_at(term, row, c));
    }
}

/**
 * Decode the first UTF-8 codepoint from `s` into `cp`.
 * Returns the number of bytes consumed, or 0 on error.
 */
static int utf8_decode(const char* s, uint32_t* cp) {
    const unsigned char* u = (const unsigned char*)s;
    if (u[0] == 0) return 0;

    if (u[0] < 0x80) {
        *cp = u[0];
        return 1;
    } else if ((u[0] & 0xE0) == 0xC0) {
        if ((u[1] & 0xC0) != 0x80) return 0;
        *cp = ((uint32_t)(u[0] & 0x1F) << 6) | (u[1] & 0x3F);
        return 2;
    } else if ((u[0] & 0xF0) == 0xE0) {
        if ((u[1] & 0xC0) != 0x80 || (u[2] & 0xC0) != 0x80) return 0;
        *cp = ((uint32_t)(u[0] & 0x0F) << 12) |
              ((uint32_t)(u[1] & 0x3F) << 6) |
              (u[2] & 0x3F);
        return 3;
    } else if ((u[0] & 0xF8) == 0xF0) {
        if ((u[1] & 0xC0) != 0x80 || (u[2] & 0xC0) != 0x80 ||
            (u[3] & 0xC0) != 0x80)
            return 0;
        *cp = ((uint32_t)(u[0] & 0x07) << 18) |
              ((uint32_t)(u[1] & 0x3F) << 12) |
              ((uint32_t)(u[2] & 0x3F) << 6) |
              (u[3] & 0x3F);
        return 4;
    }
    return 0;
}

/**
 * Determine the display width of a Unicode codepoint.
 * Uses wcwidth() with a fallback for known Korean ranges.
 */
static int codepoint_width(uint32_t cp) {
    /* Korean Hangul syllables (U+AC00-U+D7A3) */
    if (cp >= 0xAC00 && cp <= 0xD7A3) return 2;
    /* Hangul compatibility jamo (U+3131-U+318E) */
    if (cp >= 0x3131 && cp <= 0x318E) return 2;
    /* Hangul jamo (U+1100-U+11FF) */
    if (cp >= 0x1100 && cp <= 0x11FF) return 2;

    /* Try wcwidth for other characters */
    int w = wcwidth((wchar_t)cp);
    if (w < 0) return 1; /* treat control chars as width 1 for safety */
    return w;
}

/**
 * Scroll the grid up by one row. The top row is discarded,
 * all other rows move up, and the bottom row is cleared.
 */
static void scroll_up(SimTerminal* term) {
    /* Move rows 1..rows-1 up to 0..rows-2 */
    memmove(term->grid,
            term->grid + term->cols,
            (size_t)(term->rows - 1) * (size_t)term->cols * sizeof(Cell));
    clear_row(term, term->rows - 1);
}

/* ---- Public API ---- */

SimTerminal* sim_terminal_create(int cols, int rows) {
    SimTerminal* term = calloc(1, sizeof(SimTerminal));
    if (!term) return NULL;

    term->cols = cols;
    term->rows = rows;
    term->grid = calloc((size_t)cols * (size_t)rows, sizeof(Cell));
    if (!term->grid) {
        free(term);
        return NULL;
    }

    /* Ensure locale is set for wcwidth to work */
    setlocale(LC_ALL, "");

    return term;
}

void sim_terminal_destroy(SimTerminal* term) {
    if (!term) return;
    free(term->grid);
    free(term);
}

void sim_terminal_put_char(SimTerminal* term, const char* utf8_char) {
    if (!term || !utf8_char || !utf8_char[0]) return;

    uint32_t cp;
    int bytes = utf8_decode(utf8_char, &cp);
    if (bytes == 0) return;

    int w = codepoint_width(cp);

    /* Check if the character fits on the current line */
    if (term->cur_col + w > term->cols) {
        /* Wrap to next line */
        sim_terminal_newline(term);
    }

    Cell* c = cell_at(term, term->cur_row, term->cur_col);
    memcpy(c->utf8, utf8_char, (size_t)bytes);
    c->utf8[bytes] = '\0';
    c->width = w;
    c->is_continuation = false;

    term->cur_col++;

    /* Mark continuation cell for wide characters */
    if (w == 2 && term->cur_col < term->cols) {
        Cell* cont = cell_at(term, term->cur_row, term->cur_col);
        cont->utf8[0] = '\0';
        cont->width = 0;
        cont->is_continuation = true;
        term->cur_col++;
    }
}

void sim_terminal_put_string(SimTerminal* term, const char* utf8_str) {
    if (!term || !utf8_str) return;

    const char* p = utf8_str;
    while (*p) {
        uint32_t cp;
        int bytes = utf8_decode(p, &cp);
        if (bytes == 0) break;

        /* Extract the single codepoint as a NUL-terminated string */
        char single[MAX_UTF8_BYTES + 1];
        memcpy(single, p, (size_t)bytes);
        single[bytes] = '\0';

        sim_terminal_put_char(term, single);
        p += bytes;
    }
}

void sim_terminal_backspace(SimTerminal* term) {
    if (!term) return;

    /* Nothing to delete at position 0 on the current row */
    if (term->cur_col == 0) return;

    /* Look at the cell just before the cursor */
    int prev_col = term->cur_col - 1;
    Cell* prev = cell_at(term, term->cur_row, prev_col);

    if (prev->is_continuation) {
        /* The previous cell is the right half of a wide char.
         * The actual character is one more cell to the left. */
        if (prev_col > 0) {
            cell_clear(cell_at(term, term->cur_row, prev_col - 1));
            cell_clear(prev);
            term->cur_col -= 2;
        }
    } else {
        /* Single-width character (or the primary cell of a wide char — shouldn't
         * happen since cursor would be past the continuation cell, but handle it). */
        cell_clear(prev);
        term->cur_col -= 1;
    }
}

void sim_terminal_newline(SimTerminal* term) {
    if (!term) return;

    term->cur_col = 0;
    term->cur_row++;

    if (term->cur_row >= term->rows) {
        scroll_up(term);
        term->cur_row = term->rows - 1;
    }
}

void sim_terminal_move_cursor(SimTerminal* term, int direction) {
    if (!term) return;

    switch (direction) {
    case SIM_TERM_LEFT:
        if (term->cur_col > 0) {
            term->cur_col--;
            /* Skip over continuation cells */
            Cell* c = cell_at(term, term->cur_row, term->cur_col);
            if (c->is_continuation && term->cur_col > 0) {
                term->cur_col--;
            }
        }
        break;

    case SIM_TERM_RIGHT:
        if (term->cur_col < term->cols) {
            Cell* c = cell_at(term, term->cur_row, term->cur_col);
            int advance = (c->width == 2) ? 2 : 1;
            if (term->cur_col + advance <= term->cols) {
                term->cur_col += advance;
            }
        }
        break;

    case SIM_TERM_UP:
        if (term->cur_row > 0) {
            term->cur_row--;
        }
        break;

    case SIM_TERM_DOWN:
        if (term->cur_row < term->rows - 1) {
            term->cur_row++;
        }
        break;

    case SIM_TERM_HOME:
        term->cur_col = 0;
        break;

    default:
        break;
    }
}

void sim_terminal_set_preedit(SimTerminal* term, const char* utf8_preedit) {
    if (!term) return;

    if (!utf8_preedit || !utf8_preedit[0]) {
        term->preedit[0] = '\0';
        return;
    }

    size_t len = strlen(utf8_preedit);
    if (len >= MAX_PREEDIT) len = MAX_PREEDIT - 1;
    memcpy(term->preedit, utf8_preedit, len);
    term->preedit[len] = '\0';
}

void sim_terminal_clear_preedit(SimTerminal* term) {
    if (!term) return;
    term->preedit[0] = '\0';
}

void sim_terminal_dump(SimTerminal* term) {
    if (!term) return;

    /*
     * Build a display buffer that includes the preedit overlay.
     * We copy the grid into a temporary row-of-strings, then overlay preedit.
     */

    /* Top border */
    printf("\u250C"); /* ┌ */
    for (int c = 0; c < term->cols; c++) printf("\u2500"); /* ─ */
    printf("\u2510\n"); /* ┐ */

    /* Pre-compute preedit overlay info */
    int preedit_row = term->cur_row;
    int preedit_col = term->cur_col;
    bool has_preedit = (term->preedit[0] != '\0');

    /* Calculate preedit character widths for overlay */
    typedef struct {
        char utf8[MAX_UTF8_BYTES + 1];
        int  width;
    } PreeditChar;

    PreeditChar preedit_chars[64];
    int preedit_count = 0;
    int preedit_total_width = 0;

    if (has_preedit) {
        const char* p = term->preedit;
        while (*p && preedit_count < 64) {
            uint32_t cp;
            int bytes = utf8_decode(p, &cp);
            if (bytes == 0) break;
            memcpy(preedit_chars[preedit_count].utf8, p, (size_t)bytes);
            preedit_chars[preedit_count].utf8[bytes] = '\0';
            preedit_chars[preedit_count].width = codepoint_width(cp);
            preedit_total_width += preedit_chars[preedit_count].width;
            preedit_count++;
            p += bytes;
        }
    }

    /* Render each row */
    for (int r = 0; r < term->rows; r++) {
        printf("\u2502"); /* │ */

        int col = 0;
        while (col < term->cols) {
            /* Check if this position is within the preedit overlay */
            bool in_preedit = false;
            if (has_preedit && r == preedit_row) {
                if (col >= preedit_col && col < preedit_col + preedit_total_width) {
                    in_preedit = true;
                }
            }

            if (in_preedit) {
                /* Render preedit character at this position */
                int offset_in_preedit = col - preedit_col;
                int accum = 0;
                bool found = false;
                for (int pi = 0; pi < preedit_count; pi++) {
                    if (accum == offset_in_preedit) {
                        /* Render this preedit character with underline */
                        printf("\033[4m%s\033[0m", preedit_chars[pi].utf8);
                        col += preedit_chars[pi].width;
                        found = true;
                        break;
                    }
                    accum += preedit_chars[pi].width;
                }
                if (!found) {
                    /* Continuation column of a preedit wide char — skip */
                    col++;
                }
            } else {
                /* Render buffer content */
                Cell* c = cell_at(term, r, col);
                if (c->is_continuation) {
                    /* Skip — the wide char was already printed */
                    col++;
                } else if (c->utf8[0] != '\0') {
                    printf("%s", c->utf8);
                    col += (c->width > 0) ? c->width : 1;
                } else {
                    /* Empty cell */
                    printf(" ");
                    col++;
                }
            }
        }

        printf("\u2502\n"); /* │ */
    }

    /* Bottom border */
    printf("\u2514"); /* └ */
    for (int c = 0; c < term->cols; c++) printf("\u2500"); /* ─ */
    printf("\u2518\n"); /* ┘ */

    /* Status line */
    printf("Cursor: (%d, %d)", term->cur_row, term->cur_col);
    if (has_preedit) {
        printf("  Preedit: \033[4m%s\033[0m", term->preedit);
    }

    /* Show content summary: concatenate non-empty cells on all rows */
    printf("  Buffer: \"");
    for (int r = 0; r < term->rows; r++) {
        bool row_has_content = false;
        for (int c = 0; c < term->cols; c++) {
            Cell* cell = cell_at(term, r, c);
            if (cell->utf8[0] != '\0' && !cell->is_continuation) {
                row_has_content = true;
            }
        }
        if (!row_has_content) continue;

        if (r > 0) {
            /* Check if the previous row also had content */
            bool prev_has = false;
            for (int pr = 0; pr < r; pr++) {
                for (int c = 0; c < term->cols; c++) {
                    Cell* cell = cell_at(term, pr, c);
                    if (cell->utf8[0] != '\0' && !cell->is_continuation) {
                        prev_has = true;
                        break;
                    }
                }
                if (prev_has) break;
            }
            if (prev_has) printf("\\n");
        }

        for (int c = 0; c < term->cols; c++) {
            Cell* cell = cell_at(term, r, c);
            if (cell->utf8[0] != '\0' && !cell->is_continuation) {
                printf("%s", cell->utf8);
            }
        }
    }
    printf("\"\n");
}

void sim_terminal_reset(SimTerminal* term) {
    if (!term) return;

    for (int i = 0; i < term->rows * term->cols; i++) {
        cell_clear(&term->grid[i]);
    }
    term->cur_row = 0;
    term->cur_col = 0;
    term->preedit[0] = '\0';
}
