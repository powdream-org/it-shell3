/// PoC 08: RenderState Direct Population (No Terminal on Client)
///
/// Proves that:
/// 1. FlatCell[] data can directly populate a RenderState WITHOUT a Terminal
/// 2. The populated RenderState produces identical cell data when re-exported
/// 3. This validates the client-side rendering path for the it-shell3 protocol:
///    Server: Terminal → update() → bulkExport() → FlatCell[] → wire
///    Client: wire → FlatCell[] → importFlatCells() → RenderState → rebuildCells() → GPU
///
/// The client never creates a Terminal instance.
const std = @import("std");
const vt = @import("ghostty-vt");

const Terminal = vt.Terminal;
const RenderState = vt.RenderState;
const FlatCell = vt.render_export.FlatCell;
const PackedColor = vt.render_export.PackedColor;
const ExportResult = vt.render_export.ExportResult;
const bulkExport = vt.render_export.bulkExport;
const importFlatCells = vt.render_export.importFlatCells;
const flattenExport = vt.render_export.flattenExport;
const freeExport = vt.render_export.freeExport;

const print = std.debug.print;

const BENCH_ITERS = 1000;
const WARMUP_ITERS = 100;

pub fn main() !void {
    var gpa_state: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const alloc = gpa_state.allocator();

    print("=== PoC 08: RenderState Direct Population ===\n\n", .{});

    // Phase 1: Correctness
    print("--- Phase 1: Correctness Verification ---\n\n", .{});
    try verifyDirectPopulation(alloc);

    // Phase 2: Performance
    print("\n--- Phase 2: Import Performance ---\n", .{});
    print("{} warmup + {} bench iterations\n\n", .{ WARMUP_ITERS, BENCH_ITERS });

    print("{s:<25} {s:>10} {s:>12} {s:>12} {s:>12}\n", .{
        "Size", "Cells", "import us", "flatten us", "total us",
    });
    print("{s:-<25} {s:->10} {s:->12} {s:->12} {s:->12}\n", .{
        "", "", "", "", "",
    });

    const sizes = [_]struct { cols: vt.size.CellCountInt, rows: vt.size.CellCountInt, label: []const u8 }{
        .{ .cols = 80, .rows = 24, .label = "80x24 (standard)" },
        .{ .cols = 120, .rows = 40, .label = "120x40 (large)" },
        .{ .cols = 200, .rows = 50, .label = "200x50 (wide)" },
        .{ .cols = 300, .rows = 80, .label = "300x80 (ultra)" },
    };

    for (sizes) |sz| {
        try benchmarkImport(alloc, sz.cols, sz.rows, sz.label);
    }

    print("\n=== PoC 08 COMPLETE ===\n", .{});
}

// ─── Phase 1: Correctness ───────────────────────────────────────────

fn verifyDirectPopulation(alloc: std.mem.Allocator) !void {
    // SERVER SIDE: Create terminal, fill, export
    var term = try Terminal.init(alloc, .{ .cols = 80, .rows = 24 });
    defer term.deinit(alloc);
    try fillSourceTerminal(&term);

    var state_server: RenderState = .empty;
    defer state_server.deinit(alloc);
    var export_server = try bulkExport(alloc, &state_server, &term);
    defer freeExport(alloc, &export_server);

    print("  Server: {}x{} = {} cells exported\n", .{
        export_server.cols, export_server.rows,
        @as(usize, export_server.cols) * @as(usize, export_server.rows),
    });

    // CLIENT SIDE: No Terminal — populate RenderState directly from FlatCell[]
    var state_client: RenderState = .empty;
    defer state_client.deinit(alloc);

    try importFlatCells(alloc, &state_client, &export_server);

    print("  Client: RenderState populated directly (no Terminal)\n", .{});

    // Re-export from client RenderState (flatten only, no update)
    var export_client = try flattenExport(alloc, &state_client);
    defer freeExport(alloc, &export_client);

    // Compare cell-by-cell
    const total = @as(usize, export_server.rows) * @as(usize, export_server.cols);
    var match: usize = 0;
    var mismatch: usize = 0;
    var both_empty: usize = 0;

    for (0..total) |i| {
        const cs = export_server.cells[i];
        const cc = export_client.cells[i];

        if (cs.codepoint == 0 and cc.codepoint == 0) {
            both_empty += 1;
            continue;
        }

        if (cs.codepoint == cc.codepoint and
            cs.wide == cc.wide and
            cs.flags == cc.flags and
            eqlColor(cs.fg, cc.fg) and
            eqlColor(cs.bg, cc.bg))
        {
            match += 1;
        } else {
            mismatch += 1;
            if (mismatch <= 5) {
                const row = i / export_server.cols;
                const col = i % export_server.cols;
                print("  MISMATCH ({},{}):\n", .{ row, col });
                print("    Server: U+{X:0>4} w={} fl=0x{X:0>4} fg={}/{}/{}/{} bg={}/{}/{}/{}\n", .{
                    cs.codepoint, cs.wide, cs.flags,
                    cs.fg.tag, cs.fg.r, cs.fg.g, cs.fg.b,
                    cs.bg.tag, cs.bg.r, cs.bg.g, cs.bg.b,
                });
                print("    Client: U+{X:0>4} w={} fl=0x{X:0>4} fg={}/{}/{}/{} bg={}/{}/{}/{}\n", .{
                    cc.codepoint, cc.wide, cc.flags,
                    cc.fg.tag, cc.fg.r, cc.fg.g, cc.fg.b,
                    cc.bg.tag, cc.bg.r, cc.bg.g, cc.bg.b,
                });
            }
        }
    }

    print("\n  Total: {}  Empty: {}  Match: {}  Mismatch: {}\n", .{
        total, both_empty, match, mismatch,
    });

    if (mismatch == 0) {
        print("  *** ALL CELLS MATCH — Direct population PASSED ***\n", .{});
    } else {
        print("  *** {} MISMATCHES — Direct population FAILED ***\n", .{mismatch});
        return;
    }

    // Row-level spot checks on the CLIENT-side RenderState
    print("\n  Row-level checks (from client RenderState):\n", .{});

    const r0 = export_client.cells[0..80];
    std.debug.assert(r0[0].codepoint == 'H');
    print("    Row 0 ASCII: '{c}{c}{c}{c}{c}...' OK\n", .{
        @as(u8, @intCast(r0[0].codepoint)),
        @as(u8, @intCast(r0[1].codepoint)),
        @as(u8, @intCast(r0[2].codepoint)),
        @as(u8, @intCast(r0[3].codepoint)),
        @as(u8, @intCast(r0[4].codepoint)),
    });

    const r1 = export_client.cells[80..160];
    std.debug.assert(r1[0].codepoint == 0xD55C);
    std.debug.assert(r1[0].wide == 1);
    std.debug.assert(r1[1].wide == 2);
    print("    Row 1 Korean: U+{X:0>4} wide={} spacer={} OK\n", .{
        r1[0].codepoint, r1[0].wide, r1[1].wide,
    });

    const r2 = export_client.cells[160..240];
    std.debug.assert(r2[0].codepoint == 'B');
    std.debug.assert(r2[0].fg.tag == 2 and r2[0].fg.r == 255);
    std.debug.assert(r2[0].flags & 1 == 1); // bold
    print("    Row 2 Bold Red: fg=rgb({},{},{}) bold={} OK\n", .{
        r2[0].fg.r, r2[0].fg.g, r2[0].fg.b, r2[0].flags & 1 == 1,
    });

    const r5 = export_client.cells[400..480];
    std.debug.assert(r5[0].codepoint == 'P');
    std.debug.assert(r5[0].fg.tag == 1 and r5[0].fg.r == 196);
    std.debug.assert(r5[0].bg.tag == 1 and r5[0].bg.r == 21);
    print("    Row 5 Palette: fg=palette({}) bg=palette({}) OK\n", .{
        r5[0].fg.r, r5[0].bg.r,
    });
}

