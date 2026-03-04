/**
 * sim_terminal.h — Simulated terminal buffer for IME key-handling PoC.
 *
 * 80×24 grid with wide character (CJK) support, cursor tracking,
 * preedit overlay, and visual screen dump.
 */

#ifndef SIM_TERMINAL_H
#define SIM_TERMINAL_H

#ifdef __cplusplus
extern "C" {
#endif

/* Cursor movement directions */
#define SIM_TERM_LEFT  0
#define SIM_TERM_RIGHT 1
#define SIM_TERM_UP    2
#define SIM_TERM_DOWN  3
#define SIM_TERM_HOME  4

typedef struct SimTerminal SimTerminal;

/**
 * Create a new simulated terminal with the given dimensions.
 * Returns NULL on allocation failure.
 */
SimTerminal* sim_terminal_create(int cols, int rows);

/**
 * Destroy a simulated terminal and free all resources.
 */
void sim_terminal_destroy(SimTerminal* term);

/**
 * Insert a single UTF-8 character at the cursor position.
 * Wide characters (Korean) consume 2 cells.
 */
void sim_terminal_put_char(SimTerminal* term, const char* utf8_char);

/**
 * Insert a UTF-8 string at the cursor position (convenience wrapper).
 * Iterates over each UTF-8 codepoint and calls put_char.
 */
void sim_terminal_put_string(SimTerminal* term, const char* utf8_str);

/**
 * Delete the character before the cursor.
 * For wide characters, both cells are cleared.
 */
void sim_terminal_backspace(SimTerminal* term);

/**
 * Move cursor to the beginning of the next line.
 * Scrolls the buffer if the cursor is on the last row.
 */
void sim_terminal_newline(SimTerminal* term);

/**
 * Move the cursor in the given direction.
 * direction: SIM_TERM_LEFT, SIM_TERM_RIGHT, SIM_TERM_UP, SIM_TERM_DOWN, SIM_TERM_HOME
 */
void sim_terminal_move_cursor(SimTerminal* term, int direction);

/**
 * Set the preedit overlay text (UTF-8).
 * Preedit is rendered at the cursor position but NOT committed to the buffer.
 * Pass NULL or "" to clear preedit.
 */
void sim_terminal_set_preedit(SimTerminal* term, const char* utf8_preedit);

/**
 * Clear the preedit overlay.
 */
void sim_terminal_clear_preedit(SimTerminal* term);

/**
 * Print a visual representation of the terminal to stdout.
 * Shows box-drawn border, buffer content, preedit overlay, and cursor position.
 */
void sim_terminal_dump(SimTerminal* term);

/**
 * Clear the entire buffer, reset cursor to (0,0), clear preedit.
 */
void sim_terminal_reset(SimTerminal* term);

#ifdef __cplusplus
}
#endif

#endif /* SIM_TERMINAL_H */
