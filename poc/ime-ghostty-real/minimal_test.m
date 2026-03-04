// minimal_test.m — Minimal headless ghostty C API proof-of-concept
//
// Creates a ghostty app + surface with an off-screen NSView,
// feeds text via ghostty_surface_key(), and reads terminal content
// via ghostty_surface_read_text().
//
// Build:
//   cc -o minimal_test minimal_test.m \
//     -I"$GHOSTTY_HEADER_DIR" -L"$GHOSTTY_LIB_DIR" -lghostty \
//     -framework Foundation -framework AppKit -framework CoreText \
//     -framework CoreGraphics -framework Metal -framework QuartzCore \
//     -framework CoreFoundation -framework Security -framework IOKit \
//     -framework GameController \
//     -fobjc-arc

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include "ghostty.h"

// ---------------------------------------------------------------------------
// Stub callbacks for ghostty_runtime_config_s
// ---------------------------------------------------------------------------

static void stub_wakeup(void *ud) {
    // no-op: in a real app this would wake the run loop
}

static bool stub_action(ghostty_app_t app, ghostty_target_s target,
                         ghostty_action_s action) {
    // no-op: we don't handle any actions
    return false;
}

static void stub_read_clipboard(void *ud, ghostty_clipboard_e loc,
                                 void *state) {
    // no-op
}

static void stub_confirm_read_clipboard(void *ud, const char *str,
                                          void *state,
                                          ghostty_clipboard_request_e req) {
    // no-op
}

static void stub_write_clipboard(void *ud, const char *str,
                                  ghostty_clipboard_e loc, bool confirm) {
    // no-op
}

