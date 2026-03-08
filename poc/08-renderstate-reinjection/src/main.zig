/// PoC 08: RenderState Re-injection
///
/// Proves that:
/// 1. FlatCell data extracted from Terminal A can be re-injected into a
///    completely separate Terminal B using the high-level print/setAttribute API
/// 2. The re-injected Terminal B produces identical RenderState cell data
/// 3. Round-trip performance (export → reinject → re-export) is measured
///
/// This validates the full server→wire→client pipeline for the it-shell3
/// protocol: the server extracts RenderState, serializes to FlatCell[],
/// the client receives it and feeds it into a fresh ghostty Terminal
/// for GPU rendering.
const std = @import("std");
const vt = @import("ghostty-vt");

const Terminal = vt.Terminal;
const RenderState = vt.RenderState;
const FlatCell = vt.render_export.FlatCell;
const PackedColor = vt.render_export.PackedColor;
const ExportResult = vt.render_export.ExportResult;
const bulkExport = vt.render_export.bulkExport;
const freeExport = vt.render_export.freeExport;

const print = std.debug.print;

const BENCH_ITERS = 1000;

pub fn main() !void {
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const alloc = gpa_state.allocator();

    print("=== PoC 08: RenderState Re-injection ===\n\n", .{});

    // Phase 1: Correctness
    print("--- Phase 1: Correctness Verification ---\n\n", .{});
    try verifyReinjection(alloc);

    // Phase 2: Performance
    print("\n--- Phase 2: Round-trip Performance ---\n", .{});
    print("{} iterations per size\n\n", .{BENCH_ITERS});

    print("{s:<25} {s:>10} {s:>12} {s:>12} {s:>12}\n", .{
        "Size", "Cells", "export us", "reinj us", "total us",
    });
    print("{s:-<25} {s:->10} {s:->12} {s:->12} {s:->12}\n", .{
        "", "", "", "", "",
    });

    const sizes = [_]struct { cols: vt.size.CellCountInt, rows: vt.size.CellCountInt, label: []const u8 }{
        .{ .cols = 80, .rows = 24, .label = "80x24 (standard)" },
        .{ .cols = 120, .rows = 40, .label = "120x40 (large)" },
        .{ .cols = 200, .rows = 50, .label = "200x50 (wide)" },
    };

    for (sizes) |sz| {
        try benchmarkRoundtrip(alloc, sz.cols, sz.rows, sz.label);
    }

    print("\n=== PoC 08 COMPLETE ===\n", .{});
}

// ─── Phase 1: Correctness ───────────────────────────────────────────