fn fillSourceTerminal(term: *Terminal) !void {
    // Row 0: Plain ASCII
    for ("Hello, it-shell3! PoC 08 direct population.") |c| try term.print(c);
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

fn eqlColor(a: PackedColor, b: PackedColor) bool {
    return a.tag == b.tag and a.r == b.r and a.g == b.g and a.b == b.b;
}

// ─── Phase 2: Performance ───────────────────────────────────────────

fn benchmarkImport(
    alloc: std.mem.Allocator,
    cols: vt.size.CellCountInt,
    rows: vt.size.CellCountInt,
    label: []const u8,
) !void {
    // Create source data (server side)
    var term = try Terminal.init(alloc, .{ .cols = cols, .rows = rows });
    defer term.deinit(alloc);
    fillBench(&term, cols, rows) catch {};

    var state_src: RenderState = .empty;
    defer state_src.deinit(alloc);
    var export_src = try bulkExport(alloc, &state_src, &term);
    defer freeExport(alloc, &export_src);

    // Client-side RenderState — reused across iterations
    var state_client: RenderState = .empty;
    defer state_client.deinit(alloc);

    // Warmup
    for (0..WARMUP_ITERS) |_| {
        try importFlatCells(alloc, &state_client, &export_src);
        var ex = try flattenExport(alloc, &state_client);
        freeExport(alloc, &ex);
    }

    // Benchmark
    var import_ns: u64 = 0;
    var flatten_ns: u64 = 0;

    for (0..BENCH_ITERS) |_| {
        const t0 = std.time.nanoTimestamp();
        try importFlatCells(alloc, &state_client, &export_src);
        const t1 = std.time.nanoTimestamp();

        var ex = try flattenExport(alloc, &state_client);
        const t2 = std.time.nanoTimestamp();

        freeExport(alloc, &ex);

        import_ns += @intCast(t1 - t0);
        flatten_ns += @intCast(t2 - t1);
    }

    const total_cells: usize = @as(usize, cols) * @as(usize, rows);
    const import_us = import_ns / BENCH_ITERS / 1000;
    const flatten_us = flatten_ns / BENCH_ITERS / 1000;

    print("{s:<25} {d:>10} {d:>12} {d:>12} {d:>12}\n", .{
        label, total_cells, import_us, flatten_us, import_us + flatten_us,
    });
}

fn fillBench(term: *Terminal, cols: vt.size.CellCountInt, rows: vt.size.CellCountInt) !void {
    for (0..rows) |r| {
        if (r % 3 == 0) try term.setAttribute(.bold);
        if (r % 5 == 0) try term.setAttribute(.{ .direct_color_fg = .{ .r = 200, .g = 100, .b = 50 } });

        const fill_cols = @min(cols, 78);
        for (0..fill_cols) |c| {
            const cp: u21 = if (r % 4 == 1 and c % 3 == 0)
                0xD55C
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
