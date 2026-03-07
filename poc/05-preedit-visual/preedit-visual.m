// preedit-visual.m — Visual preedit rendering PoC
//
// Opens a VISIBLE ghostty surface window and calls ghostty_surface_preedit()
// directly (without OS IME / NSTextInputClient) to observe what ghostty's
// Metal renderer actually draws for preedit text.
//
// Questions to answer:
//   1. What decoration does ghostty apply? (underline? reverse? background?)
//   2. Is the terminal cursor visible during preedit?
//   3. How does a 2-cell Korean character render in preedit?
//   4. What happens when preedit is cleared?
//
// Usage:
//   ./preedit-visual
//   (Watch the window — each scenario holds for a few seconds)
//   Press Ctrl+C to exit early.
//
// Build: see build.sh

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include "ghostty.h"
#include "hangul/hangul.h"

// ===================================================================
// Ghostty stub callbacks
// ===================================================================

static void stub_wakeup(void *ud) {}
static bool stub_action(ghostty_app_t app, ghostty_target_s target,
                         ghostty_action_s action) { return false; }
static void stub_read_clipboard(void *ud, ghostty_clipboard_e loc,
                                 void *state) {}
static void stub_confirm_read_clipboard(void *ud, const char *str,
                                          void *state,
                                          ghostty_clipboard_request_e req) {}
static void stub_write_clipboard(void *ud, const char *str,
                                  ghostty_clipboard_e loc, bool confirm) {}
static void stub_close_surface(void *ud, bool process_alive) {}

// ===================================================================
// Ghostty initialization
// ===================================================================

typedef struct {
    ghostty_app_t app;
    ghostty_surface_t surface;
    ghostty_config_t config;
    NSWindow *window;
} GhosttyCtx;