fn verifyReinjection(alloc: std.mem.Allocator) !void {
    // Source terminal with mixed content
    var term_a = try Terminal.init(alloc, .{ .cols = 80, .rows = 24 });
    defer term_a.deinit(alloc);
    try fillSourceTerminal(&term_a);

    // Export from A
    var state_a: RenderState = .empty;
    defer state_a.deinit(alloc);
    var export_a = try bulkExport(alloc, &state_a, &term_a);
    defer freeExport(alloc, &export_a);

    print("  Source: {}x{} = {} cells\n", .{
        export_a.cols, export_a.rows,
        @as(usize, export_a.cols) * @as(usize, export_a.rows),
    });

    // Destination terminal — completely separate instance
    var term_b = try Terminal.init(alloc, .{ .cols = 80, .rows = 24 });
    defer term_b.deinit(alloc);

    // Re-inject
    try reinject(&term_b, export_a.cells, export_a.rows, export_a.cols);

    // Export from B
    var state_b: RenderState = .empty;
    defer state_b.deinit(alloc);
    var export_b = try bulkExport(alloc, &state_b, &term_b);
    defer freeExport(alloc, &export_b);

    // Cell-by-cell comparison
    const total = @as(usize, export_a.rows) * @as(usize, export_a.cols);
    var match: usize = 0;
    var mismatch: usize = 0;
    var both_empty: usize = 0;

    for (0..total) |i| {
        const ca = export_a.cells[i];
        const cb = export_b.cells[i];

        if (ca.codepoint == 0 and cb.codepoint == 0) {
            both_empty += 1;
            continue;
        }

        if (ca.codepoint == cb.codepoint and
            ca.wide == cb.wide and
            ca.flags == cb.flags and
            eqlColor(ca.fg, cb.fg) and
            eqlColor(ca.bg, cb.bg))
        {
            match += 1;
        } else {
            mismatch += 1;
            if (mismatch <= 5) {
                const row = i / export_a.cols;
                const col = i % export_a.cols;
                print("  MISMATCH ({},{}):\n", .{ row, col });
                print("    A: U+{X:0>4} w={} fl=0x{X:0>4} fg={}/{}/{}/{} bg={}/{}/{}/{}\n", .{
                    ca.codepoint, ca.wide, ca.flags,
                    ca.fg.tag,    ca.fg.r,    ca.fg.g,    ca.fg.b,
                    ca.bg.tag,    ca.bg.r,    ca.bg.g,    ca.bg.b,
                });
                print("    B: U+{X:0>4} w={} fl=0x{X:0>4} fg={}/{}/{}/{} bg={}/{}/{}/{}\n", .{
                    cb.codepoint, cb.wide, cb.flags,
                    cb.fg.tag,    cb.fg.r,    cb.fg.g,    cb.fg.b,
                    cb.bg.tag,    cb.bg.r,    cb.bg.g,    cb.bg.b,
                });
            }
        }
    }

    print("\n  Total: {}  Empty: {}  Match: {}  Mismatch: {}\n", .{
        total, both_empty, match, mismatch,
    });

    if (mismatch == 0) {
        print("  *** ALL CELLS MATCH — Re-injection PASSED ***\n", .{});
    } else {
        print("  *** {} MISMATCHES — Re-injection FAILED ***\n", .{mismatch});
    }

    // Verify specific rows for extra confidence
    print("\n  Row-level checks:\n", .{});

    // Row 0: ASCII
    const r0 = export_b.cells[0..80];
    std.debug.assert(r0[0].codepoint == 'H');
    std.debug.assert(r0[4].codepoint == 'o');
    print("    Row 0 ASCII: '{c}{c}{c}{c}{c}...' OK\n", .{
        @as(u8, @intCast(r0[0].codepoint)),
        @as(u8, @intCast(r0[1].codepoint)),
        @as(u8, @intCast(r0[2].codepoint)),
        @as(u8, @intCast(r0[3].codepoint)),
        @as(u8, @intCast(r0[4].codepoint)),
    });

    // Row 1: Korean wide
    const r1 = export_b.cells[80..160];
    std.debug.assert(r1[0].codepoint == 0xD55C);
    std.debug.assert(r1[0].wide == 1); // wide
    std.debug.assert(r1[1].wide == 2); // spacer_tail
    print("    Row 1 Korean: U+{X:0>4} wide={} spacer={} OK\n", .{
        r1[0].codepoint, r1[0].wide, r1[1].wide,
    });

    // Row 2: Bold red
    const r2 = export_b.cells[160..240];
    std.debug.assert(r2[0].codepoint == 'B');
    std.debug.assert(r2[0].fg.tag == 2); // RGB
    std.debug.assert(r2[0].fg.r == 255);
    std.debug.assert(r2[0].fg.g == 0);
    std.debug.assert(r2[0].flags & 1 == 1); // bold
    print("    Row 2 Bold Red: fg=rgb({},{},{}) bold={} OK\n", .{
        r2[0].fg.r, r2[0].fg.g, r2[0].fg.b, r2[0].flags & 1 == 1,
    });

    // Row 3: Italic green on blue
    const r3 = export_b.cells[240..320];
    std.debug.assert(r3[0].codepoint == 'I');
    std.debug.assert(r3[0].fg.tag == 2 and r3[0].fg.g == 255);
    std.debug.assert(r3[0].bg.tag == 2 and r3[0].bg.b == 128);
    std.debug.assert(r3[0].flags & 2 == 2); // italic
    print("    Row 3 Italic Green/Blue: fg=rgb({},{},{}) bg=rgb({},{},{}) italic={} OK\n", .{
        r3[0].fg.r, r3[0].fg.g, r3[0].fg.b,
        r3[0].bg.r, r3[0].bg.g, r3[0].bg.b,
        r3[0].flags & 2 == 2,
    });

    // Row 5: Palette colors
    const r5 = export_b.cells[400..480];
    std.debug.assert(r5[0].codepoint == 'P');
    std.debug.assert(r5[0].fg.tag == 1); // palette
    std.debug.assert(r5[0].fg.r == 196); // palette index
    std.debug.assert(r5[0].bg.tag == 1);
    std.debug.assert(r5[0].bg.r == 21);
    print("    Row 5 Palette: fg=palette({}) bg=palette({}) OK\n", .{
        r5[0].fg.r, r5[0].bg.r,
    });
}