static void stub_close_surface(void *ud, bool process_alive) {
    // no-op
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

int main(int argc, char *argv[]) {
    @autoreleasepool {
        printf("=== ghostty C API headless PoC ===\n\n");

        // --- 0. Initialize NSApplication ---
        // Metal renderer requires a valid NSApplication context.
        [NSApplication sharedApplication];

        // --- 1. Initialize ghostty global state ---
        printf("[1] Calling ghostty_init...\n");
        int init_result = ghostty_init(0, NULL);
        if (init_result != GHOSTTY_SUCCESS) {
            fprintf(stderr, "ghostty_init failed: %d\n", init_result);
            return 1;
        }
        printf("    ghostty_init succeeded\n");

        // Print build info.
        ghostty_info_s info = ghostty_info();
        printf("    ghostty version: %.*s (build mode: %d)\n",
               (int)info.version_len, info.version, info.build_mode);

        // --- 2. Create config ---
        printf("\n[2] Creating config...\n");
        ghostty_config_t config = ghostty_config_new();
        if (!config) {
            fprintf(stderr, "ghostty_config_new failed\n");
            return 1;
        }
        // Create a temp config directory with window-vsync=false.
        // CVDisplayLinkCreateWithActiveCGDisplays fails when there's no
        // window server connection (command-line process context).
        NSString *tmpBase = [NSTemporaryDirectory()
            stringByAppendingPathComponent:@"ghostty_headless"];
        NSString *xdgConfigDir = [tmpBase stringByAppendingPathComponent:@"config"];
        NSString *ghosttyConfigDir = [xdgConfigDir stringByAppendingPathComponent:@"ghostty"];
        [[NSFileManager defaultManager]
            createDirectoryAtPath:ghosttyConfigDir
      withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *configFile = [ghosttyConfigDir stringByAppendingPathComponent:@"config"];
        [@"window-vsync = false\n" writeToFile:configFile atomically:YES
                               encoding:NSUTF8StringEncoding error:nil];

        // Also create the AppSupport config path under our tmp HOME
        // so the real user config doesn't get loaded.
        NSString *tmpHome = [tmpBase stringByAppendingPathComponent:@"home"];
        [[NSFileManager defaultManager]
            createDirectoryAtPath:tmpHome
      withIntermediateDirectories:YES attributes:nil error:nil];

        // Redirect HOME and XDG_CONFIG_HOME to isolate config loading.
        setenv("HOME", tmpHome.UTF8String, 1);
        setenv("XDG_CONFIG_HOME", xdgConfigDir.UTF8String, 1);

        ghostty_config_load_default_files(config);
        ghostty_config_finalize(config);
        printf("    config created and finalized\n");

        // Check for diagnostics.
        uint32_t diag_count = ghostty_config_diagnostics_count(config);
        if (diag_count > 0) {
            printf("    config diagnostics (%u):\n", diag_count);
            for (uint32_t i = 0; i < diag_count; i++) {
                ghostty_diagnostic_s diag = ghostty_config_get_diagnostic(config, i);
                printf("      [%u] %s\n", i, diag.message);
            }
        }

        // --- 3. Create app ---
        printf("\n[3] Creating app...\n");
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
            return 1;
        }
        printf("    app created successfully\n");

        // --- 4. Create surface with an off-screen NSWindow + NSView ---
        printf("\n[4] Creating surface...\n");

        // Create a backing NSWindow with an NSView. The Metal renderer
        // needs the view to have a proper layer hierarchy.
        NSWindow *window = [[NSWindow alloc]
            initWithContentRect:NSMakeRect(0, 0, 800, 600)
                      styleMask:NSWindowStyleMaskTitled
                        backing:NSBackingStoreBuffered
                          defer:NO];
        NSView *view = window.contentView;
        // Do NOT set wantsLayer — ghostty does this itself in Metal.zig
        // (it sets view.layer = metalLayer, then view.wantsLayer = true
        // for "layer-hosting" mode).

        ghostty_surface_config_s surface_cfg = ghostty_surface_config_new();
        surface_cfg.platform_tag = GHOSTTY_PLATFORM_MACOS;
        surface_cfg.platform.macos.nsview = (__bridge void *)view;
        surface_cfg.userdata = NULL;
        surface_cfg.scale_factor = 1.0;
        surface_cfg.font_size = 0;  // use default
        surface_cfg.working_directory = NULL;
        surface_cfg.command = "/bin/cat";  // deterministic: echoes input back
        surface_cfg.wait_after_command = false;
        surface_cfg.stream_write_fn = NULL;
        surface_cfg.stream_resize_fn = NULL;
        surface_cfg.stream_userdata = NULL;

        ghostty_surface_t surface = ghostty_surface_new(app, &surface_cfg);
        if (!surface) {
            fprintf(stderr, "ghostty_surface_new failed\n");
            fprintf(stderr, "This likely means the Metal renderer cannot initialize.\n");
            fprintf(stderr, "The ghostty C API requires a real GPU context (Metal).\n");
            // NOTE: Don't call ghostty_app_free here — it panics on
            // unreachable code when no surfaces were ever successfully
            // created (likely an assertion in the app deinit).
            ghostty_config_free(config);
            return 1;
        }
        printf("    surface created successfully\n");

        // Set initial size so the terminal has dimensions.
        ghostty_surface_set_size(surface, 800, 600);
        ghostty_surface_set_focus(surface, true);

        // --- 5. Feed text to the terminal ---
        printf("\n[5] Feeding text 'hello' via ghostty_surface_key...\n");

        // Tick a few times to let the child process start.
        for (int i = 0; i < 5; i++) {
            ghostty_app_tick(app);
            usleep(50000); // 50ms
        }

        // Send each character individually.
        const char chars[] = "hello";
        ghostty_input_key_e keys[] = {
            GHOSTTY_KEY_H, GHOSTTY_KEY_E, GHOSTTY_KEY_L,
            GHOSTTY_KEY_L, GHOSTTY_KEY_O
        };
        for (int i = 0; i < 5; i++) {
            char buf[2] = { chars[i], 0 };
            ghostty_input_key_s ev = {
                .action = GHOSTTY_ACTION_PRESS,
                .mods = GHOSTTY_MODS_NONE,
                .consumed_mods = GHOSTTY_MODS_NONE,
                .keycode = keys[i],
                .text = buf,
                .unshifted_codepoint = (uint32_t)chars[i],
                .composing = false,
            };
            bool handled = ghostty_surface_key(surface, ev);
            printf("    key '%c': handled=%d\n", chars[i], handled);

            // Send release too.
            ev.action = GHOSTTY_ACTION_RELEASE;
            ev.text = NULL;
            ghostty_surface_key(surface, ev);
        }

        // Tick to process I/O (child process reads input, echoes back).
        for (int i = 0; i < 10; i++) {
            ghostty_app_tick(app);
            usleep(50000); // 50ms
        }

        // --- 6. Read terminal content ---
        printf("\n[6] Reading terminal content...\n");

        // Check surface size.
        ghostty_surface_size_s sz = ghostty_surface_size(surface);
        printf("    surface size: %u cols x %u rows (%u x %u px, cell %u x %u)\n",
               sz.columns, sz.rows, sz.width_px, sz.height_px,
               sz.cell_width_px, sz.cell_height_px);

        // Try to read the first line.
        ghostty_selection_s sel = {
            .top_left = {
                .tag = GHOSTTY_POINT_VIEWPORT,
                .coord = GHOSTTY_POINT_COORD_TOP_LEFT,
                .x = 0,
                .y = 0,
            },
            .bottom_right = {
                .tag = GHOSTTY_POINT_VIEWPORT,
                .coord = GHOSTTY_POINT_COORD_BOTTOM_RIGHT,
                .x = (sz.columns > 0 ? sz.columns - 1 : 79),
                .y = 0,
            },
            .rectangle = false,
        };

        ghostty_text_s text_result = {0};
        bool read_ok = ghostty_surface_read_text(surface, sel, &text_result);
        if (read_ok && text_result.text && text_result.text_len > 0) {
            printf("    terminal line 0: \"%.*s\"\n",
                   (int)text_result.text_len, text_result.text);
            ghostty_surface_free_text(surface, &text_result);
        } else {
            printf("    read_text returned: ok=%d text=%p len=%zu\n",
                   read_ok, (void *)text_result.text,
                   text_result.text_len);
        }

        // Also try reading the full viewport (first 5 lines).
        printf("\n    reading full viewport (lines 0-4):\n");
        for (uint32_t line = 0; line < 5; line++) {
            ghostty_selection_s line_sel = {
                .top_left = {
                    .tag = GHOSTTY_POINT_VIEWPORT,
                    .coord = GHOSTTY_POINT_COORD_TOP_LEFT,
                    .x = 0,
                    .y = line,
                },
                .bottom_right = {
                    .tag = GHOSTTY_POINT_VIEWPORT,
                    .coord = GHOSTTY_POINT_COORD_BOTTOM_RIGHT,
                    .x = (sz.columns > 0 ? sz.columns - 1 : 79),
                    .y = line,
                },
                .rectangle = false,
            };

            ghostty_text_s line_text = {0};
            bool line_ok = ghostty_surface_read_text(surface, line_sel, &line_text);
            if (line_ok && line_text.text && line_text.text_len > 0) {
                printf("    line %u: \"%.*s\"\n",
                       line, (int)line_text.text_len, line_text.text);
                ghostty_surface_free_text(surface, &line_text);
            }
        }

        // --- 7. Cleanup ---
        printf("\n[7] Cleaning up...\n");
        ghostty_surface_free(surface);
        ghostty_app_free(app);
        ghostty_config_free(config);
        printf("    done.\n\n");
        printf("=== SUCCESS: ghostty C API works headlessly! ===\n");
    }

    return 0;
}