static void tick(GhosttyCtx *ctx, int count) {
    for (int i = 0; i < count; i++) {
        ghostty_app_tick(ctx->app);
        [[NSRunLoop currentRunLoop] runUntilDate:
            [NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
}

static GhosttyCtx *ghostty_init_visible(void) {
    // NSApplication is mandatory for Metal renderer
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

    // Initialize ghostty
    int rc = ghostty_init(0, NULL);
    if (rc != GHOSTTY_SUCCESS) {
        fprintf(stderr, "ghostty_init failed: %d\n", rc);
        return NULL;
    }

    // Config with isolated HOME to avoid loading user's real config
    ghostty_config_t config = ghostty_config_new();
    if (!config) {
        fprintf(stderr, "ghostty_config_new failed\n");
        return NULL;
    }

    NSString *tmpBase = [NSTemporaryDirectory()
        stringByAppendingPathComponent:@"preedit_visual"];
    NSString *xdgConfigDir = [tmpBase stringByAppendingPathComponent:@"config"];
    NSString *ghosttyConfigDir = [xdgConfigDir
        stringByAppendingPathComponent:@"ghostty"];
    [[NSFileManager defaultManager]
        createDirectoryAtPath:ghosttyConfigDir
        withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *configFile = [ghosttyConfigDir
        stringByAppendingPathComponent:@"config"];
    [@"window-vsync = false\nfont-size = 18\n"
        writeToFile:configFile atomically:YES
        encoding:NSUTF8StringEncoding error:nil];

    NSString *tmpHome = [tmpBase stringByAppendingPathComponent:@"home"];
    [[NSFileManager defaultManager]
        createDirectoryAtPath:tmpHome
        withIntermediateDirectories:YES attributes:nil error:nil];

    setenv("HOME", tmpHome.UTF8String, 1);
    setenv("XDG_CONFIG_HOME", xdgConfigDir.UTF8String, 1);

    ghostty_config_load_default_files(config);
    ghostty_config_finalize(config);

    // Create app
    ghostty_runtime_config_s runtime_cfg = {
        .userdata = NULL,
        .supports_selection_clipboard = false,
        .wakeup_cb = stub_wakeup,
        .action_cb = stub_action,
        .read_clipboard_cb = stub_read_clipboard,
        .confirm_read_clipboard_cb = stub_confirm_read_clipboard,
        .write_clipboard_cb = stub_write_clipboard,
        .close_surface_cb = stub_close_surface,
    };

    ghostty_app_t app = ghostty_app_new(&runtime_cfg, config);
    if (!app) {
        fprintf(stderr, "ghostty_app_new failed\n");
        ghostty_config_free(config);
        return NULL;
    }

    // Create VISIBLE window
    NSRect frame = NSMakeRect(200, 200, 800, 400);
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:frame
                  styleMask:(NSWindowStyleMaskTitled |
                             NSWindowStyleMaskClosable |
                             NSWindowStyleMaskResizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [window setTitle:@"Preedit Visual PoC"];
    NSView *view = window.contentView;

    // Create surface
    ghostty_surface_config_s surface_cfg = ghostty_surface_config_new();
    surface_cfg.platform_tag = GHOSTTY_PLATFORM_MACOS;
    surface_cfg.platform.macos.nsview = (__bridge void *)view;
    surface_cfg.userdata = NULL;
    surface_cfg.scale_factor = 2.0;  // Retina
    surface_cfg.font_size = 0;
    surface_cfg.working_directory = NULL;
    surface_cfg.command = "/bin/cat";
    surface_cfg.wait_after_command = false;
    surface_cfg.stream_write_fn = NULL;
    surface_cfg.stream_resize_fn = NULL;
    surface_cfg.stream_userdata = NULL;

    ghostty_surface_t surface = ghostty_surface_new(app, &surface_cfg);
    if (!surface) {
        fprintf(stderr, "ghostty_surface_new failed\n");
        ghostty_app_free(app);
        ghostty_config_free(config);
        return NULL;
    }

    NSRect contentFrame = [view frame];
    ghostty_surface_set_size(surface,
        (uint32_t)contentFrame.size.width,
        (uint32_t)contentFrame.size.height);
    ghostty_surface_set_focus(surface, true);

    // Show window
    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    GhosttyCtx *ctx = calloc(1, sizeof(GhosttyCtx));
    ctx->app = app;
    ctx->surface = surface;
    ctx->config = config;
    ctx->window = window;

    // Let child process start and render initial frame
    tick(ctx, 10);

    return ctx;
}

static void ghostty_cleanup(GhosttyCtx *ctx) {
    ghostty_surface_free(ctx->surface);
    ghostty_app_free(ctx->app);
    ghostty_config_free(ctx->config);
    free(ctx);
}

// ===================================================================
// Key input helpers
// ===================================================================

static void send_key_text(GhosttyCtx *ctx, const char *text) {
    ghostty_input_key_s ev = {
        .action = GHOSTTY_ACTION_PRESS,
        .mods = GHOSTTY_MODS_NONE,
        .consumed_mods = GHOSTTY_MODS_NONE,
        .keycode = GHOSTTY_KEY_UNIDENTIFIED,
        .text = text,
        .unshifted_codepoint = 0,
        .composing = false,
    };
    ghostty_surface_key(ctx->surface, ev);

    ev.action = GHOSTTY_ACTION_RELEASE;
    ev.text = NULL;
    ghostty_surface_key(ctx->surface, ev);
}

static void send_enter(GhosttyCtx *ctx) {
    ghostty_input_key_s ev = {
        .action = GHOSTTY_ACTION_PRESS,
        .mods = GHOSTTY_MODS_NONE,
        .consumed_mods = GHOSTTY_MODS_NONE,
        .keycode = GHOSTTY_KEY_ENTER,
        .text = NULL,
        .unshifted_codepoint = 0,
        .composing = false,
    };
    ghostty_surface_key(ctx->surface, ev);

    ev.action = GHOSTTY_ACTION_RELEASE;
    ghostty_surface_key(ctx->surface, ev);
}

// ===================================================================
// Preedit helpers
// ===================================================================

static void set_preedit(GhosttyCtx *ctx, const char *utf8) {
    ghostty_surface_preedit(ctx->surface, utf8, (uintptr_t)strlen(utf8));
}

static void clear_preedit(GhosttyCtx *ctx) {
    ghostty_surface_preedit(ctx->surface, NULL, 0);
}

// ===================================================================
// Scenario runner
// ===================================================================

static void pause_for_observation(GhosttyCtx *ctx, double seconds) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while ([end timeIntervalSinceNow] > 0) {
        ghostty_app_tick(ctx->app);
        [[NSRunLoop currentRunLoop] runUntilDate:
            [NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
}

static void announce(GhosttyCtx *ctx, const char *title) {
    printf("\n========================================\n");
    printf("  %s\n", title);
    printf("========================================\n");
    [ctx->window setTitle:[NSString stringWithUTF8String:title]];
}

// ===================================================================
// Test scenarios
// ===================================================================

static void scenario_1_single_jamo(GhosttyCtx *ctx) {
    announce(ctx, "1. Single jamo preedit: ㄱ");
    printf("  Calling ghostty_surface_preedit(\"ㄱ\")\n");
    printf("  Observe: What decoration? Underline? Reverse? Background color?\n");

    set_preedit(ctx, "ㄱ");
    pause_for_observation(ctx, 4.0);

    printf("  Clearing preedit\n");
    clear_preedit(ctx);
    tick(ctx, 5);
}

static void scenario_2_full_syllable(GhosttyCtx *ctx) {
    announce(ctx, "2. Full syllable preedit: 한");
    printf("  Calling ghostty_surface_preedit(\"한\")\n");
    printf("  Observe: 2-cell wide character rendering, cursor behavior\n");

    set_preedit(ctx, "한");
    pause_for_observation(ctx, 4.0);

    clear_preedit(ctx);
    tick(ctx, 5);
}

static void scenario_3_composition_sequence(GhosttyCtx *ctx) {
    announce(ctx, "3. Composition sequence: ㅎ → 하 → 한");
    printf("  Observe: Preedit updates in-place as composition progresses\n");

    printf("  Step 1: preedit = \"ㅎ\"\n");
    set_preedit(ctx, "ㅎ");
    pause_for_observation(ctx, 2.0);

    printf("  Step 2: preedit = \"하\"\n");
    set_preedit(ctx, "하");
    pause_for_observation(ctx, 2.0);

    printf("  Step 3: preedit = \"한\"\n");
    set_preedit(ctx, "한");
    pause_for_observation(ctx, 2.0);

    printf("  Committing \"한\" and clearing preedit\n");
    clear_preedit(ctx);
    send_key_text(ctx, "한");
    tick(ctx, 5);
    pause_for_observation(ctx, 2.0);
}

static void scenario_4_after_committed_text(GhosttyCtx *ctx) {
    announce(ctx, "4. Preedit after committed text: 한ㄱ");
    printf("  First commit \"한\", then show preedit \"ㄱ\"\n");
    printf("  Observe: Preedit appears after committed char, correct position\n");

    // "한" was already committed in scenario 3
    // Now show preedit for next character
    set_preedit(ctx, "ㄱ");
    pause_for_observation(ctx, 3.0);

    printf("  Update preedit: \"글\"\n");
    set_preedit(ctx, "글");
    pause_for_observation(ctx, 3.0);

    printf("  Committing \"글\" and clearing preedit\n");
    clear_preedit(ctx);
    send_key_text(ctx, "글");
    tick(ctx, 5);
    pause_for_observation(ctx, 2.0);
}

static void scenario_5_ascii_then_preedit(GhosttyCtx *ctx) {
    announce(ctx, "5. ASCII text then preedit: hello + ㅎ");
    printf("  Type \"hello\" in direct mode, then show Korean preedit\n");
    printf("  Observe: Preedit position after ASCII chars\n");

    // Move to new line first
    send_enter(ctx);
    tick(ctx, 3);

    // Type ASCII
    const char *chars = "hello";
    for (int i = 0; chars[i]; i++) {
        char buf[2] = { chars[i], 0 };
        send_key_text(ctx, buf);
    }
    tick(ctx, 5);
    pause_for_observation(ctx, 1.0);

    printf("  Now showing preedit \"ㅎ\"\n");
    set_preedit(ctx, "ㅎ");
    pause_for_observation(ctx, 3.0);

    clear_preedit(ctx);
    tick(ctx, 3);
}

static void scenario_6_preedit_clear_restore_cursor(GhosttyCtx *ctx) {
    announce(ctx, "6. Preedit clear — cursor restoration");
    printf("  Show preedit, clear it, observe if cursor reappears normally\n");

    send_enter(ctx);
    tick(ctx, 3);

    printf("  Before preedit — observe cursor\n");
    pause_for_observation(ctx, 2.0);

    printf("  Setting preedit \"가\"\n");
    set_preedit(ctx, "가");
    pause_for_observation(ctx, 3.0);

    printf("  Clearing preedit — cursor should reappear\n");
    clear_preedit(ctx);
    tick(ctx, 3);
    pause_for_observation(ctx, 3.0);
}

static void scenario_7_libhangul_live(GhosttyCtx *ctx) {
    announce(ctx, "7. Live libhangul composition: r,k,s,k (간가)");
    printf("  Using real libhangul to produce preedit strings\n");
    printf("  Observe: Real composition with commit + new preedit\n");

    HangulInputContext *ic = hangul_ic_new("2");

    // 'r' = ㄱ
    printf("  Key 'r' → ");
    hangul_ic_process(ic, 'r');
    const ucschar *preedit = hangul_ic_get_preedit_string(ic);
    const ucschar *commit = hangul_ic_get_commit_string(ic);

    // Convert UCS-4 preedit to UTF-8
    char utf8_buf[64];
    int utf8_len = 0;
    for (int i = 0; preedit[i]; i++) {
        if (preedit[i] < 0x80) {
            utf8_buf[utf8_len++] = (char)preedit[i];
        } else if (preedit[i] < 0x800) {
            utf8_buf[utf8_len++] = 0xC0 | (preedit[i] >> 6);
            utf8_buf[utf8_len++] = 0x80 | (preedit[i] & 0x3F);
        } else if (preedit[i] < 0x10000) {
            utf8_buf[utf8_len++] = 0xE0 | (preedit[i] >> 12);
            utf8_buf[utf8_len++] = 0x80 | ((preedit[i] >> 6) & 0x3F);
            utf8_buf[utf8_len++] = 0x80 | (preedit[i] & 0x3F);
        }
    }
    utf8_buf[utf8_len] = 0;
    printf("preedit=\"%s\"\n", utf8_buf);
    set_preedit(ctx, utf8_buf);
    pause_for_observation(ctx, 1.5);

    // 'k' = ㅏ → 가
    printf("  Key 'k' → ");
    hangul_ic_process(ic, 'k');
    preedit = hangul_ic_get_preedit_string(ic);
    commit = hangul_ic_get_commit_string(ic);
    utf8_len = 0;
    for (int i = 0; preedit[i]; i++) {
        if (preedit[i] < 0x80) {
            utf8_buf[utf8_len++] = (char)preedit[i];
        } else if (preedit[i] < 0x800) {
            utf8_buf[utf8_len++] = 0xC0 | (preedit[i] >> 6);
            utf8_buf[utf8_len++] = 0x80 | (preedit[i] & 0x3F);
        } else if (preedit[i] < 0x10000) {
            utf8_buf[utf8_len++] = 0xE0 | (preedit[i] >> 12);
            utf8_buf[utf8_len++] = 0x80 | ((preedit[i] >> 6) & 0x3F);
            utf8_buf[utf8_len++] = 0x80 | (preedit[i] & 0x3F);
        }
    }
    utf8_buf[utf8_len] = 0;
    printf("preedit=\"%s\"\n", utf8_buf);
    set_preedit(ctx, utf8_buf);
    pause_for_observation(ctx, 1.5);

    // 's' = ㄴ → 간
    printf("  Key 's' → ");
    hangul_ic_process(ic, 's');
    preedit = hangul_ic_get_preedit_string(ic);
    commit = hangul_ic_get_commit_string(ic);
    utf8_len = 0;
    for (int i = 0; preedit[i]; i++) {
        if (preedit[i] < 0x80) {
            utf8_buf[utf8_len++] = (char)preedit[i];
        } else if (preedit[i] < 0x800) {
            utf8_buf[utf8_len++] = 0xC0 | (preedit[i] >> 6);
            utf8_buf[utf8_len++] = 0x80 | (preedit[i] & 0x3F);
        } else if (preedit[i] < 0x10000) {
            utf8_buf[utf8_len++] = 0xE0 | (preedit[i] >> 12);
            utf8_buf[utf8_len++] = 0x80 | ((preedit[i] >> 6) & 0x3F);
            utf8_buf[utf8_len++] = 0x80 | (preedit[i] & 0x3F);
        }
    }
    utf8_buf[utf8_len] = 0;
    printf("preedit=\"%s\"\n", utf8_buf);
    set_preedit(ctx, utf8_buf);
    pause_for_observation(ctx, 1.5);

    // 'k' = ㅏ → commit 간, preedit 가
    printf("  Key 'k' → ");
    hangul_ic_process(ic, 'k');
    preedit = hangul_ic_get_preedit_string(ic);
    commit = hangul_ic_get_commit_string(ic);

    // Commit text
    if (commit && commit[0]) {
        char commit_utf8[64];
        int cl = 0;
        for (int i = 0; commit[i]; i++) {
            if (commit[i] < 0x80) {
                commit_utf8[cl++] = (char)commit[i];
            } else if (commit[i] < 0x800) {
                commit_utf8[cl++] = 0xC0 | (commit[i] >> 6);
                commit_utf8[cl++] = 0x80 | (commit[i] & 0x3F);
            } else if (commit[i] < 0x10000) {
                commit_utf8[cl++] = 0xE0 | (commit[i] >> 12);
                commit_utf8[cl++] = 0x80 | ((commit[i] >> 6) & 0x3F);
                commit_utf8[cl++] = 0x80 | (commit[i] & 0x3F);
            }
        }
        commit_utf8[cl] = 0;
        printf("commit=\"%s\", ", commit_utf8);

        clear_preedit(ctx);
        send_key_text(ctx, commit_utf8);
        tick(ctx, 3);
    }

    // New preedit
    utf8_len = 0;
    for (int i = 0; preedit[i]; i++) {
        if (preedit[i] < 0x80) {
            utf8_buf[utf8_len++] = (char)preedit[i];
        } else if (preedit[i] < 0x800) {
            utf8_buf[utf8_len++] = 0xC0 | (preedit[i] >> 6);
            utf8_buf[utf8_len++] = 0x80 | (preedit[i] & 0x3F);
        } else if (preedit[i] < 0x10000) {
            utf8_buf[utf8_len++] = 0xE0 | (preedit[i] >> 12);
            utf8_buf[utf8_len++] = 0x80 | ((preedit[i] >> 6) & 0x3F);
            utf8_buf[utf8_len++] = 0x80 | (preedit[i] & 0x3F);
        }
    }
    utf8_buf[utf8_len] = 0;
    printf("preedit=\"%s\"\n", utf8_buf);
    set_preedit(ctx, utf8_buf);
    pause_for_observation(ctx, 2.0);

    // Flush
    hangul_ic_flush(ic);
    printf("  Flushing and clearing preedit\n");
    clear_preedit(ctx);
    send_key_text(ctx, utf8_buf);  // commit the remaining preedit
    tick(ctx, 5);
    pause_for_observation(ctx, 2.0);

    hangul_ic_delete(ic);
}

static void scenario_8_vowel_only(GhosttyCtx *ctx) {
    announce(ctx, "8. Vowel-only preedit: ㅏ");
    printf("  Preedit with standalone vowel (1-cell jamo)\n");
    printf("  Observe: Width — is it 1 cell or 2?\n");

    send_enter(ctx);
    tick(ctx, 3);

    set_preedit(ctx, "ㅏ");
    pause_for_observation(ctx, 3.0);

    clear_preedit(ctx);
    tick(ctx, 3);
}

static void scenario_9_mixed_width(GhosttyCtx *ctx) {
    announce(ctx, "9. Committed 'ab' then preedit '가' — alignment check");
    printf("  Observe: Does preedit start at correct position after 1-cell chars?\n");

    send_enter(ctx);
    tick(ctx, 3);

    send_key_text(ctx, "a");
    send_key_text(ctx, "b");
    tick(ctx, 5);
    pause_for_observation(ctx, 1.0);

    set_preedit(ctx, "가");
    pause_for_observation(ctx, 3.0);

    clear_preedit(ctx);
    tick(ctx, 3);
}

// ===================================================================
// Main
// ===================================================================

int main(int argc, char *argv[]) {
    @autoreleasepool {
        printf("=== Preedit Visual PoC ===\n");
        printf("This PoC opens a visible ghostty window and calls\n");
        printf("ghostty_surface_preedit() directly to observe rendering.\n");
        printf("Watch the window. Each scenario holds for a few seconds.\n\n");

        GhosttyCtx *ctx = ghostty_init_visible();
        if (!ctx) {
            fprintf(stderr, "Failed to initialize ghostty\n");
            return 1;
        }

        printf("Ghostty initialized. Window should be visible.\n");
        pause_for_observation(ctx, 2.0);

        scenario_1_single_jamo(ctx);
        scenario_2_full_syllable(ctx);
        scenario_3_composition_sequence(ctx);
        scenario_4_after_committed_text(ctx);
        scenario_5_ascii_then_preedit(ctx);
        scenario_6_preedit_clear_restore_cursor(ctx);
        scenario_7_libhangul_live(ctx);
        scenario_8_vowel_only(ctx);
        scenario_9_mixed_width(ctx);

        printf("\n========================================\n");
        printf("  All scenarios complete.\n");
        printf("  Window stays open for 10 seconds.\n");
        printf("========================================\n");
        [ctx->window setTitle:@"All scenarios complete"];
        pause_for_observation(ctx, 10.0);

        ghostty_cleanup(ctx);
        printf("\nDone.\n");
    }
    return 0;
}