fn fillSourceTerminal(term: *Terminal) !void {
    // Row 0: Plain ASCII
    for ("Hello, it-shell3! PoC 08 re-injection test.") |c| try term.print(c);
    term.carriageReturn();
    try term.linefeed();

    // Row 1: Korean wide characters
    for ([_]u21{ 0xD55C, 0xAE00, ' ', 0xD14C, 0xC2A4, 0xD2B8 }) |cp| try term.print(cp);
    term.carriageReturn();
    try term.linefeed();

    // Row 2: Bold + red fg
    try term.setAttribute(.bold);
    try term.setAttribute(.{ .direct_color_fg = .{ .r = 255, .g = 0, .b = 0 } });
    for ("Bold Red Text") |c| try term.print(c);
    try term.setAttribute(.unset);
    term.carriageReturn();
    try term.linefeed();

    // Row 3: Italic + green fg + blue bg
    try term.setAttribute(.italic);
    try term.setAttribute(.{ .direct_color_fg = .{ .r = 0, .g = 255, .b = 0 } });
    try term.setAttribute(.{ .direct_color_bg = .{ .r = 0, .g = 0, .b = 128 } });
    for ("Italic Green/Blue") |c| try term.print(c);
    try term.setAttribute(.unset);
    term.carriageReturn();
    try term.linefeed();

    // Row 4: Mixed — styled ASCII + Korean
    try term.setAttribute(.{ .direct_color_fg = .{ .r = 255, .g = 128, .b = 0 } });
    for ("Orange: ") |c| try term.print(c);
    for ([_]u21{ 0xD55C, 0xAE00, 0xD14C, 0xC2A4, 0xD2B8 }) |cp| try term.print(cp);
    try term.setAttribute(.unset);
    term.carriageReturn();
    try term.linefeed();

    // Row 5: Palette colors (256-color)
    try term.setAttribute(.{ .@"256_fg" = 196 });
    try term.setAttribute(.{ .@"256_bg" = 21 });
    for ("Palette 196/21") |c| try term.print(c);
    try term.setAttribute(.unset);
}

// ─── Re-injection Algorithm ─────────────────────────────────────────

/// Re-inject FlatCell data into a fresh Terminal instance.
///
/// Uses the high-level Terminal API (setCursorPos + setAttribute + print)
/// to reconstruct the screen content. This is the recommended approach
/// because:
/// - print() automatically handles wide characters (spacer_tail generation)
/// - setAttribute() correctly manages the page-local StyleSet
/// - No direct page.Cell manipulation needed
fn reinject(term: *Terminal, cells: [*]FlatCell, rows: u16, cols: u16) !void {
    var cur_fg = PackedColor{};
    var cur_bg = PackedColor{};
    var cur_flags: u16 = 0;
    var style_set = false;

    for (0..rows) |y| {
        var cursor_x: usize = 0;
        var row_started = false;

        for (0..cols) |x| {
            const cell = cells[y * cols + x];

            // Skip spacer cells — auto-generated by print() for wide chars
            if (cell.wide == 2 or cell.wide == 3) continue;

            // Skip empty cells
            if (cell.codepoint == 0) continue;

            // Position cursor if needed
            if (!row_started or cursor_x != x) {
                term.setCursorPos(@intCast(y + 1), @intCast(x + 1));
                cursor_x = x;
                row_started = true;
            }

            // Update style only when it changes (minimize setAttribute calls)
            if (!style_set or
                cell.flags != cur_flags or
                !eqlColor(cell.fg, cur_fg) or
                !eqlColor(cell.bg, cur_bg))
            {
                try term.setAttribute(.unset);
                try applyStyle(term, cell);
                cur_flags = cell.flags;
                cur_fg = cell.fg;
                cur_bg = cell.bg;
                style_set = true;
            }

            // Print codepoint — handles wide char mechanics automatically
            try term.print(@intCast(cell.codepoint));
            cursor_x += if (cell.wide == 1) @as(usize, 2) else @as(usize, 1);
        }
    }
}

