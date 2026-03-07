/**
 * test_sim_terminal.c — Smoke test for sim_terminal.
 *
 * Build:
 *   cc -o test_sim_terminal test_sim_terminal.c sim_terminal.c -std=c99
 */

#include <locale.h>
#include <stdio.h>
#include "sim_terminal.h"

int main(void) {
    setlocale(LC_ALL, "");

    /* Use a small terminal for visibility */
    SimTerminal* term = sim_terminal_create(40, 6);
    if (!term) {
        fprintf(stderr, "Failed to create terminal\n");
        return 1;
    }

    printf("=== Test 1: ASCII text ===\n");
    sim_terminal_put_string(term, "Hello, World!");
    sim_terminal_dump(term);
    printf("\n");

    printf("=== Test 2: Korean text (wide chars) ===\n");
    sim_terminal_reset(term);
    sim_terminal_put_string(term, "Hello ");
    /* Korean characters: 한글 */
    sim_terminal_put_char(term, "\xed\x95\x9c"); /* 한 */
    sim_terminal_put_char(term, "\xea\xb8\x80"); /* 글 */
    sim_terminal_dump(term);
    printf("\n");

    printf("=== Test 3: Preedit overlay ===\n");
    sim_terminal_reset(term);
    sim_terminal_put_string(term, "Input: ");
    sim_terminal_set_preedit(term, "\xea\xb0\x80"); /* 가 (preedit) */
    sim_terminal_dump(term);
    printf("\n");

    printf("=== Test 4: Backspace on Korean char ===\n");
    sim_terminal_reset(term);
    sim_terminal_put_char(term, "\xed\x95\x9c"); /* 한 */
    sim_terminal_put_char(term, "\xea\xb8\x80"); /* 글 */
    printf("Before backspace:\n");
    sim_terminal_dump(term);
    sim_terminal_backspace(term);
    printf("After backspace (글 removed):\n");
    sim_terminal_dump(term);
    printf("\n");

    printf("=== Test 5: Newline and scrolling ===\n");
    sim_terminal_reset(term);
    for (int i = 0; i < 8; i++) {
        char buf[32];
        snprintf(buf, sizeof(buf), "Line %d", i);
        sim_terminal_put_string(term, buf);
        sim_terminal_newline(term);
    }
    sim_terminal_dump(term);
    printf("\n");

    printf("=== Test 6: Cursor movement ===\n");
    sim_terminal_reset(term);
    sim_terminal_put_string(term, "ABCD");
    sim_terminal_move_cursor(term, SIM_TERM_LEFT);
    sim_terminal_move_cursor(term, SIM_TERM_LEFT);
    printf("After typing ABCD and moving left twice (cursor at col 2):\n");
    sim_terminal_dump(term);
    printf("\n");

    sim_terminal_destroy(term);
    printf("All sim_terminal tests passed.\n");
    return 0;
}
