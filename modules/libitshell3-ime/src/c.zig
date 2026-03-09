//! @cImport wrapper for libhangul.
//! Centralizes all C interop in one place so the rest of the codebase
//! uses Zig-typed imports.

const hangul = @cImport({
    @cInclude("hangul/hangul.h");
});

// Re-export all libhangul types and functions used by the engine.
pub const ucschar = hangul.ucschar;
pub const HangulInputContext = hangul.HangulInputContext;

pub const hangul_ic_new = hangul.hangul_ic_new;
pub const hangul_ic_delete = hangul.hangul_ic_delete;
pub const hangul_ic_process = hangul.hangul_ic_process;
pub const hangul_ic_reset = hangul.hangul_ic_reset;
pub const hangul_ic_backspace = hangul.hangul_ic_backspace;
pub const hangul_ic_is_empty = hangul.hangul_ic_is_empty;
pub const hangul_ic_get_preedit_string = hangul.hangul_ic_get_preedit_string;
pub const hangul_ic_get_commit_string = hangul.hangul_ic_get_commit_string;
pub const hangul_ic_flush = hangul.hangul_ic_flush;
pub const hangul_ic_select_keyboard = hangul.hangul_ic_select_keyboard;