/// Apply FlatCell style to the terminal pen state.
/// Called after setAttribute(.unset) has cleared all attributes.
fn applyStyle(term: *Terminal, cell: FlatCell) !void {
    // Style flags — bit positions match Style.Flags packed struct(u16):
    //   0=bold, 1=italic, 2=faint, 3=blink, 4=inverse,
    //   5=invisible, 6=strikethrough, 7=overline, 8-10=underline(u3)
    if (cell.flags & 0x0001 != 0) try term.setAttribute(.bold);
    if (cell.flags & 0x0002 != 0) try term.setAttribute(.italic);
    if (cell.flags & 0x0004 != 0) try term.setAttribute(.faint);
    if (cell.flags & 0x0008 != 0) try term.setAttribute(.blink);
    if (cell.flags & 0x0010 != 0) try term.setAttribute(.inverse);
    if (cell.flags & 0x0020 != 0) try term.setAttribute(.invisible);
    if (cell.flags & 0x0040 != 0) try term.setAttribute(.strikethrough);
    if (cell.flags & 0x0080 != 0) try term.setAttribute(.overline);

    const underline_val: u3 = @intCast((cell.flags >> 8) & 0x7);
    if (underline_val != 0) {
        try term.setAttribute(.{ .underline = @enumFromInt(underline_val) });
    }

    // Foreground color
    switch (cell.fg.tag) {
        1 => try term.setAttribute(.{ .@"256_fg" = cell.fg.r }),
        2 => try term.setAttribute(.{ .direct_color_fg = .{
            .r = cell.fg.r, .g = cell.fg.g, .b = cell.fg.b,
        } }),
        else => {},
    }

    // Background color
    switch (cell.bg.tag) {
        1 => try term.setAttribute(.{ .@"256_bg" = cell.bg.r }),
        2 => try term.setAttribute(.{ .direct_color_bg = .{
            .r = cell.bg.r, .g = cell.bg.g, .b = cell.bg.b,
        } }),
        else => {},
    }
}

fn eqlColor(a: PackedColor, b: PackedColor) bool {
    return a.tag == b.tag and a.r == b.r and a.g == b.g and a.b == b.b;
}

// ─── Phase 2: Performance ───────────────────────────────────────────

fn benchmarkRoundtrip(
    alloc: std.mem.Allocator,
    cols: vt.size.CellCountInt,
    rows: vt.size.CellCountInt,
    label: []const u8,
) !void {
    // Source terminal
    var term_src = try Terminal.init(alloc, .{ .cols = cols, .rows = rows });
    defer term_src.deinit(alloc);
    fillBench(&term_src, cols, rows) catch {};

    var state_src: RenderState = .empty;
    defer state_src.deinit(alloc);
    var export_src = try bulkExport(alloc, &state_src, &term_src);
    defer freeExport(alloc, &export_src);

    // Warmup
    for (0..100) |_| {
        var td = try Terminal.init(alloc, .{ .cols = cols, .rows = rows });
        reinject(&td, export_src.cells, export_src.rows, export_src.cols) catch {};
        var sd: RenderState = .empty;
        var ed = bulkExport(alloc, &sd, &td) catch {
            sd.deinit(alloc);
            td.deinit(alloc);
            continue;
        };
        freeExport(alloc, &ed);
        sd.deinit(alloc);
        td.deinit(alloc);
    }

    // Benchmark
    var export_ns: u64 = 0;
    var reinject_ns: u64 = 0;

    for (0..BENCH_ITERS) |_| {
        var td = try Terminal.init(alloc, .{ .cols = cols, .rows = rows });

        const t0 = std.time.nanoTimestamp();
        reinject(&td, export_src.cells, export_src.rows, export_src.cols) catch {};
        const t1 = std.time.nanoTimestamp();

        var sd: RenderState = .empty;
        var ed = try bulkExport(alloc, &sd, &td);
        const t2 = std.time.nanoTimestamp();

        freeExport(alloc, &ed);
        sd.deinit(alloc);
        td.deinit(alloc);

        reinject_ns += @intCast(t1 - t0);
        export_ns += @intCast(t2 - t1);
    }

    const total_cells: usize = @as(usize, cols) * @as(usize, rows);
    const export_us = export_ns / BENCH_ITERS / 1000;
    const reinject_us = reinject_ns / BENCH_ITERS / 1000;

    print("{s:<25} {d:>10} {d:>12} {d:>12} {d:>12}\n", .{
        label, total_cells, export_us, reinject_us, export_us + reinject_us,
    });
}

fn fillBench(term: *Terminal, cols: vt.size.CellCountInt, rows: vt.size.CellCountInt) !void {
    for (0..rows) |r| {
        if (r % 3 == 0) try term.setAttribute(.bold);
        if (r % 5 == 0) try term.setAttribute(.{ .direct_color_fg = .{ .r = 200, .g = 100, .b = 50 } });

        const fill_cols = @min(cols, 78);
        for (0..fill_cols) |c| {
            const cp: u21 = if (r % 4 == 1 and c % 3 == 0)
                0xD55C // 한 (wide)
            else
                @intCast('A' + (c + r) % 26);
            try term.print(cp);
        }

        if (r + 1 < rows) {
            term.carriageReturn();
            try term.linefeed();
        }

        if (r % 3 == 0 or r % 5 == 0) try term.setAttribute(.unset);
    }
}
